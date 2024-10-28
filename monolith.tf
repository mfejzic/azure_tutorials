## ! BIG STUFF HAPPENING ! ##


locals {
  resource_group_name = "main_resource_group"
  location = "EASTUS"
  virtual_network = {
    address_space = "10.0.0.0/16"
  }
}

module "general_module" {
    source = "./monolith_modules/general"
    resource_group_name = local.resource_group_name
    resource_group_location = local.location
}

module "vnet" {
  source = "./monolith_modules/vnet"
  resource_group_name = local.resource_group_name
  vnet_name = "main_vnet"
  vnet_location = local.location
  vnet_address_space = "10.0.0.0/16"
  subnet_names = ["web-subnet", "db-subnet"]
  bastion_required = true                                 # false by default

  #use type map(string)
  nsg_names = {
    "web-nsg" = "web-subnet"
    "db-nsg" = "db-subnet"
   }

   nsg_rules = [{
    id = 1,
    priority = "200"
    network_security_group_name = "web-nsg"
    destination_port_range = "3389"
    access = "Allow"
   }, {
    id = 2,
    priority = "300"
    network_security_group_name = "web-nsg"
    destination_port_range = "80"
    access = "Allow"
   }, {
    id = 3,
    priority = "400"
    network_security_group_name = "web-nsg"
    destination_port_range = "8173"
    access = "Allow"
   }, {
    id = 4,
    priority = "200"
    network_security_group_name = "db-nsg"
    destination_port_range = "3389"
    access = "Allow"
   }]
}
# manually defines subnet space
  /* subnet_names = {
    "web-subnet" = "10.0.0.0/24"
    "db-subnet" = "10.0.1.0/24"
  } */
