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

  # SSH needed for script file uploads to proxmox
  ssh {
    agent    = false
    username = var.proxmox_ssh_username
    password = var.proxmox_ssh_password
  }
}

# Machine specs
locals {
  vms = {
    Workstation01 = {
      cores       = 4
      memory      = 4096
      disk        = 32
      ip_address  = var.vm1_ip_address
      netmask     = 24
      net_bridge  = "vmbr1"
    }
    ShopFloorPC = {
      cores       = 4
      memory      = 4096
      disk        = 32
      ip_address  = var.vm2_ip_address
      netmask     = 24
      net_bridge  = "vmbr1"
    }
  }

  vmbr1_gateway = var.vmbr1_gateway
  dns_primary   = "1.1.1.1"
  dns_secondary = "1.0.0.1"
}

# Create a separate cloud-init script for each VM
resource "proxmox_virtual_environment_file" "cloud_init_script" {
  for_each = local.vms

  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data = <<-EOF
    #ps1_sysnative

    Start-Transcript -Path C:\cloud-init-${each.key}.log

    Write-Host "=== Configuring ${each.key} ==="

    try {
        # Set hostname
        Write-Host "Setting hostname to ${each.key}..."
        Rename-Computer -NewName "
}" -Force

        # Get network adapter
        $adapter = Get-NetAdapter | Where-Object {
            $_.Status -eq 'Up' -and
            $_.InterfaceDescription -notlike '*Loopback*'
        } | Select-Object -First 1

        if ($adapter) {
            Write-Host "Configuring network on: $($adapter.Name)"

            # Remove existing IP
            Remove-NetIPAddress -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetRoute -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2

            # Set static IP
            New-NetIPAddress `
                -InterfaceAlias $adapter.Name `
                -IPAddress "${each.value.ip_address}" `
                -PrefixLength ${each.value.netmask} `
                -DefaultGateway "${local.vmbr1_gateway}"

            # Set DNS
            Set-DnsClientServerAddress `
                -InterfaceAlias $adapter.Name `
                -ServerAddresses ("${local.dns_primary}", "${local.dns_secondary}")

            Clear-DnsClientCache
            Write-Host "Network configured successfully"
        }

    } catch {
        Write-Error "Configuration failed: $_"
    }

    Stop-Transcript
    EOF

    file_name = "cloud-init-${each.key}.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "Win-10-VM" {
  for_each = local.vms

  name      = each.key
  node_name = "pve"

  clone {
    vm_id = 9000
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
    datastore_id = "zfs-pool1"
    interface    = "scsi0"
    size         = each.value.disk
  }

  agent {
    enabled = true
  }

  initialization {
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_script[each.key].id
  }
}