output "vm_id" {
  description = "VM ID of the domain controller"
  value       = proxmox_virtual_environment_vm.dc.vm_id
}

output "vm_name" {
  description = "Name of the domain controller"
  value       = proxmox_virtual_environment_vm.dc.name
}

output "dc_ip" {
  description = "DC IP address (from DHCP via guest agent)"
  value       = proxmox_virtual_environment_vm.dc.ipv4_addresses[0][0]
}

output "all_ips" {
  description = "All IPs reported by guest agent (for debugging)"
  value       = proxmox_virtual_environment_vm.dc.ipv4_addresses
}

output "dc_verified" {
  description = "DC verification resource ID (for dependencies)"
  value       = null_resource.verify_dc.id
}