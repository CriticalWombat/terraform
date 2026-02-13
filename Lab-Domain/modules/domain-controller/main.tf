terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.95.0"
    }
  }
}

# ============================================
# DOMAIN CONTROLLER VM
# ============================================

resource "proxmox_virtual_environment_vm" "dc" {
  name      = var.vm_name
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
    bridge = "vmbr0"
    model  = "virtio"
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = 48
  }

  agent {
    enabled = true
    timeout = "120s"
    wait_for_ip {
      ipv4 = true
    }
  }

  lifecycle {
    ignore_changes = [clone]
  }
}

# Wait for VM to boot and guest agent to report IP
resource "time_sleep" "wait_for_boot" {
  depends_on      = [proxmox_virtual_environment_vm.dc]
  create_duration = "5m"
}

# Extract DHCP IP from guest agent
locals {
  dc_ip = proxmox_virtual_environment_vm.dc.ipv4_addresses[0][0]
}

# ============================================
# DC PROMOTION
# ============================================

resource "null_resource" "upload_scripts" {
  depends_on = [time_sleep.wait_for_boot]

  triggers = {
    vm_id       = proxmox_virtual_environment_vm.dc.id
    script_hash = filemd5("${var.scripts_path}/promote-dc.ps1")
    dc_ip       = local.dc_ip
  }

  connection {
    type     = "winrm"
    host     = local.dc_ip
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
      "powershell.exe -Command \"Write-Host 'Connected to DC at ${local.dc_ip}'\"",
      "powershell.exe -Command \"New-Item -ItemType Directory -Force -Path C:\\terraform-scripts\""
    ]
  }

  provisioner "file" {
    source      = "${var.scripts_path}/promote-dc.ps1"
    destination = "C:\\terraform-scripts\\promote-dc.ps1"
  }

  provisioner "file" {
    source      = "${var.scripts_path}/verify-dc.ps1"
    destination = "C:\\terraform-scripts\\verify-dc.ps1"
  }
}

resource "null_resource" "install_adds_role" {
  depends_on = [null_resource.upload_scripts]

  triggers = {
    vm_id = proxmox_virtual_environment_vm.dc.id
  }

  connection {
    type     = "winrm"
    host     = local.dc_ip
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
      "powershell.exe -ExecutionPolicy Bypass -Command \"if ((Get-WindowsFeature -Name AD-Domain-Services).InstallState -ne 'Installed') { Write-Host 'Installing AD DS Role...'; Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools; Write-Host 'AD DS Role installed successfully' } else { Write-Host 'AD DS Role already installed' }\""
    ]
  }
}

resource "null_resource" "promote_dc" {
  depends_on = [null_resource.install_adds_role]

  triggers = {
    vm_id       = proxmox_virtual_environment_vm.dc.id
    script_hash = filemd5("${var.scripts_path}/promote-dc.ps1")
  }

  connection {
    type     = "winrm"
    host     = local.dc_ip
    user     = var.admin_username
    password = var.admin_password
    port     = 5986
    https    = true
    insecure = true
    timeout  = "30m"
    use_ntlm = true
  }

  provisioner "remote-exec" {
    inline = [
      "powershell.exe -ExecutionPolicy Bypass -File C:\\terraform-scripts\\promote-dc.ps1 -DomainName ${var.domain_name} -NetBiosName ${var.domain_netbios_name} -SafeModePassword ${var.safe_mode_password}"
    ]
  }
}

resource "time_sleep" "wait_for_promotion" {
  depends_on      = [null_resource.promote_dc]
  create_duration = "5m"
}

resource "null_resource" "verify_dc" {
  depends_on = [time_sleep.wait_for_promotion]

  triggers = {
    dc_promotion = null_resource.promote_dc.id
  }

  connection {
    type     = "winrm"
    host     = local.dc_ip
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
      "powershell.exe -ExecutionPolicy Bypass -File C:\\terraform-scripts\\verify-dc.ps1"
    ]
  }
}