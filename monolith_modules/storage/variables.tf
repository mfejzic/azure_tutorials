variable "SA_name" {
  type = string
  description = "provides the storage account name"
}

variable "resource_group_name" {
  type = string
  description = "defines resource group name"
}

variable "vnet_location" {
  type = string
  description = "defines location of virtual network"
}

variable "container_name" {
  type = string
  description = "defines SA container name"
}

variable "app_container_name" {
  type=string
  description="This defines the container name for the application"
}

variable "container_access" {
  type = string
  description = "defines container access level"
  default = "private"
}

variable "blob_name" {
  type = string
  description = "defines the blob name"
}

variable "blobs" {
  type = map
  description = "defines the blobs to be added"
}
