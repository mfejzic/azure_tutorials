variable "uswest" {
  type = string
  default = "westus"
}

variable "full_cidr" {
  type = list(string)
  default = ["10.0.0.0/16"]
}

variable "all_cidr" {
  type = string
  default = "0.0.0.0/0"
}

variable "subnets" {
  type    = number
  default = 6
}
