output "client_ips" {
  description = "Map of client VM names to IP addresses"
  value       = local.client_ips
}

output "vm_ids" {
  description = "Map of client VM names to Proxmox VM IDs"
  value = {
    for name, vm in proxmox_virtual_environment_vm.clients :
    name => vm.vm_id
  }
}
