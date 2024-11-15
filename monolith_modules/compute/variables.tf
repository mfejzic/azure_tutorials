variable "nic_name" {
  type = string
  description = "defines network interface name"
}

variable "resource_group_name" {
  type = string
  description = "defines resource group name"
}

variable "vnet_location" {
  type = string
  description = "defines location of virtual network"
}

variable "db_subnet_id" {
  type = string
  description = "defines subnet id"
}

variable "private_ip_address_allocation" {
  type=string
  description="This defines the private ip address allocation"
  default = "Dynamic"
}

variable "publicip_name" {
  type = string
  description = "defines public ip name"
  default = "defualt-ip"
}

variable "publicip_required" {
  type = bool
  description = "defines whether public ip is required or not"
}

variable "vmdb_name" {
  type = string
  description = "defines name of the database vm"
}

variable "admin_username" {
  type = string
  description = "defines admin username for db vm"
}

variable "admin_password" {
  type = string
  description = "defines admin passwrod for db vm"
}

variable "source_image_reference" {
  type = map
  description = "defines the source image reference for the virtual machine"
}
