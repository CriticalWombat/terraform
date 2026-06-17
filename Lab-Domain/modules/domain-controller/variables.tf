variable "node_name" {
  type = string
}

variable "template_id" {
  type = number
}

variable "datastore_id" {
  type = string
}

variable "vm_id" {
  type = number
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "domain_name" {
  type = string
}

variable "domain_netbios" {
  type = string
}

variable "safe_mode_password" {
  type      = string
  sensitive = true
}
