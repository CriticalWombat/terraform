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

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "datastore_id" {
  description = "Proxmox datastore ID"
  type        = string
  default     = "zfs-pool1"
}

# ============================================
# TEMPLATE IDs
# ============================================

variable "server2022_template_id" {
  description = "VM template ID for Windows Server 2022"
  type        = number
  default     = 8000
}

variable "win10_template_id" {
  description = "VM template ID for Windows 10"
  type        = number
  default     = 9000
}

# ============================================
# NETWORK CONFIGURATION
# ============================================

variable "vmbr1_gateway" {
  description = "Gateway for vmbr1"
  type        = string
}

variable "dc_ip_address" {
  description = "Static IP address for Domain Controller"
  type        = string
}

variable "client_ip_prefix" {
  description = "IP prefix for client machines (e.g., '192.168.1.')"
  type        = string
}

variable "client_count" {
  description = "Number of Windows 10 clients to create"
  type        = number
  default     = 2
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
# ACTIVE DIRECTORY CONFIGURATION
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