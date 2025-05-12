// add route 53
// use a dyanmic website for testing



// create diagnostic logs to montior the traffic


## try using redis cache for database

## create startup sript to install flask, and upload script and html to each vm
## !! use manual snapshot of a configured vm, this will be your image !! ##
  // create a vm on portal with everything installed, capture it, then refernce it in your vmss blocks


locals {
  zones = ["1", "2"]

  //zone 1: Public, Private (VM), Private (DB) - list of maps
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
  # public_subnets = flatten(concat([                                                            # logic creates list for public subnets, takes public subnets from the top lists
  #   for subnet in local.subnets_zone1 : subnet.name if substr(subnet.name, 0, 5) == "Azure"    #refers to subnets_zone1[0] AzureBastionSubnet
  #   ] , [ 
  #   for subnet in local.subnets_zone2 : subnet.name if substr(subnet.name, 0, 6) == "public"   #refers to subnets_zone2[0] public subnet for load balancer
  #   ]))

  //Combines both zones' private vm subnets to create one list for private vma - used in scaling set block, check line ...
  private_vm_subnets = flatten(concat([                                                            # logic creates list for private vm subnets
    for subnet in local.subnets_zone1 : subnet.name if substr(subnet.name, 0, 10) == "private-vm"    #refers to subnets_zone1[1] 
    ] , [ 
    for subnet in local.subnets_zone2 : subnet.name if substr(subnet.name, 0, 10) == "private-vm"   #refers to subnets_zone2[1] 
    ]))
    
  // database locals
  private_db_subnets = flatten(concat([                                                            # logic creates list for private vm subnets
    for subnet in local.subnets_zone1 : subnet.name if substr(subnet.name, 0, 10) == "private-db"    #refers to subnets_zone1[1] 
    ] , [ 
    for subnet in local.subnets_zone2 : subnet.name if substr(subnet.name, 0, 10) == "private-db"   #refers to subnets_zone2[1] 
    ]))

    // part of rework
 

    public_subnets = [
      { name = "AzureBastionSubnet" , address_prefixes = "10.0.1.0/24" , zone = "1"},
      { name = "gateway" , address_prefixes = "10.0.2.0/24" , zone = "2"}
    ]

    vm_subnets = [
      { name = "private-vm-subnet-zone1" , address_prefixes = "10.0.3.0/24" , zone = "1"},
      { name = "private-vm-subnet-zone2" , address_prefixes = "10.0.4.0/24" , zone = "2"}
    ]

    db_subnets = [
      { name = "private-db-subnet-zone1" , address_prefixes = "10.0.5.0/24" , zone = "1"},
      { name = "private-db-subnet-zone2" , address_prefixes = "10.0.6.0/24" , zone = "2"}      // unused, potential later use
    ]




  //resources for load balancer configuration
  backend_address_pool_name      = "${azurerm_virtual_network.vnet.name}-backend-address-pool"
  frontend_port_name             = "${azurerm_virtual_network.vnet.name}-frontend-port"
  frontend_ip_configuration_name = "${azurerm_virtual_network.vnet.name}-frontend-ip"
  http_setting_name              = "${azurerm_virtual_network.vnet.name}-http-setting"
  listener_name                  = "${azurerm_virtual_network.vnet.name}-listener-name"
  request_routing_rule_name      = "${azurerm_virtual_network.vnet.name}-routing-rule"
  redirect_configuration_name    = "${azurerm_virtual_network.vnet.name}-redirect-config"
    
}

# resource "azurerm_resource_group" "main" {
#   name = "vmbased"
#   location = var.uswest3
# }

# refers to existing resorce group
data "azurerm_resource_group" "main" {
  name = "vmbased-vnet"
}



# block creates new network
resource "azurerm_virtual_network" "vnet" {
  name                = "vmbased"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  address_space       = var.full_cidr
}


#----------------------------------- all private subnets ------------------------------------#

// create private subnets for the linux virtual machines scale set
resource "azurerm_subnet" "vm_subnets" {
  count = length(local.vm_subnets)                                           // spans all zones
  name = local.vm_subnets[count.index].name
  resource_group_name = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name

  address_prefixes = [
    local.vm_subnets[count.index].address_prefixes                         // refers to address prefix in locals block
  ]
  depends_on = [ 
    azurerm_virtual_network.vnet 
  ]
}

// create private subnets for the sql databases
resource "azurerm_subnet" "db_subnets" {
  count = length(local.db_subnets)
  name = local.db_subnets[count.index].name
  resource_group_name = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name

  address_prefixes = [
    local.db_subnets[count.index].address_prefixes
  ]

   delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }

  depends_on = [ 
    azurerm_virtual_network.vnet 
  ]
}


#------------------------------------ all public subnets -------------------------------------#

// public subnet for azure bastion
resource "azurerm_subnet" "bastion_subnet" {
  name = local.public_subnets[0].name                                                        // [0] refers to bastion subnet
  resource_group_name = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name

  address_prefixes = [
    local.public_subnets[0].address_prefixes
  ]
  depends_on = [ 
    azurerm_virtual_network.vnet 
  ]
}

// public subnet for application gateway
resource "azurerm_subnet" "agw_subnet" {
  name = local.public_subnets[1].name                                                     // [1] refers to gateway subnet
  resource_group_name = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name

  address_prefixes = [
    local.public_subnets[1].address_prefixes
  ]
  depends_on = [ 
    azurerm_virtual_network.vnet 
  ]
}

#-------------------------------- nat gateway & associations ------------------------------------#

# create nat gateway -> associate to subnet -> create public ip -> associate IP to nat gateway

#----- nat gateway for bastion subnet, or zone 1 subnet -----#
resource "azurerm_nat_gateway" "nat_gateway_zone1" {
  name                = "zone1-NAT"                                     // bastion host is located in zone 1
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  zones = [ "1" ]

  depends_on = [ 
    azurerm_virtual_network.vnet 
  ]
}

//associate NAT Gateway to bastion subnet
resource "azurerm_subnet_nat_gateway_association" "bastion_subnet" {
  subnet_id           = azurerm_subnet.bastion_subnet.id
  nat_gateway_id      = azurerm_nat_gateway.nat_gateway_zone1.id

  depends_on = [ 
    azurerm_subnet.bastion_subnet, azurerm_nat_gateway.nat_gateway_zone1               // needs bastion subnet and NAT gateway
  ]
}

//block creates a public IP for this nat gateway
resource "azurerm_public_ip" "nat_zone1" {
  name                = "NAT-zone1"   
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                  = "Standard"
  zones = [ "1" ]
  //zones               = each.value == "public-subnet-zone1" ? ["1"] : ["2"]     //assigning the IP to a each zone (zone 1 for public-subnet-zone1, zone 2 for public-subnet-zone2)

  depends_on = [ 
    azurerm_virtual_network.vnet 
  ]
}

// associate nat gateway with the public IP above
resource "azurerm_nat_gateway_public_ip_association" "nat_to_ip_association1" {
  nat_gateway_id      = azurerm_nat_gateway.nat_gateway_zone1.id
  public_ip_address_id = azurerm_public_ip.nat_zone1.id

  depends_on = [ 
    azurerm_public_ip.nat_zone1, azurerm_nat_gateway.nat_gateway_zone1 
  ]
}


#----- this creates a nat gateway for agw subnet, or zone 2 subnet -----#
resource "azurerm_nat_gateway" "nat_gateway_zone2" {
  name                = "zone2-NAT"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  zones = [ "2" ]

  depends_on = [ 
    azurerm_virtual_network.vnet 
  ]
}

//associates NAT Gateway to app gateway subnet, or public zone 2 subnet
resource "azurerm_subnet_nat_gateway_association" "agw_subnet" {
  subnet_id           = azurerm_subnet.agw_subnet.id
  nat_gateway_id      = azurerm_nat_gateway.nat_gateway_zone2.id

  depends_on = [ 
    azurerm_subnet.agw_subnet, azurerm_nat_gateway.nat_gateway_zone2                     // needs agw subnet and nat gateway
  ]
}
resource "azurerm_subnet_nat_gateway_association" "zone2_vm_subnet" {                      // ?????? private subnet not need NAT, verify and delete this block
  subnet_id           = azurerm_subnet.vm_subnets[1].id
  nat_gateway_id      = azurerm_nat_gateway.nat_gateway_zone2.id

  depends_on = [ azurerm_subnet.agw_subnet, azurerm_nat_gateway.nat_gateway_zone2 ]        // needs agw subnet and nat gateway
}

// this creates a public IP for the zone 2 nat gateway
resource "azurerm_public_ip" "nat_zone2" {
  name                = "NAT-zone2"   // add random number if using count 
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                  = "Standard"
  zones = [ "2" ]
  //zones               = each.value == "public-subnet-zone1" ? ["1"] : ["2"]     //assigning the IP to a each zone (zone 1 for public-subnet-zone1, zone 2 for public-subnet-zone2) - use this if using count attribute

  depends_on = [ 
    azurerm_virtual_network.vnet 
  ]
}

// associate nat gateway with the public IP above
resource "azurerm_nat_gateway_public_ip_association" "nat_to_ip_association2" {
  nat_gateway_id      = azurerm_nat_gateway.nat_gateway_zone2.id
  public_ip_address_id = azurerm_public_ip.nat_zone2.id

  depends_on = [ 
    azurerm_public_ip.nat_zone2, azurerm_nat_gateway.nat_gateway_zone2 
  ]
}


#----------------------------------- zone 1 private route tables ------------------------------------#

resource "azurerm_route_table" "route_tables_zone1" {
  name                = "zone1-to-internet"                          
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  route {
    name                   = "nat-access"                             // Route for internet access via NAT Gateway
    address_prefix         = var.all_cidr
    next_hop_type          = "Internet"                                    // use internet                     virtual applicance routes traffic to an azure service - requires next_hop_in_ip_address - define nat gateways public IP
    //next_hop_in_ip_address = azurerm_public_ip.public_ip_nat_zone1.ip_address   //NAT Gateway for internet access - comment this out if using internet
  }

  depends_on = [ 
    azurerm_public_ip.nat_zone1, azurerm_nat_gateway.nat_gateway_zone1 
  ]
}

#------- route table associations --------#
resource "azurerm_subnet_route_table_association" "zone1_rt_association_vm" {
  subnet_id      = azurerm_subnet.vm_subnets[0].id                   //Private VM subnet in zone 1
  route_table_id = azurerm_route_table.route_tables_zone1.id
}

resource "azurerm_subnet_route_table_association" "zone1_rt_association_db" {
  subnet_id      = azurerm_subnet.db_subnets[0].id                  //Private DB subnet in zone 1 
  route_table_id = azurerm_route_table.route_tables_zone1.id
}

#-------------------------------------- zone 2 private route tables -------------------------------------#

resource "azurerm_route_table" "route_tables_zone2" {
  name                = "zone2-to-internet"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  route {
    name                   = "nat-access"                             // Route to internet via NAT Gateway
    address_prefix         = var.all_cidr
    next_hop_type          = "Internet"                                    // virtual applicance routes traffic to an azure service - requires next_hop_in_ip_address - define nat gateways public IP
    //next_hop_in_ip_address = azurerm_public_ip.public_ip_nat_zone2.ip_address  //NAT Gateway for internet access - comment this out if using internet
  }

  depends_on = [ 
    azurerm_public_ip.nat_zone2, azurerm_nat_gateway.nat_gateway_zone2 
  ]
}

#------- route table associations --------#
resource "azurerm_subnet_route_table_association" "zone2_rt_association_vm" {
  subnet_id      = azurerm_subnet.vm_subnets[1].id                         //Private VM subnet in zone 2
  route_table_id = azurerm_route_table.route_tables_zone2.id
}

resource "azurerm_subnet_route_table_association" "zone2_rt_association_db" {  // change the 1 to a 0, and delete the privatesubnet2 database, actally delete this
  subnet_id      = azurerm_subnet.db_subnets[1].id                         //Private DB subnet in zone 2 
  route_table_id = azurerm_route_table.route_tables_zone2.id
}

#-----------------------  public route tables ------------------------#

resource "azurerm_route_table" "public_rt" {                 // check this works!!!
  name = "route-to-internet"
  resource_group_name = data.azurerm_resource_group.main.name
  location = data.azurerm_resource_group.main.location

  route {
    name = "internet-access"
    address_prefix         = var.all_cidr
    next_hop_type = "Internet"
  }
}

#------- route table associations --------#
# resource "azurerm_subnet_route_table_association" "public_bastion_rt_association" {      // cannot attach route table to bastion subnet
#   subnet_id      = azurerm_subnet.bastion_subnet.id                        
#   route_table_id = azurerm_route_table.public_rt.id
# }

resource "azurerm_subnet_route_table_association" "public_agw_rt_association" {
  subnet_id      = azurerm_subnet.agw_subnet.id                         
  route_table_id = azurerm_route_table.public_rt.id
}

#----------------------------- security groups ------------------------------#

#---- nsg for bastion subnet ----#
resource "azurerm_network_security_group" "bastion_nsg" {
  name                = "nsg-BastionSubnet"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

# -- inbound rules -- #

  security_rule {
    name                       = "allow-ingress-443-from-public-internet"
    direction                  = "Inbound"
    priority                  = 100
    protocol                  = "Tcp"
    source_address_prefix     = "*"
    destination_port_range    = "443"
    access                    = "Allow"
    source_port_range         = "*"
    destination_address_prefix = "*"
    description               = "Allow inbound traffic from the internet to port 443 for Bastion"
  }

  security_rule {
    name                       = "allow-ingress-443-from-gateway-manager"
    direction                  = "Inbound"
    priority                  = 110
    protocol                  = "Tcp"
    source_address_prefix     = "GatewayManager"
    destination_port_range    = "443"
    access                    = "Allow"
    source_port_range         = "*"
    destination_address_prefix = "*"
    description               = "Allow inbound control plane traffic from Gateway Manager"
  }

  security_rule {
    name                       = "allow-ingress-8080-from-virtualnetwork"
    direction                  = "Inbound"
    priority                  = 120
    protocol                  = "Tcp"
    source_address_prefix     = "VirtualNetwork"
    destination_port_range    = "8080"
    access                    = "Allow"
    source_port_range         = "*"
    destination_address_prefix = "*"
    description               = "Allow inbound data plane traffic from VirtualNetwork"
  }

  security_rule {
    name                       = "allow-ingress-5701-from-virtualnetwork"
    direction                  = "Inbound"
    priority                  = 130
    protocol                  = "Tcp"
    source_address_prefix     = "VirtualNetwork"
    destination_port_range    = "5701"
    access                    = "Allow"
    source_port_range         = "*"
    destination_address_prefix = "*"
    description               = "Allow inbound data plane traffic from VirtualNetwork"
  }

  security_rule {
    name                       = "allow-ingress-443-from-azure-loadbalancer"
    direction                  = "Inbound"
    priority                  = 140
    protocol                  = "Tcp"
    source_address_prefix     = "AzureLoadBalancer"
    destination_port_range    = "443"
    access                    = "Allow"
    source_port_range         = "*"
    destination_address_prefix = "*"
    description               = "Allow inbound health probe traffic from Azure Load Balancer"
  }

# -- outbound rules -- #

  security_rule {
    name                       = "allow-egress-to-vm-subnet-3389"
    direction                  = "Outbound"
    priority                  = 100
    protocol                  = "Tcp"
    source_address_prefix     = "*"
    destination_address_prefix = "VirtualNetwork"
    destination_port_range    = "3389"
    access                    = "Allow"
    source_port_range         = "*"
    description               = "Allow egress to VM subnets for RDP"
  }

  security_rule {
    name                       = "allow-egress-to-vm-subnet-22"
    direction                  = "Outbound"
    priority                  = 110
    protocol                  = "Tcp"
    source_address_prefix     = "*"
    destination_address_prefix = "VirtualNetwork"
    destination_port_range    = "22"
    access                    = "Allow"
    source_port_range         = "*"
    description               = "Allow egress to VM subnets for SSH"
  }

  security_rule {
    name                       = "allow-egress-8080-to-virtualnetwork"
    direction                  = "Outbound"
    priority                  = 120
    protocol                  = "Tcp"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    destination_port_range    = "8080"
    access                    = "Allow"
    source_port_range         = "*"
    description               = "Allow outbound data plane traffic to VirtualNetwork"
  }

  security_rule {
    name                       = "allow-egress-5701-to-virtualnetwork"
    direction                  = "Outbound"
    priority                  = 130
    protocol                  = "Tcp"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    destination_port_range    = "5701"
    access                    = "Allow"
    source_port_range         = "*"
    description               = "Allow outbound data plane traffic to VirtualNetwork"
  }

  security_rule {
    name                       = "allow-egress-to-azurecloud-443"
    direction                  = "Outbound"
    priority                  = 140
    protocol                  = "Tcp"
    source_address_prefix     = "*"
    destination_address_prefix = "AzureCloud"
    destination_port_range    = "443"
    access                    = "Allow"
    source_port_range         = "*"
    description               = "Allow outbound traffic to Azure public endpoints"
  }

  security_rule {
    name                       = "allow-egress-to-internet-80"
    direction                  = "Outbound"
    priority                  = 150
    protocol                  = "Tcp"
    source_address_prefix     = "*"
    destination_address_prefix = "*"
    destination_port_range    = "80"
    access                    = "Allow"
    source_port_range         = "*"
    description               = "Allow outbound traffic to Internet on port 80"
  }
}

// block associates the Bastion NSG with the Bastion subnet
resource "azurerm_subnet_network_security_group_association" "bastion" {
  subnet_id                 = azurerm_subnet.bastion_subnet.id
  network_security_group_id = azurerm_network_security_group.bastion_nsg.id
}

#---- nsg for the application gateway subnet ----#
# resource "azurerm_network_security_group" "appgateway_nsg" {
#   name                        = "nsg-AppGateway"
#   location                    = data.azurerm_resource_group.main.location
#   resource_group_name         = data.azurerm_resource_group.main.name

#   # -- inbound rules -- #

#   security_rule {
#     name                       = "Allow-PrivateVM-to-AppGateway"
#     priority                   = 100
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                   = "*"
#     source_port_range          = "*"
#     destination_port_range     = "*"
#     source_address_prefix      = local.vm_subnets[1].address_prefixes  # Replace with the CIDR of the Private VNet
#     destination_address_prefix = "VirtualNetwork"  # Allow communication with any resource in the virtual network
#   }

#   # -- outbound rules -- #

#   security_rule {
#     name                       = "Allow-PrivateVM-to-Internet"
#     priority                   = 120
#     direction                  = "Outbound"
#     access                     = "Allow"
#     protocol                   = "*"
#     source_port_range          = "*"
#     destination_port_range     = "*"
#     source_address_prefix      = local.vm_subnets[1].address_prefixes  # Replace with the CIDR of the Private VNet
#     destination_address_prefix = "0.0.0.0/0"  # Allow internet access
#   }
# }

# resource "azurerm_subnet_network_security_group_association" "appgateway" {
#   subnet_id                 = azurerm_subnet.agw_subnet.id
#   network_security_group_id = azurerm_network_security_group.appgateway_nsg.id
# }

#---- nsg for the private virtual machines subnet ----#
resource "azurerm_network_security_group" "vm_nsg" {
  name                = "nsg-VirtualMachines"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name   

  # -- inbound rules -- #
 // should allow traffic from the agw subnet

  security_rule {
    name                       = "Allow-AppGateway-To-VMs"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = azurerm_subnet.agw_subnet.address_prefixes[0]
    destination_address_prefix = "*"
  }

  # -- outbound rules -- #
  // should outbound to all network resources and internet

   security_rule {
    name                       = "Allow-Internet-Outbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-VM-to-NAT-Gateway"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = azurerm_public_ip.nat_zone2.ip_address  #  NAT Gateway's public IP
  }

  security_rule {
    name                       = "Allow-Azure-Services"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "53"  # For DNS traffic
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "168.63.129.16"  # Azure DNS & Management IP
  }

  security_rule {
    name                       = "Allow-Internet-Access"
    priority                   = 140
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "0.0.0.0/0"  # Allow internet access
  }
}

#2 blocks to associate nsg with subnets the vms are located in
resource "azurerm_subnet_network_security_group_association" "zone1_vm" {
  subnet_id                 = azurerm_subnet.vm_subnets[0].id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "zone2_vm" {
  subnet_id                 = azurerm_subnet.vm_subnets[1].id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}


# #---- nsg for the databases----#
# resource "azurerm_network_security_group" "db_nsg" {
#   name                = "nsg-Databases"
#   location            = data.azurerm_resource_group.main.location
#   resource_group_name = data.azurerm_resource_group.main.name
#     // allow inbound traffic from the virtual machines and bastion only. allow outbound traffic to nat gateway only - maybe allow outbound to vm and bastion
#   # -- inbound rules -- #

#   security_rule {
#   name                       = "Allow-ssh-from-bastion-and-vms"
#   priority                   = 100
#   direction                  = "Inbound"
#   access                     = "Allow"
#   protocol                  = "Tcp"
#   source_port_range         = "*"
#   destination_port_range    = "22"  # SSH port
#   source_address_prefix     = var.full_cidr[0]  # Use the VNet CIDR block (10.0.0.0/16)
#   destination_address_prefix = "*"
#   description               = "Allow SSH access from Bastion and VMs within the VNet"
#   }

#   # -- outbound rules -- #

# }

# #2 blocks to associate nsg with subnets the db are located in
# resource "azurerm_subnet_network_security_group_association" "zone1_db" {
#   subnet_id                 = azurerm_subnet.db_subnets[0].id
#   network_security_group_id = azurerm_network_security_group.db_nsg.id
# }

# resource "azurerm_subnet_network_security_group_association" "zone2_db" {
#   subnet_id                 = azurerm_subnet.db_subnets[1].id
#   network_security_group_id = azurerm_network_security_group.db_nsg.id
# }

#---------------------------- bastion & IP -----------------------------#
// includes all things bastion

# block creates bastion host
resource "azurerm_bastion_host" "bastion" {
  //for_each = toset(local.public_subnets)                                // 1 bastion per vnet
  name                     = "bastion"
  location                 = data.azurerm_resource_group.main.location
  resource_group_name      = data.azurerm_resource_group.main.name
  //virtual_network_id = azurerm_virtual_network.vnet.id                   // only supported when sku is developer, cannot use ip_configuration[] block
  sku = "Standard"                                                      // standard sku for production, needs ip_configuration[] block, cannot use vnet_id

  ip_configuration {
    name = "ip_config"
    public_ip_address_id = azurerm_public_ip.bastion.id
    subnet_id = azurerm_subnet.bastion_subnet.id
  }
}

# creates public ip for bastion
resource "azurerm_public_ip" "bastion" {
  //for_each            = toset(local.public_subnets)                         //Iterate over the public subnets
  name                = "bastion-ip"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  //sku                 = "Standard"
}


#---------------------------- application gateway -----------------------------#

# Public IP for the Load Balancer
resource "azurerm_public_ip" "app_gateway" {
  name                = "application-gateway-public-IP"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku = "Standard"
  zones = [ "1", "2" ]                                               // zonal public IP - must include same zones as agw ???? why 2 zones?
}

resource "azurerm_application_gateway" "app_gateway" {
  name = "application-gateway"
  location = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  zones = [ "1", "2" ]                                             // must include zones in public IP

  gateway_ip_configuration {
    name = "gateway_ip"                            // create new private subnet for this
    subnet_id = azurerm_subnet.agw_subnet.id
  }
  
  frontend_ip_configuration {
    name = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.app_gateway.id
    //subnet_id = azurerm_subnet.agw_subnet.id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  http_listener {
    name = local.listener_name
    protocol = "Http"
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name = local.frontend_port_name
  }

  probe {
    name = "vmss-health-probe"
    protocol = "Http"
    host = "localhost"                    # or a custom hostname if your app listens on it
    path = "/"                            # or another path your app responds to
    interval = 10                         # seconds
    timeout = 8                          # seconds
    unhealthy_threshold = 3
    pick_host_name_from_backend_http_settings = false
    match {
      status_code = ["200-399"]
    } 
  }

  backend_http_settings {
    name = local.http_setting_name
    protocol = "Http"
    port = 80
    cookie_based_affinity = "Disabled"
    probe_name = "vmss-health-probe"
  }

  request_routing_rule {
    name = local.request_routing_rule_name
    http_listener_name = local.listener_name
    rule_type = "Basic"
    backend_address_pool_name = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
    priority = 1
  }

  backend_address_pool {                                            // leave ip addresses empty for now  replace with -> azurerm_network_interface.vmss.private_ip_address,azurerm_network_interface.vmss_2.private_ip_address
    name = local.backend_address_pool_name 
    //ip_addresses = [    ]                                            // refer to the vm scale set network interface cards      // use this the correct way; backend pool with an associated backend address pool backend 
  }

  sku {
    name     = "Standard_v2" 
    tier     = "Standard_v2"
    //capacity = 2                                              // exclusive with autoscale_configuration
  }

  autoscale_configuration {
    min_capacity = 2
    max_capacity = 12
  }

  
}

#----------------------------------- key vault & private key --------------------------------------#

//refers to prebuilt image from community images
# data "azurerm_image" "community_image" {
#   resource_group_name = data.azurerm_resource_group.main.name
#   provider = azurerm
#   name = "10.4.3-x86_64 (eastus/GraphDB-02faf3ce-79ed-4676-ab69-0e422bbd9ee1/10.4.3-x86_64)"
#   //id = "/CommunityGalleries/graphdb-02faf3ce-79ed-4676-ab69-0e422bbd9ee1/Images/10.4.3-x86_64"
# }

provider "tls" {}

# Generate SSH key pair for Azure VM
resource "tls_private_key" "tls_private_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Store the private key on the local machine
resource "local_file" "local_file" {
  content  = tls_private_key.tls_private_key.private_key_pem
  filename = "linuxkey.pem"  # Store this file in the current directory (or change the path)
}

# Azure Key Vault to store SSH key (Optional, for secure storage of the key)
resource "azurerm_key_vault" "key_vault" {
  name                        = "key-vault-mf37"
  location                    = data.azurerm_resource_group.main.location
  resource_group_name         = data.azurerm_resource_group.main.name
  enabled_for_disk_encryption = true
  tenant_id = "16983dae-9f48-4a35-b9f5-0519bf3cdf09"
  sku_name = "standard"

  # network_acls {                                 //check if this is needed
  #   bypass = "AzureServices"
  #   default_action = "Allow"
  #   virtual_network_subnet_ids = [ 
  #   azurerm_subnet.db_subnets[0].id, 
  #   azurerm_subnet.db_subnets[1].id, 
  #   azurerm_subnet.vm_subnets[0].id, 
  #   azurerm_subnet.vm_subnets[1].id ]
  # }
}

# Store the public SSH key in Key Vault
resource "azurerm_key_vault_secret" "public_key" {
  name         = "private-key"
  value        = tls_private_key.tls_private_key.private_key_pem
  key_vault_id = azurerm_key_vault.key_vault.id

  depends_on = [ 
    azurerm_key_vault.key_vault, 
    azurerm_key_vault_access_policy.user1, 
    azurerm_key_vault_access_policy.local_machine, 
    azurerm_key_vault_access_policy.terraform_application
  ]
}

data "azurerm_client_config" "current" {}


# Access Policy for User 1
resource "azurerm_key_vault_access_policy" "user1" {
  key_vault_id = azurerm_key_vault.key_vault.id
  tenant_id    = "16983dae-9f48-4a35-b9f5-0519bf3cdf09"
  object_id    = "900a20af-26d8-47b0-85d0-b1437c8af627"  # User 1 object ID       // if not try

  key_permissions = [
    "Get", "List", "Create", "Update", "Import"
  ]

  secret_permissions = [
    "Get", "List", "Set", "Recover", "Delete", "Restore"
  ]

  certificate_permissions = [
    "Get", "List", "Create"
  ]

  depends_on = [azurerm_key_vault.key_vault]
}

# Access Policy for Local Machine Application
resource "azurerm_key_vault_access_policy" "local_machine" {
  key_vault_id = azurerm_key_vault.key_vault.id
  tenant_id    = "16983dae-9f48-4a35-b9f5-0519bf3cdf09"
  object_id    = "3728e04a-d9d3-4d3c-b503-b287b1aaa666"  # Local Machine object ID

  key_permissions = [
    "Get", "List", "Create", "Update", "Import"
  ]

  secret_permissions = [
    "Get", "List", "Set", "Recover", "Delete", "Restore"
  ]

  certificate_permissions = [
    "Get", "List", "Create"
  ]

  depends_on = [azurerm_key_vault.key_vault]
}

# Access Policy for Terraform Service Principal
resource "azurerm_key_vault_access_policy" "terraform_application" {
  key_vault_id = azurerm_key_vault.key_vault.id
  tenant_id    = "16983dae-9f48-4a35-b9f5-0519bf3cdf09"
  object_id    = "a4815ff2-fc06-4608-b1c6-9b902ac9ffb3"  # Terraform Service Principal object ID

  key_permissions = [
    "Get", "List", "Create", "Update", "Import"
  ]

  secret_permissions = [
    "Get", "List", "Set", "Recover", "Delete", "Restore"
  ]

  certificate_permissions = [
    "Get", "List", "Create"
  ]

  depends_on = [azurerm_key_vault.key_vault]
}


#------------------------------------ scale set image ---------------------------------------#
// create pre-baked image on portal, refer to it using source_image_id in vmss block
# data "azurerm_image" "name" {
  
# }

#------------------------------------ linux scale sets ---------------------------------------#

//created two scale sets per subnet for more granular control

# --- zone 1 scale set --- #

# block creates virtual machines that auto scale
resource "azurerm_linux_virtual_machine_scale_set" "linux_vm" {
  name = "linux-vm"
  location = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  admin_username = "Admin0"
  admin_password = "Bratunac?13"
  sku = "Standard_B2s"
  instances = 2
  upgrade_mode = "Automatic"
  zones = [ "1" ]
  disable_password_authentication = true
  
  admin_ssh_key {
    public_key = tls_private_key.tls_private_key.public_key_openssh
    username = "Admin0"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching = "ReadWrite"
  }
  network_interface {
    name = "vmss1-interface"
    primary = true

    ip_configuration {
      name = "ip-config"
      subnet_id = azurerm_subnet.vm_subnets[0].id
      
      application_gateway_backend_address_pool_ids = [              // assign this to each each vmss ip-config block, app gateway will target the vmss instances
        for pool in azurerm_application_gateway.app_gateway.backend_address_pool : pool.id
        ]    
    } 
  }
}

// delete this net interface block, you already have inlide block in the vmss above
# resource "azurerm_network_interface" "vmss" {
#   name                = "vmss-nic"
#   location            = data.azurerm_resource_group.main.location
#   resource_group_name = data.azurerm_resource_group.main.name

#   ip_configuration {
#     name                          = "vmss-nic"
#     subnet_id                     = azurerm_subnet.vm_subnets[0].id
#     private_ip_address_allocation = "Dynamic"
#   }
# }

# --- zone 2 scale set --- #

# block creates virtual machines that auto scales
resource "azurerm_linux_virtual_machine_scale_set" "linux_vm2" {
  //for_each = azurerm_subnet.vm_subnets
  name = "linux-vm2"
  location = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  admin_username = "Admin0"
  admin_password = "Bratunac?13"
  sku = "Standard_B2s"
  instances = 2
  upgrade_mode = "Automatic"
  zones = [ "2" ]
  disable_password_authentication = true
  // add source image id or source image reference
  //source_image_id = data.azurerm_image.community_image.id
  
  admin_ssh_key {
    public_key = tls_private_key.tls_private_key.public_key_openssh
    username = "Admin0"
    
  }
  
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching = "ReadWrite"
  }

  network_interface {
    name = "vmss2-interface"
    primary = true

    ip_configuration {
      name = "ip-config"
      subnet_id = azurerm_subnet.vm_subnets[1].id
      application_gateway_backend_address_pool_ids = [              // assign this to each each vmss ip-config block, app gateway will target the vmss instances
        for pool in azurerm_application_gateway.app_gateway.backend_address_pool : pool.id
        ]    
    }
  }
}

// delete this net interface block, you already have inlide block in the vmss above
# resource "azurerm_network_interface" "vmss_2" {
#   name                = "vmss2-nic"
#   location            = data.azurerm_resource_group.main.location
#   resource_group_name = data.azurerm_resource_group.main.name

#   ip_configuration {
#     name                          = "vmss-2-nic"
#     subnet_id                     = azurerm_subnet.vm_subnets[1].id
#     private_ip_address_allocation = "Dynamic"
#   }
# }


#---------------------------- database server -----------------------------#

resource "azurerm_mysql_flexible_server" "sql_server" {
  name                   = "database1-mf37"
  resource_group_name    = data.azurerm_resource_group.main.name
  location               = data.azurerm_resource_group.main.location
  administrator_login    = "admin0"
  administrator_password = "Bratunac?13"
  sku_name               = "GP_Standard_D2ds_v4"
  private_dns_zone_id = azurerm_private_dns_zone.zone.id
  delegated_subnet_id = azurerm_subnet.db_subnets[0].id                    // primary server in zone 1
  zone = "1"
  
  high_availability {
    mode = "ZoneRedundant"                                                    // enables standby server in the remaining zone (2)
    standby_availability_zone = "2"
  }

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.zone_link
  ]
}

resource "azurerm_mysql_flexible_database" "mysql_database" {
  name                = "mysql-flexible-database"
  resource_group_name = data.azurerm_resource_group.main.name
  server_name         = azurerm_mysql_flexible_server.sql_server.name
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
}

//set firewall rules to allow access to the MySQL server
resource "azurerm_mysql_flexible_server_firewall_rule" "db_server_firewall" {
  name                 = "allow-access"
  resource_group_name  = data.azurerm_resource_group.main.name
  server_name          = azurerm_mysql_flexible_server.sql_server.name
  start_ip_address     = "0.0.0.0"  
  end_ip_address       = "255.255.255.255"                                       //allow access from any IP (can be more restrictive)
}

#------------------ private dns zone -------------------#


resource "azurerm_private_dns_zone" "zone" {
  name                = "mf37.mysql.database.azure.com"
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "zone_link" {
  name                  = "mf37VnetZone.com"
  private_dns_zone_name = azurerm_private_dns_zone.zone.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  resource_group_name   = data.azurerm_resource_group.main.name
}


# #---------------------------- diagnostics & log analytics workspace -----------------------------#

# resource "azurerm_log_analytics_workspace" "example" {
#   name                = "acctest-01"
#   location            = azurerm_resource_group.example.location
#   resource_group_name = azurerm_resource_group.example.name
#   sku                 = "PerGB2018"
#   retention_in_days   = 30
# }





# #---------------------------- route 53 -----------------------------#
