// fix bastion host security group
// add scaling sets to both subnets
// add app gateway
// add sql and nosql databases
// add route 53
// use a dyanmic website for testing



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
    { name = "public-lb-subnet-zone2", address_prefixes = "10.0.4.0/24" },
    { name = "private-vm-subnet-zone2", address_prefixes = "10.0.5.0/24" },
    { name = "private-db-subnet-zone2", address_prefixes = "10.0.6.0/24" }
  ]

  //Combines both zones' public subnets to create public IPs
  public_subnets = flatten(concat([                                                            # logic creates list for public subnets, takes public subnets from the top lists
    for subnet in local.subnets_zone1 : subnet.name if substr(subnet.name, 0, 5) == "Azure"    #refers to subnets_zone1[0] AzureBastionSubnet
    ] , [ 
    for subnet in local.subnets_zone2 : subnet.name if substr(subnet.name, 0, 6) == "public"   #refers to subnets_zone2[0] public subnet for load balancer
    ]))

  //Combines both zones' private vm subnets to create one list for private vma - used in scaling set block, check line ...
  private_vm_subnets = flatten(concat([                                                            # logic creates list for private vm subnets
    for subnet in local.subnets_zone1 : subnet.name if substr(subnet.name, 0, 10) == "private-vm"    #refers to subnets_zone1[1] 
    ] , [ 
    for subnet in local.subnets_zone2 : subnet.name if substr(subnet.name, 0, 10) == "private-vm"   #refers to subnets_zone2[1] 
    ]))

  //resources for load balancer configuration
  backend_address_pool_name      = "${azurerm_virtual_network.vnet.name}-backend-address-pool"
  frontend_port_name             = "${azurerm_virtual_network.vnet.name}-frontend-port"
  frontend_ip_configuration_name = "${azurerm_virtual_network.vnet.name}-frontend-ip"
  http_setting_name              = "${azurerm_virtual_network.vnet.name}-http-setting"
  listener_name                  = "${azurerm_virtual_network.vnet.name}-listener-name"
  request_routing_rule_name      = "${azurerm_virtual_network.vnet.name}-routing-rule"
  redirect_configuration_name    = "${azurerm_virtual_network.vnet.name}-redirect-config"
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
#----------------------- NAT gateway ------------------------#

//block creates 2 NAT Gateways for each public subnet
resource "azurerm_nat_gateway" "nat_gateway" {
  for_each            = toset(local.public_subnets)
  name                = "${each.value}-NATgateway"
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
  nat_gateway_id      = azurerm_nat_gateway.nat_gateway["public-lb-subnet-zone2"].id

  depends_on = [ azurerm_subnet.subnets_zone2, azurerm_nat_gateway.nat_gateway ]     // needs zone 2 subnets and NAT gateway
}

#----------------------- public IPs ------------------------#

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

resource "azurerm_route_table" "route_table_bastion" {
  name                = "route-table-to-bastion-subnet"
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
  route_table_id = azurerm_route_table.route_table_bastion.id
}

resource "azurerm_subnet_route_table_association" "zone1_private_db_subnet_association" {
  subnet_id      = azurerm_subnet.subnets_zone1[2].id                    //Private DB subnet in zone 1 (index 2)
  route_table_id = azurerm_route_table.route_table_bastion.id
}

#----------------------- route table for zone 2 ------------------------#

resource "azurerm_route_table" "route_table_lb" {
  name                = "route-table-to-load-balancer-subnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  route {
    name                   = "internet-access"                             // Route to internet via NAT Gateway
    address_prefix         = var.all_cidr
    next_hop_type          = "VirtualAppliance"                                    // virtal applicance routes traffic to an azure service - requires next_hop_in_ip_address - define nat gateways public IP
    next_hop_in_ip_address = azurerm_public_ip.public_ip_nat["public-lb-subnet-zone2"].ip_address   //NAT Gateway for internet access
  }

  depends_on = [ azurerm_public_ip.public_ip_nat, azurerm_nat_gateway.nat_gateway ]
}

#------- route table associations --------#
resource "azurerm_subnet_route_table_association" "zone2_private_subnet_association" {
  subnet_id      = azurerm_subnet.subnets_zone2[1].id                         //Private VM subnet in zone 2 (index 1)
  route_table_id = azurerm_route_table.route_table_lb.id
}

resource "azurerm_subnet_route_table_association" "zone2_private_db_subnet_association" {
  subnet_id      = azurerm_subnet.subnets_zone2[2].id                         //Private DB subnet in zone 2 (index 2)
  route_table_id = azurerm_route_table.route_table_lb.id
}

#----------------------------- security groups ------------------------------#

# #----nsg for bastion----#
# resource "azurerm_network_security_group" "bastion_nsg" {               // security group allows bastion host to ssh into all resources in vnet
#   name                = "bastion-nsg"
#   location            = azurerm_resource_group.main.location
#   resource_group_name = azurerm_resource_group.main.name

# }

# // block associates the Bastion NSG with the Bastion subnet
# resource "azurerm_subnet_network_security_group_association" "bastion_nsg_association" {
#   subnet_id                 = azurerm_subnet.subnets_zone1[0].id
#   network_security_group_id = azurerm_network_security_group.bastion_nsg.id
# }

#---- nsg for the virtual machines----#
resource "azurerm_network_security_group" "vm_nsg" {
  name                = "virtual-machine-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name   
  // add rules after creation of vms/ allow inbound traffic from load balancer, database and bastion only. allow outbound traffic to nat gateway only
}

#2 blocks to associate nsg with subnets the vms are located in
resource "azurerm_subnet_network_security_group_association" "zone1_vm_nsg" {
  subnet_id                 = azurerm_subnet.subnets_zone1[1].id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "zone2_vm_nsg" {
  subnet_id                 = azurerm_subnet.subnets_zone2[1].id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

#---- nsg for the databases----#
resource "azurerm_network_security_group" "db_nsg" {
  name                = "database-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
    // add rules after creation of database. allow inbound traffic from the virtual machines and bastion only. allow outbound traffic to nat gateway only - maybe allow outbound to vm and bastion

}

#2 blocks to associate nsg with subnets the db are located in
resource "azurerm_subnet_network_security_group_association" "zone1_db_nsg" {
  subnet_id                 = azurerm_subnet.subnets_zone1[2].id
  network_security_group_id = azurerm_network_security_group.db_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "zone2_db_nsg" {
  subnet_id                 = azurerm_subnet.subnets_zone2[2].id
  network_security_group_id = azurerm_network_security_group.db_nsg.id
}

#---------------------------- bastion & IP -----------------------------#

resource "azurerm_bastion_host" "bastion" {
  //for_each = toset(local.public_subnets)                                // 1 bastion per vnet
  name                     = "bastion"
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  //virtual_network_id = azurerm_virtual_network.vnet.id                   // only supported when sku is developer, cannot use ip_configuration[] block
  sku = "Standard"                                                      // standard sku for production, needs ip_configuration[] block, cannot use vnet_id

  ip_configuration {
    name = "ip_config"
    public_ip_address_id = azurerm_public_ip.public_ip_bastion.id
    subnet_id = azurerm_subnet.subnets_zone1[0].id
  }
}

resource "azurerm_public_ip" "public_ip_bastion" {
  //for_each            = toset(local.public_subnets)                         //Iterate over the public subnets
  name                = "bastion_-ip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  //sku                 = "Standard"
}


#---------------------------- application gateway -----------------------------#

# Public IP for the Load Balancer
# resource "azurerm_public_ip" "app_gateway_IP" {
#   name                = "application-gateway-public-IP"
#   location            = azurerm_resource_group.main.location
#   resource_group_name = azurerm_resource_group.main.name
#   allocation_method   = "Static"
# }

# resource "azurerm_application_gateway" "app_gateway" {
#   name = "application-gateway"
#   location = azurerm_resource_group.main.location
#   resource_group_name = azurerm_resource_group.main.name

#   gateway_ip_configuration {
#     name = "gateway_ip"                            // create new private subnet for this
#     subnet_id = azurerm_subnet.subnets_zone2[1].id
#   }
  
#   frontend_ip_configuration {
#     name = local.frontend_ip_configuration_name
#     //public_ip_address_id = azurerm_public_ip.app_gateway_IP
#     subnet_id = azurerm_subnet.subnets_zone2[0].id
#   }

#   frontend_port {
#     name = local.frontend_port_name
#     port = 80
#   }

#   http_listener {
#     name = local.listener_name
#     protocol = 80
#     frontend_ip_configuration_name = azurerm_application_gateway_frontend_ip_configuration.frontend_ip_configuration.id
#     frontend_port_name = 
#   }

#   request_routing_rule {
#     name = local.request_routing_rule_name
#     http_listener_name = local.listener_name
#     rule_type = "basic"
#   }

#   backend_address_pool {
#     name = local.backend_address_pool_name
#     ip_addresses = [  ]
#   }

#   backend_http_settings {
#     name = "backend-http-setting"
#     protocol = "Http"
#     port = 80
#     cookie_based_affinity =
    
#   }

#   sku {
#     name = "sku"
#     tier = "Standard_v2"
#   }
# }

#---------------------------- linux scale sets -----------------------------#

resource "azurerm_linux_virtual_machine_scale_set" "linux_vm" {
  for_each = toset(local.private_vm_subnets)
  name = "linux-vm-${each.key}"
  location = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  admin_username = "Admin"
  sku = "Standard_F2"
  os_disk {
    storage_account_type = "Standard_LRS"
    caching = "readWrite"
  }
  network_interface {
    name = "change"

    ip_configuration {
      name = "ip-config"
      subnet_id = local.private_vm_subnets[each.key].id
    }
  }
}
