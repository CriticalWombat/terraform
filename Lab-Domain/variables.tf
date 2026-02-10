# ============================================
# PROXMOX CONNECTION
# ============================================

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox username"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Allow insecure SSL connections"
  type        = bool
  default     = true
}

variable "proxmox_ssh_username" {
  description = "Proxmox SSH username"
  type        = string
}

variable "proxmox_ssh_password" {
  description = "Proxmox SSH password"
  type        = string
  sensitive   = true
}

# ============================================
# VM CREDENTIALS
# ============================================

variable "admin_username" {
  description = "Admin username for all VMs"
  type        = string
  default     = "Administrator"
}

variable "admin_password" {
  description = "Admin password for all VMs"
  type        = string
  sensitive   = true
}

# ============================================
# DOMAIN CONFIGURATION
# ============================================

variable "domain_name" {
  description = "Active Directory domain name (FQDN)"
  type        = string
  default     = "contoso.local"
}

variable "domain_netbios_name" {
  description = "Active Directory NetBIOS name"
  type        = string
  default     = "CONTOSO"
}

variable "safe_mode_password" {
  description = "Safe mode administrator password for DC"
  type        = string
  sensitive   = true
}

variable "dc_ip" {
  description = "Final static IP for Domain Controller"
  type        = string
  default     = "10.27.51.10"
}

# ============================================
# CLIENT CONFIGURATION
# ============================================

variable "client_count" {
  description = "Number of Windows 10 clients to create"
  type        = number
  default     = 2
}