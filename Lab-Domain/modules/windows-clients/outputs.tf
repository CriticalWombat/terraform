output "client_vms" {
  description = "Client VM details"
  value = {
    for k, v in proxmox_virtual_environment_vm.clients :
    k => {
      vm_id = v.vm_id
      name  = v.name
    }
  }
}

output "client_ips" {
  description = "Client IP addresses"
  value = {
    for k, v in local.client_vms :
    k => v.final_ip
  }
}

output "temp_ips" {
  description = "Client temporary IP addresses"
  value = {
    for k, v in local.client_vms :
    k => v.temp_ip
  }
}