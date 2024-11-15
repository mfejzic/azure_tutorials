variable "extension_name" {
    type = string
    description = "defines name of extension "
}

variable "virtual_machine_id" {
    type = string
    description = "defines virtual machine ID "
}

variable "extension_type" {
    type = map
    description = "defines defines extension type "
}

variable "SA_name" {
    type = string
    description = "defines storage account name "
}

variable "container_name" {
    type = string
    description = "defines container name in storage account "
}
