terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.95"
    }
  }
}

locals {
  client_vms = {
    for i in range(var.client_count) :
    format("WIN10-%02d", i + 1) => {
      vm_id  = var.vm_id_base + i
      cores  = 4
      memory = 4096
      disk   = 60
    }
  }
}

resource "proxmox_virtual_environment_vm" "clients" {
  for_each = local.client_vms

  name      = each.key
  node_name = var.node_name
  vm_id     = each.value.vm_id

  clone {
    vm_id = var.template_id
    full  = false
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = each.value.disk
  }

  agent {
    enabled = true
    timeout = "1200s"
    wait_for_ip {
      ipv4 = true
    }
  }

  lifecycle {
    ignore_changes = [clone]
  }
}

resource "time_sleep" "wait_for_winrm" {
  depends_on      = [proxmox_virtual_environment_vm.clients]
  create_duration = "5m"
}

locals {
  client_ips = {
    for name, vm in proxmox_virtual_environment_vm.clients :
    name => [
      for ip in flatten(vm.ipv4_addresses) :
      ip if !startswith(ip, "127.")
    ][0]
  }
}

# Set DC as DNS server then join the domain
resource "null_resource" "configure_and_join" {
  for_each = local.client_vms

  depends_on = [time_sleep.wait_for_winrm]

  triggers = {
    vm_id = proxmox_virtual_environment_vm.clients[each.key].id
    dc_ip = var.dc_ip
  }

  connection {
    type     = "winrm"
    host     = local.client_ips[each.key]
    user     = "Administrator"
    password = var.admin_password
    port     = 5985
    https    = false
    timeout  = "30m"
    use_ntlm = true
  }

  provisioner "remote-exec" {
    inline = [
      "cmd /c mkdir C:\\setup 2>nul || exit 0",
      "powershell.exe -Command \"Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | Set-DnsClientServerAddress -ServerAddresses '${var.dc_ip}'\""
    ]
  }

  provisioner "file" {
    source      = "${path.module}/scripts/join-domain.ps1"
    destination = "C:\\setup\\join-domain.ps1"
  }

  provisioner "remote-exec" {
    inline = [
      "powershell.exe -ExecutionPolicy Bypass -File C:\\setup\\join-domain.ps1 -DomainName ${var.domain_name} -DomainUser Administrator@${var.domain_name} -DomainPassword ${var.admin_password}"
    ]
  }
}
