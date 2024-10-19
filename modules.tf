

module "start_westus" {
  source = "./reusables"
  location = "westus"
  resource_group_name = "westus_RG"
  virtual_network_name = "basic_vnet"
  virtual_network_address_space = "10.0.0.0/16"
}

module "startup_eastus" {
  source = "./reusables"
  location = "eastus"
  resource_group_name = "eastus_RG"
  virtual_network_name = "basic_vnet"
  virtual_network_address_space = "10.0.0.0/16"
}

module "startup_westeurope" {
  source = "./reusables"
  location = "westeurope"
  resource_group_name = "westeurope_RG"
  virtual_network_name = "basic_vnet"
  virtual_network_address_space = "10.0.0.0/16"
}