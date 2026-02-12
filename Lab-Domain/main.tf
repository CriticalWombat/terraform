terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.95.0"
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
# DOMAIN CONTROLLER MODULE
# ============================================

module "domain_controller" {
  source = "./modules/domain-controller"

  # VM Configuration
  vm_name      = "AD01"
  vm_id        = 8000
  node_name    = "pve"
  template_id  = 9100
  datastore_id = "zfs-pool1"

  # Credentials
  admin_username = var.admin_username
  admin_password = var.admin_password

  # Domain Configuration
  domain_name         = var.domain_name
  domain_netbios_name = var.domain_netbios_name
  safe_mode_password  = var.safe_mode_password

  # Scripts path
  scripts_path = "${path.root}/scripts"
}

# ============================================
# WINDOWS CLIENTS MODULE
# ============================================

module "windows_clients" {
  source = "./modules/windows-clients"

  # Only create if DC is ready
  depends_on = [module.domain_controller]

  # VM Configuration
  node_name       = "pve"
  template_id     = 100
  datastore_id    = "zfs-pool1"
  client_count    = var.client_count
  network_bridge  = "vmbr0"

  # DC IP (dynamically discovered)
  dc_ip = module.domain_controller.dc_ip

  # Credentials
  admin_username = var.admin_username
  admin_password = var.admin_password

  # Domain Configuration
  domain_name = var.domain_name

  # Scripts path
  scripts_path = "${path.root}/scripts"

  # Ensure DC is verified before creating clients
  dc_verified = module.domain_controller.dc_verified
}