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

resource "proxmox_virtual_environment_vm" "windows_vm" {
  count = 0

  name        = "terraform-win10-vm"
  node_name   = "pve"

  clone {
    vm_id = 9000
    full  = false
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 4096
  }

  network_device {
    bridge = "vmbr1"
    model  = "virtio"
  }

  agent {
    enabled = true
  }
}