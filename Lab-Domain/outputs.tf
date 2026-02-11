# ============================================
# DOMAIN CONTROLLER OUTPUTS
# ============================================

output "dc_vm_id" {
  description = "Domain Controller VM ID"
  value       = module.domain_controller.vm_id
}

output "dc_vm_name" {
  description = "Domain Controller VM name"
  value       = module.domain_controller.vm_name
}

output "dc_ip" {
  description = "Domain Controller IP address"
  value       = module.domain_controller.dc_ip
}

# ============================================
# CLIENT OUTPUTS
# ============================================

output "client_details" {
  description = "Client VM details"
  value       = module.windows_clients.client_details
}

output "client_ips" {
  description = "Client IP addresses"
  value       = module.windows_clients.client_ips
}

# ============================================
# RDP CONNECTION COMMANDS
# ============================================

output "rdp_commands" {
  description = "RDP connection commands"
  sensitive   = true
  value = merge(
    {
      dc = "xfreerdp /v:${module.domain_controller.dc_ip} /u:${var.admin_username} /p:${var.admin_password}"
    },
    {
      for name, ip in module.windows_clients.client_ips :
      name => "xfreerdp /v:${ip} /u:${var.domain_name}\\${var.admin_username} /p:${var.admin_password}"
    }
  )
}

# ============================================
# SUMMARY
# ============================================

output "deployment_summary" {
  description = "Deployment summary"
  value = {
    domain = {
      name        = var.domain_name
      netbios     = var.domain_netbios_name
      dc_ip       = module.domain_controller.dc_ip
      dc_hostname = module.domain_controller.vm_name
    }
    clients = {
      count = var.client_count
      ips   = module.windows_clients.client_ips
    }
  }
}