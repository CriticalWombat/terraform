terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.70.0"
    }
  }
}

# ============================================
# CLIENT VMS
# ============================================

locals {
  client_vms = {
    for i in range(var.client_count) :
    "WIN10-${i + 1}" => {
      cores    = 2
      memory   = 4096
      disk     = 32
      temp_ip  = "${var.client_ip_prefix}${151 + i}"
      final_ip = "${var.client_ip_prefix}${11 + i}"
      netmask  = 24
    }
  }
}

resource "proxmox_virtual_environment_vm" "clients" {
  for_each = local.client_vms

  name      = each.key
  node_name = var.node_name
  vm_id     = 200 + index(keys(local.client_vms), each.key)

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
    bridge = "vmbr1"
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

  lifecycle {
    ignore_changes = [clone]
  }
}

resource "time_sleep" "wait_for_boot" {
  depends_on      = [proxmox_virtual_environment_vm.clients]
  create_duration = "90s"
}

# ============================================
# SET STATIC IPs
# ============================================

resource "null_resource" "upload_ip_script" {
  for_each = local.client_vms

  depends_on = [time_sleep.wait_for_boot]

  triggers = {
    vm_id       = proxmox_virtual_environment_vm.clients[each.key].id
    script_hash = filemd5("${var.scripts_path}/set-static-ip.ps1")
  }

  connection {
    type     = "winrm"
    host     = each.value.temp_ip
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
    source      = "${var.scripts_path}/set-static-ip.ps1"
    destination = "C:\\terraform-scripts\\set-static-ip.ps1"
  }
}

resource "null_resource" "set_static_ip" {
  for_each = local.client_vms

  depends_on = [
    null_resource.upload_ip_script
  ]

  triggers = {
    vm_id      = proxmox_virtual_environment_vm.clients[each.key].id
    final_ip   = each.value.final_ip
    dc_verified = var.dc_verified  # Ensures DC is ready
  }

  connection {
    type     = "winrm"
    host     = each.value.temp_ip
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
      # Use DC IP dynamically!
      "powershell.exe -ExecutionPolicy Bypass -File C:\\terraform-scripts\\set-static-ip.ps1 -IPAddress '${each.value.final_ip}' -PrefixLength ${each.value.netmask} -DefaultGateway '${var.gateway}' -DnsServers '${var.dc_ip}','1.1.1.1'"
    ]
  }
}

resource "time_sleep" "wait_after_ip_change" {
  depends_on      = [null_resource.set_static_ip]
  create_duration = "30s"
}

# ============================================
# DOMAIN JOIN
# ============================================

resource "null_resource" "upload_scripts" {
  for_each = local.client_vms

  depends_on = [time_sleep.wait_after_ip_change]

  triggers = {
    vm_id       = proxmox_virtual_environment_vm.clients[each.key].id
    script_hash = filemd5("${var.scripts_path}/join-domain.ps1")
  }

  connection {
    type     = "winrm"
    host     = each.value.final_ip
    user     = var.admin_username
    password = var.admin_password
    port     = 5986
    https    = true
    insecure = true
    timeout  = "10m"
    use_ntlm = true
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

resource "null_resource" "configure_winrm" {
  for_each = local.client_vms

  depends_on = [null_resource.upload_scripts]

  triggers = {
    vm_id = proxmox_virtual_environment_vm.clients[each.key].id
  }

  connection {
    type     = "winrm"
    host     = each.value.final_ip
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
    host     = each.value.final_ip
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