# variables.tf

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
  sensitive   = true  # Prevents showing in logs
}

variable "proxmox_insecure" {
  description = "Allow insecure SSL connections"
  type        = bool
  default     = true
}

variable "proxmox_ssh_username" {
  description = "Proxmox username for ssh acess"
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_password" {
  description = "Proxmox password for ssh acess"
  type        = string
  sensitive   = true
}

variable "vmbr1_gateway" {
  description = "The IP address assigned to vmbr1 gateway"
  type        = string
}

variable "vm1_ip_address" {
  description = "The IP address assigned to vm1"
  type        = string
}

variable "vm2_ip_address" {
  description = "The IP address assigned to vm2"
  type        = string
}