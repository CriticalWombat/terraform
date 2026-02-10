output "vm_id" {
  description = "VM ID of the domain controller"
  value       = proxmox_virtual_environment_vm.dc.vm_id
}

output "vm_name" {
  description = "Name of the domain controller"
  value       = proxmox_virtual_environment_vm.dc.name
}

output "temp_ip" {
  description = "Temporary IP address"
  value       = var.temp_ip
}

output "final_ip" {
  description = "Final static IP address"
  value       = var.final_ip
}

output "dc_verified" {
  description = "DC verification resource ID (for dependencies)"
  value       = null_resource.verify_dc.id
}