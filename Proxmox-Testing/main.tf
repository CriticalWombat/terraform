terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.70.0"  # Check https://registry.terraform.io/providers/bpg/proxmox for latest
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  username = var.proxmox_username
  api_token = var.proxmox_api_token
  insecure = var.proxmox_insecure
}

resource "proxmox_virtual_environment_vm" "Win-10-vm" {
  node_name = "pve"
  vm_id     = 200
  name      = "win10-terraform"

  clone {
    vm_id = 100
    full  = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 64
  }

  network_device {
    bridge = "vmbr0"
  }
}

