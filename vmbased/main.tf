locals {
  zones = ["1", "2"]

  //zone 1: Public, Private (VM), Private (DB)
  subnets_zone1 = [
    { name = "AzureBastionSubnet", address_prefixes = "10.0.1.0/24" },
    { name = "private-vm-subnet-zone1", address_prefixes = "10.0.2.0/24" },
    { name = "private-db-subnet-zone1", address_prefixes = "10.0.3.0/24" }
  ]

  //zone 2: Public, Private (VM), Private (DB)
  subnets_zone2 = [
    { name = "AzureBastionSubnet", address_prefixes = "10.0.4.0/24" },
    { name = "private-vm-subnet-zone2", address_prefixes = "10.0.5.0/24" },
    { name = "private-db-subnet-zone2", address_prefixes = "10.0.6.0/24" }
  ]

  //Combine both zones' public subnets to create public IPs
  public_subnets = flatten(concat([ 
    for subnet in local.subnets_zone1 : subnet.name if substr(subnet.name, 0, 5) == "Azure" 
    ] , [ 
    for subnet in local.subnets_zone2 : subnet.name if substr(subnet.name, 0, 5) == "Azure" 
    ]))
}

resource "azurerm_resource_group" "main" {
  name = "vmbased"
  location = var.uswest
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vmbased"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.full_cidr
}

#----------------------- all zone 1 subnets ------------------------#

resource "azurerm_subnet" "subnets_zone1" {
  count = length(local.subnets_zone1)
  name = local.subnets_zone1[count.index].name
  resource_group_name = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [local.subnets_zone1[count.index].address_prefixes]

  depends_on = [ azurerm_virtual_network.vnet ]
}

//associate NAT Gateway to public subnet 1 
resource "azurerm_subnet_nat_gateway_association" "nat_to_pubsub1" {
  subnet_id           = azurerm_subnet.subnets_zone1[0].id
  nat_gateway_id      = azurerm_nat_gateway.nat_gateway["AzureBastionSubnet"].id

  depends_on = [ azurerm_subnet.subnets_zone1, azurerm_nat_gateway.nat_gateway ]        // needs zone 1 subnets and NAT gateway
}
#----------------------- NAT gateway & public IPs ------------------------#

//block creates 2 NAT Gateways for each public subnet
resource "azurerm_nat_gateway" "nat_gateway" {
  for_each            = toset(local.public_subnets)
  name                = "${each.value}-nat-gateway"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  //zones               = each.value == "public-subnet-zone1" ? ["1"] : ["2"]       //assign NAT Gateway to a each zone

  depends_on = [ azurerm_virtual_network.vnet ]
  
}
#----------------------- all zone 2 subnets ------------------------#

resource "azurerm_subnet" "subnets_zone2" {
  count = length(local.subnets_zone2)
  name = local.subnets_zone2[count.index].name
  resource_group_name = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes =[local.subnets_zone2[count.index].address_prefixes]

  depends_on = [ azurerm_virtual_network.vnet ]
}

#associate NAT Gateway to public subnet 2
resource "azurerm_subnet_nat_gateway_association" "nat_to_pubsub2" {
  subnet_id           = azurerm_subnet.subnets_zone2[0].id
  nat_gateway_id      = azurerm_nat_gateway.nat_gateway["AzureBastionSubnet"].id

  depends_on = [ azurerm_subnet.subnets_zone2, azurerm_nat_gateway.nat_gateway ]     // needs zone 2 subnets and NAT gateway
}

#----------------------- NAT gateway & public IPs ------------------------#

//block creates 2 NAT Gateways for each public subnet
resource "azurerm_nat_gateway" "nat_gateway" {                                  //delete
  for_each            = toset(local.public_subnets)
  name                = "${each.value}-nat-gateway"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  //zones               = each.value == "public-subnet-zone1" ? ["1"] : ["2"]       //assign NAT Gateway to a each zone

  depends_on = [ azurerm_virtual_network.vnet ]
  
}

# Create 2 Elastic IPs for each public subnet
resource "azurerm_public_ip" "public_ip_nat" {
  for_each            = toset(local.public_subnets)
  name                = "${each.value}-nat-public-ip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                  = "Standard"
  //zones               = each.value == "public-subnet-zone1" ? ["1"] : ["2"]     //assigning the IP to a each zone (zone 1 for public-subnet-zone1, zone 2 for public-subnet-zone2)

  depends_on = [ azurerm_virtual_network.vnet ]
}

# associate NAT Gateways with Public IPs
resource "azurerm_nat_gateway_public_ip_association" "nat_to_ip_association" {
  for_each            = toset(local.public_subnets)                                      //???
  nat_gateway_id      = azurerm_nat_gateway.nat_gateway[each.value].id
  public_ip_address_id = azurerm_public_ip.public_ip_nat[each.value].id

  depends_on = [ azurerm_public_ip.public_ip_nat, azurerm_nat_gateway.nat_gateway ]
}

#----------------------- route table for zone 1 ------------------------#

resource "azurerm_route_table" "private_rt1" {
  name                = "private-route-table1"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  route {
    name                   = "internet-access"                             // Route for internet access via NAT Gateway
    address_prefix         = var.all_cidr
    next_hop_type          = "VirtualAppliance"                                    // virtal applicance routes traffic to an azure service - requires next_hop_in_ip_address - define nat gateways public IP
    next_hop_in_ip_address = azurerm_public_ip.public_ip_nat["AzureBastionSubnet"].ip_address   //NAT Gateway for internet access
  }

  depends_on = [ azurerm_public_ip.public_ip_nat, azurerm_nat_gateway.nat_gateway ]
}

#------- route table associations --------#
resource "azurerm_subnet_route_table_association" "zone1_private_subnet_association" {
  subnet_id      = azurerm_subnet.subnets_zone1[1].id                    //Private VM subnet in zone 1 (index 1)
  route_table_id = azurerm_route_table.private_rt1.id
}

resource "azurerm_subnet_route_table_association" "zone1_private_db_subnet_association" {
  subnet_id      = azurerm_subnet.subnets_zone1[2].id                    //Private DB subnet in zone 1 (index 2)
  route_table_id = azurerm_route_table.private_rt1.id
}

#----------------------- route table for zone 2 ------------------------#

resource "azurerm_route_table" "private_rt2" {
  name                = "private-route-table2"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  route {
    name                   = "internet-access"                             // Route to internet via NAT Gateway
    address_prefix         = var.all_cidr
    next_hop_type          = "VirtualAppliance"                                    // virtal applicance routes traffic to an azure service - requires next_hop_in_ip_address - define nat gateways public IP
    next_hop_in_ip_address = azurerm_public_ip.public_ip_nat["AzureBastionSubnet"].ip_address   //NAT Gateway for internet access
  }

  depends_on = [ azurerm_public_ip.public_ip_nat, azurerm_nat_gateway.nat_gateway ]
}

#------- route table associations --------#
resource "azurerm_subnet_route_table_association" "zone2_private_subnet_association" {
  subnet_id      = azurerm_subnet.subnets_zone2[1].id                         //Private VM subnet in zone 2 (index 1)
  route_table_id = azurerm_route_table.private_rt2.id
}

resource "azurerm_subnet_route_table_association" "zone2_private_db_subnet_association" {
  subnet_id      = azurerm_subnet.subnets_zone2[2].id                         //Private DB subnet in zone 2 (index 2)
  route_table_id = azurerm_route_table.private_rt2.id
}

#----------------------------- security groups ------------------------------#

# resource "azurerm_network_security_group" "bastion_nsg" {
#   name                = "bastion-nsg"
#   location            = azurerm_resource_group.main.location
#   resource_group_name = azurerm_resource_group.main.name

#   security_rule {
#     name                       = "Allow-SSH-from-trusted-IP"
#     priority                   = 100
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                   = "Tcp"
#     source_port_range          = "*"
#     destination_port_range     = "22"
#     source_address_prefix      = "your_trusted_ip_address_or_range"
#     destination_address_prefix = "*"
#   }

#   security_rule {
#     name                       = "Allow-RDP-from-Trusted-IP"
#     priority                   = 110
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                   = "Tcp"
#     source_port_range          = "*"
#     destination_port_range     = "3389"
#     source_address_prefix      = "your_trusted_ip_address_or_range"
#     destination_address_prefix = "*"
#   }
# }

# resource "azurerm_network_security_group" "vm_nsg" {
#   name                = "vm-nsg"
#   location            = azurerm_resource_group.main.location
#   resource_group_name = azurerm_resource_group.main.name

#   security_rule {
#     name                       = "Allow-SSH-from-Bastion"
#     priority                   = 100
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                   = "Tcp"
#     source_port_range          = "*"
#     destination_port_range     = "22"  # Or 3389 for RDP, adjust based on OS
#     source_address_prefix      = azurerm_network_security_group.bastion_nsg.id
#     destination_address_prefix = "*"
#   }

#   security_rule {
#     name                       = "Allow-Internal-VM-Access"
#     priority                   = 110
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                   = "*"
#     source_port_range          = "*"
#     destination_port_range     = "*"
#     source_address_prefix      = "10.0.0.0/8"  # Adjust based on your network
#     destination_address_prefix = "*"
#   }
# }

# resource "azurerm_network_security_group" "db_nsg" {
#   name                = "db-nsg"
#   location            = azurerm_resource_group.main.location
#   resource_group_name = azurerm_resource_group.main.name

#   security_rule {
#     name                       = "Allow-VM-to-DB"
#     priority                   = 100
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                   = "Tcp"
#     source_port_range          = "*"
#     destination_port_range     = "3306"  # MySQL, adjust if using another DB type
#     source_address_prefix      = "10.0.0.0/8"  # Internal subnets, adjust accordingly
#     destination_address_prefix = "*"
#   }

#   security_rule {
#     name                       = "Allow-Admin-Access"
#     priority                   = 110
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                   = "Tcp"
#     source_port_range          = "*"
#     destination_port_range     = "3306"  # MySQL, adjust based on your DB port
#     source_address_prefix      = "trusted_admin_ip_range"
#     destination_address_prefix = "*"
#   }
# }

#---------------------------- bastion & IP -----------------------------#

resource "azurerm_bastion_host" "bastion1" {
  //for_each = toset(local.public_subnets)                                // 1 bastion per vnet
  name                     = "bastion1"
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  //virtual_network_id = azurerm_virtual_network.vnet.id                   // only supported when sku is developer, cannot use ip_configuration[] block
  sku = "Standard"                                                      // standard sku for production, needs ip_configuration[] block, cannot use vnet_id

  ip_configuration {
    name = "ip1"
    public_ip_address_id = azurerm_public_ip.public_ip_bastion1.id
    subnet_id = azurerm_subnet.subnets_zone1[0].id
  }
}

resource "azurerm_public_ip" "public_ip_bastion1" {
  //for_each            = toset(local.public_subnets)                         //Iterate over the public subnets
  name                = "bastion-ip1"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  //sku                 = "Standard"
}

resource "azurerm_bastion_host" "bastion2" {
  //for_each = toset(local.public_subnets)                                // 1 bastion per vnet
  name                     = "bastion2"
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  //virtual_network_id = azurerm_virtual_network.vnet.id                   // only supported when sku is developer 
  sku = "Standard"                                                      // use standard sku for production

  ip_configuration {
    name = "ip2"
    public_ip_address_id = azurerm_public_ip.public_ip_bastion2.id
    subnet_id = azurerm_subnet.subnets_zone2[0].id
  }
}

resource "azurerm_public_ip" "public_ip_bastion2" {
  //for_each            = toset(local.public_subnets)                         //Iterate over the public subnets
  name                = "bastion-ip2"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  //sku                 = "Standard"
}
