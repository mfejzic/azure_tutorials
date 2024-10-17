variable "East_US" {
  type    = string
  default = "eastus"
}
variable "East_US_2" {
  type    = string
  default = "eastus2"
}
variable "West_US" {
  type    = string
  default = "westus"
}
variable "Central_US" {
  type    = string
  default = "centralus"
}
variable "northeurope" {
  type    = string
  default = "northeurope"
}



variable "num_of_sub_it1" {
  type        = number
  description = "defines number of subnets"
  default     = 3 // makes three subnets
}

variable "num_of_sub_it2" {
  type        = number
  description = "defines number of subnets"
  default     = 4 // makes three subnets
  validation {
    condition     = var.num_of_sub_it2 < 5
    error_message = "number of subnets must be less than 5"
  }
}

variable "num_of_vms" {
  type        = number
  description = "number of virtual machines"
  default     = 3
}

# new network infra variables
variable "number_of_machines" {
  type        = number
  description = "This defines the number of virtual machines in the virtual network"
  default     = 2
}