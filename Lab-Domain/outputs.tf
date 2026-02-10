output "dc_info" {
  description = "Domain Controller information"
  value       = module.domain_controller
}

output "clients_info" {
  description = "Windows clients information"
  value       = module.windows_clients
}

output "rdp_commands" {
  description = "RDP connection commands"
  value = merge(
    {
      dc = "xfreerdp /v:${module.domain_controller.final_ip} /u:${var.admin_username}"
    },
    {
      for name, ip in module.windows_clients.client_ips :
      name => "xfreerdp /v:${ip} /u:${var.admin_username}"
    }
  )
}