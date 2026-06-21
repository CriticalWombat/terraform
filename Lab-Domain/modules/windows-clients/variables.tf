variable "node_name" {
  type = string
}

variable "template_id" {
  type = number
}

variable "datastore_id" {
  type = string
}

variable "vm_id_base" {
  type = number
}

variable "client_count" {
  type = number
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "dc_ip" {
  type = string
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "domain_name" {
  type = string
}
