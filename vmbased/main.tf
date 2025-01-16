// fix bastion host security group
// add scaling sets to both subnets
// fix app gateway
// add sql databases
// add route 53
// use a dyanmic website for testing

// ssh into vms from bastion, configure ssh key for vm and nsg for both subnets
// add correct backend pools in the app gateway
// create db after this, ssh into db from bastion and from vm, must work in all zones
// fix up load balancer
// find prebuilt webpage to population the vm and db, test it with fake traffic

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
      { name = "private-db-subnet-zone2" , address_prefixes = "10.0.6.0/24" , zone = "2"}
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

data "azurerm_resource_group" "main" {
  name = "vmbased-vnet"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vmbased"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  address_space       = var.full_cidr
}


#----------------------- all private subnets ------------------------#

// create private subnets for the linux virtual machines
resource "azurerm_subnet" "vm_subnets" {
  count = length(local.vm_subnets)
  name = local.vm_subnets[count.index].name
  resource_group_name = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [local.vm_subnets[count.index].address_prefixes]

  depends_on = [ azurerm_virtual_network.vnet ]
}

// create private subnets for the sql databases
resource "azurerm_subnet" "db_subnets" {
  count = length(local.db_subnets)
  name = local.db_subnets[count.index].name
  resource_group_name = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [local.db_subnets[count.index].address_prefixes]

  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
    }
  }

  depends_on = [ azurerm_virtual_network.vnet ]
}


#----------------------- all public subnets & nat gateway------------------------#

// public subnet for azure bastion
resource "azurerm_subnet" "bastion_subnet" {
  name = local.public_subnets[0].name
  resource_group_name = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [local.public_subnets[0].address_prefixes]

  depends_on = [ azurerm_virtual_network.vnet ]
}

// nat gateway for bastion subnet
resource "azurerm_nat_gateway" "nat_gateway_zone1" {
  name                = "NATgateway-for-bastion-subnet"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  zones = [ "1" ]

  depends_on = [ azurerm_virtual_network.vnet ]
  
}

//associate NAT Gateway to bastion subnet
resource "azurerm_subnet_nat_gateway_association" "bastion_subnet" {
  subnet_id           = azurerm_subnet.bastion_subnet.id
  nat_gateway_id      = azurerm_nat_gateway.nat_gateway_zone1.id

  depends_on = [ azurerm_subnet.bastion_subnet, azurerm_nat_gateway.nat_gateway_zone1 ]        // needs bastion subnet and NAT gateway
}

// public subnet for application gateway
resource "azurerm_subnet" "agw_subnet" {
  name = local.public_subnets[1].name
  resource_group_name = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [local.public_subnets[1].address_prefixes]

  depends_on = [ azurerm_virtual_network.vnet ]
}

// nat gateway for agw subnet
resource "azurerm_nat_gateway" "nat_gateway_zone2" {
  name                = "NATgateway-for-agw-subnet"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  zones = [ "2" ]

  depends_on = [ azurerm_virtual_network.vnet ]
  
}

//associate NAT Gateway to agw subnet
resource "azurerm_subnet_nat_gateway_association" "agw_subnet" {
  subnet_id           = azurerm_subnet.agw_subnet.id
  nat_gateway_id      = azurerm_nat_gateway.nat_gateway_zone2.id

  depends_on = [ azurerm_subnet.agw_subnet, azurerm_nat_gateway.nat_gateway_zone2 ]        // needs agw subnet and nat gateway
}


#----------------------- public IPs ------------------------#

# Elastic IPs for bastion subnet
resource "azurerm_public_ip" "public_ip_nat_bastion" {
  //for_each            = length(local.public_subnets)
  name                = "nat-public-ip-for-bastion-subnet"   // add random number
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                  = "Standard"
  zones = [ "1" ]
  //zones               = each.value == "public-subnet-zone1" ? ["1"] : ["2"]     //assigning the IP to a each zone (zone 1 for public-subnet-zone1, zone 2 for public-subnet-zone2)

  depends_on = [ azurerm_virtual_network.vnet ]
}

// associate nat gateway id with bastion subnet
resource "azurerm_nat_gateway_public_ip_association" "nat_to_ip_association1" {
  nat_gateway_id      = azurerm_nat_gateway.nat_gateway_zone1.id
  public_ip_address_id = azurerm_public_ip.public_ip_nat_bastion.id

  depends_on = [ azurerm_public_ip.public_ip_nat_bastion, azurerm_nat_gateway.nat_gateway_zone1 ]
}

// elastic IP for agw public subnet
resource "azurerm_public_ip" "public_ip_nat_agw" {
  name                = "nat-public-ip-for-agw-subnet"   // add random number
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                  = "Standard"
  zones = [ "2" ]
  //zones               = each.value == "public-subnet-zone1" ? ["1"] : ["2"]     //assigning the IP to a each zone (zone 1 for public-subnet-zone1, zone 2 for public-subnet-zone2)

  depends_on = [ azurerm_virtual_network.vnet ]
}

// associate nat gateway id with agw subnet
resource "azurerm_nat_gateway_public_ip_association" "nat_to_ip_association2" {
  nat_gateway_id      = azurerm_nat_gateway.nat_gateway_zone2.id
  public_ip_address_id = azurerm_public_ip.public_ip_nat_agw.id

  depends_on = [ azurerm_public_ip.public_ip_nat_agw, azurerm_nat_gateway.nat_gateway_zone2 ]
}


#----------------------- zone 1 route table ------------------------#

resource "azurerm_route_table" "route_table_bastion" {
  name                = "route-table-to-bastion-subnet"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  route {
    name                   = "internet-access"                             // Route for internet access via NAT Gateway
    address_prefix         = var.all_cidr
    next_hop_type          = "VirtualAppliance"                                    // virtal applicance routes traffic to an azure service - requires next_hop_in_ip_address - define nat gateways public IP
    next_hop_in_ip_address = azurerm_public_ip.public_ip_nat_bastion.ip_address   //NAT Gateway for internet access
  }

  depends_on = [ azurerm_public_ip.public_ip_nat_bastion, azurerm_nat_gateway.nat_gateway_zone1 ]
}

#------- route table associations --------#
resource "azurerm_subnet_route_table_association" "zone1_rt_association_vm" {
  subnet_id      = azurerm_subnet.vm_subnets[0].id                   //Private VM subnet in zone 1 (index 1)
  route_table_id = azurerm_route_table.route_table_bastion.id
}

resource "azurerm_subnet_route_table_association" "zone1_rt_association_db" {
  subnet_id      = azurerm_subnet.db_subnets[0].id                  //Private DB subnet in zone 1 (index 2)
  route_table_id = azurerm_route_table.route_table_bastion.id
}

#----------------------- zone 2 route table ------------------------#

resource "azurerm_route_table" "route_table_agw" {
  name                = "route-table-to-app-gateway-subnet"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  route {
    name                   = "internet-access"                             // Route to internet via NAT Gateway
    address_prefix         = var.all_cidr
    next_hop_type          = "VirtualAppliance"                                    // virtal applicance routes traffic to an azure service - requires next_hop_in_ip_address - define nat gateways public IP
    next_hop_in_ip_address = azurerm_public_ip.public_ip_nat_agw.ip_address   //NAT Gateway for internet access
  }

  depends_on = [ azurerm_public_ip.public_ip_nat_agw, azurerm_nat_gateway.nat_gateway_zone2 ]
}

#------- route table associations --------#
resource "azurerm_subnet_route_table_association" "zone2_rt_association_vm" {
  subnet_id      = azurerm_subnet.vm_subnets[1].id                         //Private VM subnet in zone 2 (index 1)
  route_table_id = azurerm_route_table.route_table_agw.id
}

resource "azurerm_subnet_route_table_association" "zone2_rt_association_db" {
  subnet_id      = azurerm_subnet.db_subnets[1].id                         //Private DB subnet in zone 2 (index 2)
  route_table_id = azurerm_route_table.route_table_agw.id
}


#----------------------------- security groups ------------------------------#

# # #----nsg for bastion----#
# resource "azurerm_network_security_group" "bastion_nsg" {               // security group allows bastion host to ssh into all resources in vnet
#   name                = "bastion-nsg"
#   location            = data.azurerm_resource_group.main.location
#   resource_group_name = data.azurerm_resource_group.main.name

#   security_rule {
#     name                       = "Allow-SSH"
#     priority                   = 100
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                  = "Tcp"
#     source_port_range         = "*"
#     destination_port_range    = "22"  # SSH port
#     source_address_prefix     = "*"  # Allow from anywhere
#     destination_address_prefix = "*"
#     description               = "Allow SSH from anywhere to Bastion host"
#   }

# }

# // block associates the Bastion NSG with the Bastion subnet
# resource "azurerm_subnet_network_security_group_association" "bastion_nsg_association" {
#   subnet_id                 = azurerm_subnet.bastion_subnet.id
#   network_security_group_id = azurerm_network_security_group.bastion_nsg.id
# }

# #---- nsg for the virtual machines----#
# resource "azurerm_network_security_group" "vm_nsg" {
#   name                = "virtual-machine-nsg"
#   location            = data.azurerm_resource_group.main.location
#   resource_group_name = data.azurerm_resource_group.main.name   
#   // add rules after creation of vms/ allow inbound traffic from load balancer, database and bastion only. allow outbound traffic to nat gateway only

#   security_rule {
#     name                       = "Allow-ssh-from-bastion"
#     priority                   = 100
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                  = "Tcp"
#     source_port_range         = "*"
#     destination_port_range    = "3306"  # MySQL port 
#     source_address_prefix     = azurerm_public_ip.public_ip_bastion.ip_address  # Replace with Bastion's IP or subnet CIDR
#     destination_address_prefix = "*"
#     description               = "Allow ssh access from Bastion host"
#   }

#   security_rule {
#     name                       = "Allow-outbound-to-nat-gateway"
#     priority                   = 110
#     direction                  = "Outbound"
#     access                     = "Allow"
#     protocol                  = "Tcp"
#     source_port_range         = "*"
#     destination_port_range    = ""   
#     source_address_prefix     = ""  
#     destination_address_prefix = azurerm_public_ip.public_ip_nat_bastion.ip_address
#     description               = "Allow ssh access from Bastion host"
#   }
# }

# #2 blocks to associate nsg with subnets the vms are located in
# resource "azurerm_subnet_network_security_group_association" "zone1_vm_nsg" {
#   subnet_id                 = azurerm_subnet.vm_subnets[0].id
#   network_security_group_id = azurerm_network_security_group.vm_nsg.id
# }

# resource "azurerm_subnet_network_security_group_association" "zone2_vm_nsg" {
#   subnet_id                 = azurerm_subnet.vm_subnets[1].id
#   network_security_group_id = azurerm_network_security_group.vm_nsg.id
# }

# #---- nsg for the databases----#
# resource "azurerm_network_security_group" "db_nsg" {
#   name                = "database-nsg"
#   location            = data.azurerm_resource_group.main.location
#   resource_group_name = data.azurerm_resource_group.main.name
#     // add rules after creation of database. allow inbound traffic from the virtual machines and bastion only. allow outbound traffic to nat gateway only - maybe allow outbound to vm and bastion

# }

# #2 blocks to associate nsg with subnets the db are located in
# resource "azurerm_subnet_network_security_group_association" "zone1_db_nsg" {
#   subnet_id                 = azurerm_subnet.db_subnets[0].id
#   network_security_group_id = azurerm_network_security_group.db_nsg.id
# }

# resource "azurerm_subnet_network_security_group_association" "zone2_db_nsg" {
#   subnet_id                 = azurerm_subnet.db_subnets[1].id
#   network_security_group_id = azurerm_network_security_group.db_nsg.id
# }

#---------------------------- bastion & IP -----------------------------#

resource "azurerm_bastion_host" "bastion" {
  //for_each = toset(local.public_subnets)                                // 1 bastion per vnet
  name                     = "bastion"
  location                 = data.azurerm_resource_group.main.location
  resource_group_name      = data.azurerm_resource_group.main.name
  //virtual_network_id = azurerm_virtual_network.vnet.id                   // only supported when sku is developer, cannot use ip_configuration[] block
  sku = "Standard"                                                      // standard sku for production, needs ip_configuration[] block, cannot use vnet_id

  ip_configuration {
    name = "ip_config"
    public_ip_address_id = azurerm_public_ip.public_ip_bastion.id
    subnet_id = azurerm_subnet.bastion_subnet.id
  }
}

resource "azurerm_public_ip" "public_ip_bastion" {
  //for_each            = toset(local.public_subnets)                         //Iterate over the public subnets
  name                = "bastion_-ip"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  //sku                 = "Standard"
}


#---------------------------- application gateway -----------------------------#

# Public IP for the Load Balancer
resource "azurerm_public_ip" "app_gateway_IP" {
  name                = "application-gateway-public-IP"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
}

resource "azurerm_application_gateway" "app_gateway" {
  name = "application-gateway"
  location = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  gateway_ip_configuration {
    name = "gateway_ip"                            // create new private subnet for this
    subnet_id = azurerm_subnet.agw_subnet.id
  }
  
  frontend_ip_configuration {
    name = local.frontend_ip_configuration_name
    //public_ip_address_id = azurerm_public_ip.app_gateway_IP
    subnet_id = azurerm_subnet.agw_subnet.id
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

  request_routing_rule {
    name = local.request_routing_rule_name
    http_listener_name = local.listener_name
    rule_type = "Basic"
  }

  backend_address_pool {
    name = local.backend_address_pool_name
    ip_addresses = [ 
      
    azurerm_public_ip.public_ip_nat_bastion.ip_address, 
    azurerm_public_ip.app_gateway_IP.ip_address, azurerm_public_ip.public_ip_bastion.ip_address ]
  }

  backend_http_settings {
    name = "backend-http-setting"
    protocol = "Http"
    port = 80
    cookie_based_affinity = "Disabled"
    
  }

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
    capacity = 2
  }
}

#---------------------------- linux scale sets -----------------------------#

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
}

# Store the public SSH key in Key Vault (Optional)
resource "azurerm_key_vault_secret" "public_key" {
  name         = "ssh-public-key"
  value        = tls_private_key.tls_private_key.public_key_openssh
  key_vault_id = azurerm_key_vault.key_vault.id
}

data "azurerm_client_config" "current" {}


resource "azurerm_key_vault_access_policy" "kv_access_policy" {
  key_vault_id = azurerm_key_vault.key_vault.id
  tenant_id    = "16983dae-9f48-4a35-b9f5-0519bf3cdf09"
  object_id    = "7b599db4-a713-4a7e-9c06-8b62bf11eed2"

  key_permissions = [
    "Get", "List", "Create", "Update", "Import"
  ]

  secret_permissions = [
    "Get", "List", "Set"
  ]
}

//created two scale sets per subnet for more granular control
resource "azurerm_linux_virtual_machine_scale_set" "linux_vm" {
  //for_each = azurerm_subnet.vm_subnets
  name = "linux-vm"
  location = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  admin_username = "Admin0"
  sku = "Standard_D2s_v3"
  instances = 1
  upgrade_mode = "Automatic"
  zones = [ "1" ]
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
    name = "net-interface"
    primary = true

    ip_configuration {
      name = "ip-config"
      subnet_id = azurerm_subnet.vm_subnets[0].id
    }
  }
}

#---#

resource "azurerm_linux_virtual_machine_scale_set" "linux_vm2" {
  //for_each = azurerm_subnet.vm_subnets
  name = "linux-vm2"
  location = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  admin_username = "Admin0"
  sku = "Standard_D2s_v3"
  instances = 1
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
    name = "net-interface"
    primary = true

    ip_configuration {
      name = "ip-config"
      subnet_id = azurerm_subnet.vm_subnets[1].id
    }
  }
}

resource "azurerm_network_interface" "name" {
  
}

resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "name" {
  
}
// play with these reousources and find out which one to use





#---------------------------- database server -----------------------------#


# resource "azurerm_mysql_flexible_server" "sql_server" {
#   name                   = "mysql-flexible-server"
#   resource_group_name    = data.azurerm_resource_group.main.name
#   location               = data.azurerm_resource_group.main.location
#   administrator_login    = "admin0"
#   administrator_password = "Bratunac?13"
#   sku_name               = "B_Standard_B1s"
#   delegated_subnet_id = azurerm_subnet.db_subnets[0].id

# }

# resource "azurerm_mysql_flexible_database" "mysql_database" {
#   name                = "mysql-flexible-database"
#   resource_group_name = data.azurerm_resource_group.main.name
#   server_name         = azurerm_mysql_flexible_server.sql_server.name
#   charset             = "utf8"
#   collation           = "utf8_unicode_ci"
# }
