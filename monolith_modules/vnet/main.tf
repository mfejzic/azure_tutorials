
module "general_module" {
  source = ".././general"
  resource_group_name = var.resource_group_name
  resource_group_location = var.vnet_location
}

##############################################################################################################################
#                                                 virtual network and subnets                                                #
##############################################################################################################################

resource "azurerm_virtual_network" "main_vnet" {
  name                = var.vnet_name
  location            = var.vnet_location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_address_space]
  depends_on = [ var.resource_group_name, module.general_module ]

  tags = {
    environment = "Production"
  }
}

resource "azurerm_subnet" "subnets" {
  for_each = var.subnet_names
  name                 = each.key
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.vnet_name
  address_prefixes     = [cidrsubnet(var.vnet_address_space,8,index(tolist(var.subnet_names), each.key))]

  # manually define subnets
  /* address_prefixes     = [each.value] */

  depends_on = [ azurerm_virtual_network.main_vnet, module.general_module ]
}

##############################################################################################################################
#                                                     bastion components                                                     #
##############################################################################################################################

resource "azurerm_subnet" "bastion_subnet" {
  count = var.bastion_required ? 1 : 0                 # if bastion is required, create resource - if not required, skip this block
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.vnet_name
  address_prefixes     = ["10.0.10.0/24"]
  depends_on = [ azurerm_virtual_network.main_vnet ]
}

resource "azurerm_public_ip" "bastion_ip" {
  count = var.bastion_required ? 1 : 0                 # if bastion is required, create resource - if not required, skip this block
  name                = "bastion-ip"
  location            = var.vnet_location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  depends_on = [ module.general_module ]
}

resource "azurerm_bastion_host" "bastion_host" {
  count = var.bastion_required ? 1 : 0                 # if bastion is required, create resource - if not required, skip this block
  name                = "bastion-host"
  location            = var.vnet_location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion_subnet[0].id
    public_ip_address_id = azurerm_public_ip.bastion_ip[0].id
  }
}

##############################################################################################################################
#                                                  network security groups                                                   #
##############################################################################################################################

resource "azurerm_network_security_group" "nsg" {
  for_each = var.nsg_names
  name                = each.key
  location            = var.vnet_location
  resource_group_name = var.resource_group_name

  depends_on = [ azurerm_virtual_network.main_vnet ]

  tags = {
    environment = "Production"
  }
}

resource "azurerm_network_security_rule" "nsg_rules" {
  for_each = {for rule in var.nsg_rules:rule.id => rule}
  name                        = "${each.value.access} - ${each.value.destination_port_range}"
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = each.value.access
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.value.destination_port_range
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.nsg[each.value.network_security_group_name].name

  depends_on = [ azurerm_network_security_group.nsg, module.general_module ]
}


resource "azurerm_subnet_network_security_group_association" "NSG_association" {
  for_each = var.nsg_names
  subnet_id                 = azurerm_subnet.subnets[each.value].id
  network_security_group_id = azurerm_network_security_group.nsg[each.key].id

  depends_on = [ azurerm_virtual_network.main_vnet ]
}
