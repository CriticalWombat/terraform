terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.70.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  username  = var.proxmox_username
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  ssh {
    agent    = false
    username = var.proxmox_ssh_username
    password = var.proxmox_ssh_password
  }
}

# ============================================
# MACHINE SPECS
# ============================================

locals {
  # Domain Controller
  dc_vm = {
    AD01 = {
      cores      = 4
      memory     = 8192
      disk       = 48
      ip_address = var.dc_ip_address
      netmask    = 24
      net_bridge = "vmbr1"
      gateway    = var.vmbr1_gateway
    }
  }

  # Windows 10 Clients
  client_vms = {
    for i in range(var.client_count) :
    "WIN10-${i + 1}" => {
      cores      = 2
      memory     = 4096
      disk       = 32
      ip_address = "${var.client_ip_prefix}${i + 10}"  # e.g., 192.168.1.10, .11, .12
      netmask    = 24
      net_bridge = "vmbr1"
      gateway    = var.vmbr1_gateway
    }
  }

  # DNS settings
  dns_primary   = var.dc_ip_address  # DC will be DNS after promotion
  dns_secondary = "1.1.1.1"          # Fallback during setup

  # Domain settings
  domain_name         = var.domain_name
  domain_netbios_name = var.domain_netbios_name
}

# ============================================
# DOMAIN CONTROLLER (Server 2022)
# ============================================

resource "proxmox_virtual_environment_vm" "dc" {
  for_each = local.dc_vm

  name      = each.key
  node_name = var.proxmox_node
  vm_id     = 100  # Specific ID for DC

  clone {
    vm_id = var.server2022_template_id
    full  = false
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
  }

  network_device {
    bridge = each.value.net_bridge
    model  = "virtio"
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = each.value.disk
  }

  agent {
    enabled = true
  }
}

# Wait for VM to be ready
resource "time_sleep" "wait_for_dc_vm" {
  depends_on = [proxmox_virtual_environment_vm.dc]

  create_duration = "60s"  # Wait for VM to boot
}

# ============================================
# DC PROMOTION (Apply 1)
# ============================================

# Upload DC promotion scripts
resource "null_resource" "upload_dc_scripts" {
  depends_on = [time_sleep.wait_for_dc_vm]

  triggers = {
    vm_id       = values(proxmox_virtual_environment_vm.dc)[0].id
    script_hash = filemd5("${path.module}/scripts/promote-dc.ps1")
  }

  connection {
    type     = "winrm"
    host     = var.dc_ip_address
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
      "powershell.exe -Command \"New-Item -ItemType Directory -Force -Path C:\\terraform-scripts\""
    ]
  }

  provisioner "file" {
    source      = "${path.module}/scripts/promote-dc.ps1"
    destination = "C:\\terraform-scripts\\promote-dc.ps1"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/verify-dc.ps1"
    destination = "C:\\terraform-scripts\\verify-dc.ps1"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/configure-winrm.ps1"
    destination = "C:\\terraform-scripts\\configure-winrm.ps1"
  }
}

# Ensure WinRM is properly configured
resource "null_resource" "configure_dc_winrm" {
  depends_on = [null_resource.upload_dc_scripts]

  triggers = {
    vm_id = values(proxmox_virtual_environment_vm.dc)[0].id
  }

  connection {
    type     = "winrm"
    host     = var.dc_ip_address
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

# Install AD DS Role (doesn't require reboot)
resource "null_resource" "install_adds_role" {
  depends_on = [null_resource.configure_dc_winrm]

  triggers = {
    vm_id = values(proxmox_virtual_environment_vm.dc)[0].id
  }

  connection {
    type     = "winrm"
    host     = var.dc_ip_address
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

# Promote to Domain Controller (will reboot)
resource "null_resource" "promote_dc" {
  depends_on = [null_resource.install_adds_role]

  triggers = {
    vm_id       = values(proxmox_virtual_environment_vm.dc)[0].id
    script_hash = filemd5("${path.module}/scripts/promote-dc.ps1")
  }

  connection {
    type     = "winrm"
    host     = var.dc_ip_address
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
      "powershell.exe -ExecutionPolicy Bypass -File C:\\terraform-scripts\\promote-dc.ps1 -DomainName '${local.domain_name}' -NetBiosName '${local.domain_netbios_name}' -SafeModePassword '${var.safe_mode_password}'"
    ]
  }
}

# Wait for DC to be fully operational after reboot
resource "time_sleep" "wait_for_dc_promotion" {
  depends_on = [null_resource.promote_dc]

  create_duration = "5m"  # Wait 5 minutes after promotion
}

# Verify DC is ready
resource "null_resource" "verify_dc" {
  depends_on = [time_sleep.wait_for_dc_promotion]

  triggers = {
    dc_promotion = null_resource.promote_dc.id
  }

  connection {
    type     = "winrm"
    host     = var.dc_ip_address
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

# ============================================
# WINDOWS 10 CLIENTS
# ============================================

resource "proxmox_virtual_environment_vm" "clients" {
  for_each = local.client_vms

  name      = each.key
  node_name = var.proxmox_node
  vm_id     = 200 + index(keys(local.client_vms), each.key)  # 200, 201, 202...

  clone {
    vm_id = var.win10_template_id
    full  = false
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
  }

  network_device {
    bridge = each.value.net_bridge
    model  = "virtio"
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = each.value.disk
  }

  agent {
    enabled = true
  }

  # Cloud-init configuration
  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip_address}/${each.value.netmask}"
        gateway = each.value.gateway
      }
    }

    user_account {
      username = var.admin_username
      password = var.admin_password
    }

    dns {
      servers = [local.dns_secondary]  # Initially use external DNS
    }
  }

  lifecycle {
    ignore_changes = [
      initialization,
    ]
  }
}

# Wait for client VMs to be ready
resource "time_sleep" "wait_for_clients" {
  depends_on = [proxmox_virtual_environment_vm.clients]

  create_duration = "60s"
}

# ============================================
# DOMAIN JOIN (Apply 2)
# ============================================

# Upload domain join scripts to clients
resource "null_resource" "upload_client_scripts" {
  for_each = local.client_vms

  depends_on = [
    time_sleep.wait_for_clients,
    null_resource.verify_dc
  ]

  triggers = {
    vm_id       = proxmox_virtual_environment_vm.clients[each.key].id
    script_hash = filemd5("${path.module}/scripts/join-domain.ps1")
    dc_ready    = null_resource.verify_dc.id
  }

  connection {
    type     = "winrm"
    host     = each.value.ip_address
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
      "powershell.exe -Command \"New-Item -ItemType Directory -Force -Path C:\\terraform-scripts\""
    ]
  }

  provisioner "file" {
    source      = "${path.module}/scripts/configure-winrm.ps1"
    destination = "C:\\terraform-scripts\\configure-winrm.ps1"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/configure-dns.ps1"
    destination = "C:\\terraform-scripts\\configure-dns.ps1"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/join-domain.ps1"
    destination = "C:\\terraform-scripts\\join-domain.ps1"
  }
}

# Ensure WinRM is configured on clients
resource "null_resource" "configure_client_winrm" {
  for_each = local.client_vms

  depends_on = [null_resource.upload_client_scripts]

  triggers = {
    vm_id = proxmox_virtual_environment_vm.clients[each.key].id
  }

  connection {
    type     = "winrm"
    host     = each.value.ip_address
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

# Configure DNS to point to DC
resource "null_resource" "configure_client_dns" {
  for_each = local.client_vms

  depends_on = [null_resource.configure_client_winrm]

  triggers = {
    vm_id    = proxmox_virtual_environment_vm.clients[each.key].id
    dc_ip    = var.dc_ip_address
    dc_ready = null_resource.verify_dc.id
  }

  connection {
    type     = "winrm"
    host     = each.value.ip_address
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
      "powershell.exe -ExecutionPolicy Bypass -File C:\\terraform-scripts\\configure-dns.ps1 -DnsServerIP '${var.dc_ip_address}'"
    ]
  }
}

# Join clients to domain
resource "null_resource" "join_domain" {
  for_each = local.client_vms

  depends_on = [null_resource.configure_client_dns]

  triggers = {
    vm_id       = proxmox_virtual_environment_vm.clients[each.key].id
    dc_ready    = null_resource.verify_dc.id
    script_hash = filemd5("${path.module}/scripts/join-domain.ps1")
  }

  connection {
    type     = "winrm"
    host     = each.value.ip_address
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
      "powershell.exe -ExecutionPolicy Bypass -File C:\\terraform-scripts\\join-domain.ps1 -DomainName '${local.domain_name}' -DomainUser '${var.admin_username}' -DomainPassword '${var.admin_password}'"
    ]
  }
}