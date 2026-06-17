terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.95"
    }
  }
}

resource "proxmox_virtual_environment_vm" "dc" {
  name      = "DC01"
  node_name = var.node_name
  vm_id     = var.vm_id

  clone {
    vm_id = var.template_id
    full  = false
  }

  cpu {
    cores = 4
  }

  memory {
    dedicated = 8192
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = 80
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

locals {
  dc_ip = [
    for ip in flatten(proxmox_virtual_environment_vm.dc.ipv4_addresses) :
    ip if !startswith(ip, "127.")
  ][0]
}

# Minimum wait before Terraform attempts WinRM. Sysprep first-boot + setup.ps1
# realistically needs 5-10 min. The connection timeout on promote_dc handles
# anything slower by retrying the WinRM connection for up to 30 more minutes.
resource "time_sleep" "wait_for_winrm" {
  depends_on      = [proxmox_virtual_environment_vm.dc]
  create_duration = "5m"
}

# Install AD DS role + promote + reboot
resource "null_resource" "promote_dc" {
  depends_on = [time_sleep.wait_for_winrm]

  triggers = {
    vm_id = proxmox_virtual_environment_vm.dc.id
  }

  connection {
    type     = "winrm"
    host     = local.dc_ip
    user     = "Administrator"
    password = var.admin_password
    port     = 5986
    https    = true
    insecure = true
    timeout  = "30m"
    use_ntlm = true
  }

  provisioner "remote-exec" {
    inline = ["cmd /c mkdir C:\\setup 2>nul || exit 0"]
  }

  provisioner "file" {
    source      = "${path.module}/scripts/promote-dc.ps1"
    destination = "C:\\setup\\promote-dc.ps1"
  }

  provisioner "remote-exec" {
    inline = [
      "powershell.exe -ExecutionPolicy Bypass -File C:\\setup\\promote-dc.ps1 -DomainName ${var.domain_name} -NetBiosName ${var.domain_netbios} -SafeModePassword ${var.safe_mode_password}"
    ]
  }
}

# Wait for the post-promotion reboot to complete AND for AD services (ADWS,
# DNS, Netlogon, KDC) to fully start. On slow storage this takes 8-12 min.
# Profile modules and clients both depend_on this module, so they won't attempt
# any DC connections until after this sleep. The profile scripts add their own
# per-service readiness checks on top of this as a second layer.
resource "time_sleep" "wait_for_reboot" {
  depends_on      = [null_resource.promote_dc]
  create_duration = "10m"
}
