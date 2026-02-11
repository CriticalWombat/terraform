terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.95.0"
    }
  }
}

# ============================================
# LOCALS - Client VM Configuration
# ============================================

locals {
  # Create client VM config (IPs will be discovered)
  client_vms = {
    for i in range(var.client_count) :
    "WIN10-${i + 1}" => {
      vm_id  = 200 + i
      cores  = 2
      memory = 4096
      disk   = 32
    }
  }
}

# ============================================
# CLIENT VMS
# ============================================

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
    timeout = "60s"
  }

  lifecycle {
    ignore_changes = [clone]
  }
}

resource "time_sleep" "wait_for_boot" {
  depends_on      = [proxmox_virtual_environment_vm.clients]
  create_duration = "180s"
}

# Extract DHCP IPs from guest agent for each client
locals {
  client_ips = {
    for name, vm in proxmox_virtual_environment_vm.clients :
    name => vm.ipv4_addresses[0][0]
  }
}

# ============================================
# UPLOAD SCRIPTS
# ============================================

resource "null_resource" "upload_scripts" {
  for_each = local.client_vms

  depends_on = [
    time_sleep.wait_for_boot,
    var.dc_verified
  ]

  triggers = {
    vm_id       = proxmox_virtual_environment_vm.clients[each.key].id
    script_hash = filemd5("${var.scripts_path}/join-domain.ps1")
    client_ip   = local.client_ips[each.key]
  }

  connection {
    type     = "winrm"
    host     = local.client_ips[each.key]  # Dynamic DHCP IP!
    user     = var.admin_username
    password = var.admin_password
    port     = 5986
    https    = true
    insecure = true
    timeout  = "10m"
    use_ntlm = true
  }

  provisioner "remote-exec" {
    inline = [
      "powershell.exe -Command \"Write-Host 'Connected to ${each.key} at ${local.client_ips[each.key]}'\"",
      "powershell.exe -Command \"New-Item -ItemType Directory -Force -Path C:\\terraform-scripts\""
    ]
  }

  provisioner "file" {
    source      = "${var.scripts_path}/configure-winrm.ps1"
    destination = "C:\\terraform-scripts\\configure-winrm.ps1"
  }

  provisioner "file" {
    source      = "${var.scripts_path}/join-domain.ps1"
    destination = "C:\\terraform-scripts\\join-domain.ps1"
  }
}

# ============================================
# CONFIGURE DNS TO POINT TO DC
# ============================================

resource "null_resource" "configure_dns" {
  for_each = local.client_vms

  depends_on = [null_resource.upload_scripts]

  triggers = {
    vm_id = proxmox_virtual_environment_vm.clients[each.key].id
    dc_ip = var.dc_ip
  }

  connection {
    type     = "winrm"
    host     = local.client_ips[each.key]
    user     = var.admin_username
    password = var.admin_password
    port     = 5986
    https    = true
    insecure = true
    timeout  = "10m"
    use_ntlm = true
  }

  provisioner "remote-exec" {
    inline = [
      "powershell.exe -ExecutionPolicy Bypass -Command \"Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | Set-DnsClientServerAddress -ServerAddresses '${var.dc_ip}','1.1.1.1'\""
    ]
  }
}

resource "time_sleep" "wait_after_dns" {
  depends_on      = [null_resource.configure_dns]
  create_duration = "30s"
}

# ============================================
# CONFIGURE WINRM
# ============================================

resource "null_resource" "configure_winrm" {
  for_each = local.client_vms

  depends_on = [time_sleep.wait_after_dns]

  triggers = {
    vm_id = proxmox_virtual_environment_vm.clients[each.key].id
  }

  connection {
    type     = "winrm"
    host     = local.client_ips[each.key]
    user     = var.admin_username
    password = var.admin_password
    port     = 5986
    https    = true
    insecure = true
    timeout  = "10m"
    use_ntlm = true
  }

  provisioner "remote-exec" {
    inline = [
      "powershell.exe -ExecutionPolicy Bypass -File C:\\terraform-scripts\\configure-winrm.ps1"
    ]
  }
}

# ============================================
# JOIN DOMAIN
# ============================================

resource "null_resource" "join_domain" {
  for_each = local.client_vms

  depends_on = [null_resource.configure_winrm]

  triggers = {
    vm_id       = proxmox_virtual_environment_vm.clients[each.key].id
    script_hash = filemd5("${var.scripts_path}/join-domain.ps1")
    dc_verified = var.dc_verified
  }

  connection {
    type     = "winrm"
    host     = local.client_ips[each.key]
    user     = var.admin_username
    password = var.admin_password
    port     = 5986
    https    = true
    insecure = true
    timeout  = "15m"
    use_ntlm = true
  }

  provisioner "remote-exec" {
    inline = [
      "powershell.exe -ExecutionPolicy Bypass -File C:\\terraform-scripts\\join-domain.ps1 -DomainName '${var.domain_name}' -DomainUser '${var.admin_username}' -DomainPassword '${var.admin_password}'"
    ]
  }
}