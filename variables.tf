variable "resource_group_name" {
  type=string
  description="This defines the resource group name"
}

variable "location" {
  type=string
  description="This defines the location"
}

variable "virtual_network_name" {
  type=string
  description="This defines the name of the virtual network"
}

variable "virtual_network_address_space" {
  type=string
  description="This defines the address space of the virtual network"
}