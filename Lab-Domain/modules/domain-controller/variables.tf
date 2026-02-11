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

variable "admin_username" {
  description = "Administrator username"
  type        = string
}

variable "admin_password" {
  description = "Administrator password"
  type        = string
  sensitive   = true
}

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

variable "scripts_path" {
  description = "Path to PowerShell scripts"
  type        = string
}