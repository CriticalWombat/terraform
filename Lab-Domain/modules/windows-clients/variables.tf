# VM Configuration
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

variable "client_count" {
  description = "Number of clients to create"
  type        = number
}

# Network Configuration
variable "client_ip_prefix" {
  description = "IP prefix for clients (e.g., '10.27.51.')"
  type        = string
}

variable "gateway" {
  description = "Network gateway"
  type        = string
}

variable "dc_ip" {
  description = "Domain controller IP (dynamic from DC module)"
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

# Scripts
variable "scripts_path" {
  description = "Path to PowerShell scripts"
  type        = string
}

# Dependencies
variable "dc_verified" {
  description = "DC verification resource ID (ensures DC is ready)"
  type        = string
}