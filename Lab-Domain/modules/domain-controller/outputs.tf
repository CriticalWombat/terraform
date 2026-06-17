output "dc_ip" {
  description = "DC IP address reported by the guest agent"
  value       = local.dc_ip
}

output "vm_id" {
  value = proxmox_virtual_environment_vm.dc.vm_id
}
