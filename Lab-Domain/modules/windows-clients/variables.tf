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

variable "network_bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "client_count" {
  description = "Number of clients to create"
  type        = number
}

variable "dc_ip" {
  description = "Domain controller IP (from DC module)"
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

variable "scripts_path" {
  description = "Path to PowerShell scripts"
  type        = string
}

variable "dc_verified" {
  description = "DC verification resource ID (ensures DC is ready)"
  type        = string
}