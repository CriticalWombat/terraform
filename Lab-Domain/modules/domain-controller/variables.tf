# VM Configuration
variable "vm_name" {
  description = "Name of the DC VM"
  type        = string
}

variable "vm_id" {
  description = "VM ID for the DC"
  type        = number
}

variable "node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "template_id" {
  description = "Template ID to clone from"
  type        = number
}

variable "datastore_id" {
  description = "Datastore ID"
  type        = string
}

# Network Configuration
variable "temp_ip" {
  description = "Temporary IP address from template"
  type        = string
}

variable "final_ip" {
  description = "Final static IP address"
  type        = string
}

variable "gateway" {
  description = "Network gateway"
  type        = string
}

# Credentials
variable "admin_username" {
  description = "Administrator username"
  type        = string
}

variable "admin_password" {
  description = "Administrator password"
  type        = string
  sensitive   = true
}

# Domain Configuration
variable "domain_name" {
  description = "Domain name (FQDN)"
  type        = string
}

variable "domain_netbios_name" {
  description = "Domain NetBIOS name"
  type        = string
}

variable "safe_mode_password" {
  description = "Safe mode password"
  type        = string
  sensitive   = true
}

# Scripts
variable "scripts_path" {
  description = "Path to PowerShell scripts"
  type        = string
}