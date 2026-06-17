# ============================================
# PROXMOX CONNECTION
# ============================================

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint (e.g. https://192.168.1.10:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token (e.g. root@pam!terraform=<uuid>)"
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_password" {
  description = "Proxmox root SSH password (used by the provider for file operations)"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

# ============================================
# STORAGE & NETWORKING
# ============================================

variable "datastore" {
  description = "Proxmox datastore for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

# ============================================
# TEMPLATES
# ============================================

variable "dc_template_id" {
  description = "VM ID of the Windows Server template to clone for the DC"
  type        = number
}

variable "win10_template_id" {
  description = "VM ID of the Windows 10 template to clone for clients"
  type        = number
}

variable "vm_id_base" {
  description = "Base VM ID. DC gets this ID; clients are assigned sequential IDs above it"
  type        = number
  default     = 8000
}

# ============================================
# CREDENTIALS
# ============================================

variable "admin_password" {
  description = "Local Administrator password set in the VM templates"
  type        = string
  sensitive   = true
}

# ============================================
# ACTIVE DIRECTORY
# ============================================

variable "domain_name" {
  description = "Active Directory domain FQDN"
  type        = string
  default     = "corp.local"
}

variable "domain_netbios" {
  description = "Active Directory NetBIOS name"
  type        = string
  default     = "CORP"
}

variable "safe_mode_password" {
  description = "DSRM (Directory Services Restore Mode) password for the DC"
  type        = string
  sensitive   = true
}

variable "client_count" {
  description = "Number of Windows 10 workstations to join the domain"
  type        = number
  default     = 1
}

# ============================================
# LAB PROFILE
# ============================================

variable "lab_profile" {
  description = "AD vulnerability profile to deploy after DC promotion. Options: badblood, vulnad, none"
  type        = string
  default     = "badblood"

  validation {
    condition     = contains(["badblood", "vulnad", "none"], var.lab_profile)
    error_message = "lab_profile must be one of: badblood, vulnad, none"
  }
}
