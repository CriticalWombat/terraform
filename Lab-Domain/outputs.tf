output "dc_ip" {
  description = "Domain Controller IP address"
  value       = module.domain_controller.dc_ip
}

output "client_ips" {
  description = "Map of client VM names to IP addresses"
  value       = module.windows_clients.client_ips
}

output "rdp_commands" {
  description = "xfreerdp commands for all lab machines"
  value = merge(
    {
      dc = "xfreerdp /v:${module.domain_controller.dc_ip} /u:Administrator /p:${var.admin_password} +clipboard /dynamic-resolution"
    },
    {
      for name, ip in module.windows_clients.client_ips :
      name => "xfreerdp /v:${ip} /u:${var.domain_name}\\Administrator /p:${var.admin_password} +clipboard /dynamic-resolution"
    }
  )
}

output "lab_summary" {
  description = "Lab deployment summary"
  value = {
    profile = var.lab_profile
    domain  = var.domain_name
    dc_ip   = module.domain_controller.dc_ip
    clients = module.windows_clients.client_ips
  }
}
