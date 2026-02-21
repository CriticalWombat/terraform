# ============================================
# PROXMOX CONNECTION
# ============================================

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox username (e.g., root@pam)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token"
  type        = string

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

}

# ============================================
# VM CREDENTIALS
# ============================================

variable "admin_username" {
  description = "Administrator username for all VMs"
  type        = string
  default     = "Administrator"
}

variable "admin_password" {
  description = "Administrator password for all VMs"
  type        = string

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

}

# ============================================
# CLIENT CONFIGURATION
# ============================================

variable "client_count" {
  description = "Number of Windows 10 clients to create"
  type        = number
  default     = 1
}