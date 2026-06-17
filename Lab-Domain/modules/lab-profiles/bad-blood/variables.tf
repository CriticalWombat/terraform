variable "dc_ip" {
  description = "IP address of the domain controller"
  type        = string
}

variable "admin_password" {
  description = "Local Administrator password on the DC"
  type        = string
  sensitive   = true
}
