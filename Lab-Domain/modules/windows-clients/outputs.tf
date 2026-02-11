output "client_details" {
  description = "All client VM details with dynamic IPs"
  value = {
    for name, config in local.client_vms :
    name => {
      vm_id     = config.vm_id
      static_ip = local.client_ips[name]
      cores     = config.cores
      memory    = config.memory
    }
  }
}

output "client_ips" {
  description = "Map of client names to DHCP IP addresses"
  value       = local.client_ips
}

output "client_vm_ids" {
  description = "Map of client names to VM IDs"
  value = {
    for name, vm in proxmox_virtual_environment_vm.clients :
    name => vm.vm_id
  }
}

output "all_client_ips" {
  description = "All IPs reported by guest agent (for debugging)"
  value = {
    for name, vm in proxmox_virtual_environment_vm.clients :
    name => vm.ipv4_addresses
  }
}