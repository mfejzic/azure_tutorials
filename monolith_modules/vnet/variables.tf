
variable "resource_group_name" {
  type = string
  description = "defines resource group name"
}

variable "vnet_location" {
  type = string
  description = "defines location of virtual network"
}

variable "vnet_name" {
  type = string
  description = "defines name of virtual network"
}

variable "vnet_address_space" {
  type = string
  description = "defines address space of virtual network"
}

variable subnet_names {
  type = set(string)
  description = "defines subnets within virtual network"
}

variable "bastion_required" {
  type = bool
  description = "defines whether bastion service is required"
  default = false
}

variable nsg_names {
  type = map(string)
  description = "defines names of entwork security groups"
}

variable "nsg_rules" {
  type = list
  description = "defines nsg rules"
}
