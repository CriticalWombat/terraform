terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.95"
    }
  }
  required_version = ">= 1.3"
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true

  ssh {
    agent    = false
    username = "root"
    password = var.proxmox_ssh_password
  }
}

module "domain_controller" {
  source = "./modules/domain-controller"

  node_name      = var.proxmox_node
  datastore_id   = var.datastore
  template_id    = var.dc_template_id
  vm_id          = var.vm_id_base
  network_bridge = var.network_bridge

  admin_password     = var.admin_password
  domain_name        = var.domain_name
  domain_netbios     = var.domain_netbios
  safe_mode_password = var.safe_mode_password
}

module "windows_clients" {
  source = "./modules/windows-clients"

  depends_on = [module.domain_controller]

  node_name      = var.proxmox_node
  datastore_id   = var.datastore
  template_id    = var.win10_template_id
  vm_id_base     = var.vm_id_base + 1
  client_count   = var.client_count
  network_bridge = var.network_bridge

  dc_ip          = module.domain_controller.dc_ip
  admin_password = var.admin_password
  domain_name    = var.domain_name
}

# ============================================
# LAB PROFILE — swap via var.lab_profile
# ============================================

module "profile_badblood" {
  count  = var.lab_profile == "badblood" ? 1 : 0
  source = "./modules/lab-profiles/bad-blood"

  depends_on = [module.domain_controller]

  dc_ip          = module.domain_controller.dc_ip
  admin_password = var.admin_password
}

module "profile_vulnad" {
  count  = var.lab_profile == "vulnad" ? 1 : 0
  source = "./modules/lab-profiles/vuln-ad"

  depends_on = [module.domain_controller]

  dc_ip          = module.domain_controller.dc_ip
  admin_password = var.admin_password
}
