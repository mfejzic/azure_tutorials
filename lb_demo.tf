# config sets up a load balancing infrastructure by creating a resource group, vnet, static public IP for the load balancer, 
# subnet defined with the VM to host network interfaces for mulitple VMs
# the load balancer configured with backend address pool, distributes incoming traffic to the VMs
# health probe pings the VM every five seconds, checking its fucntionality
# includes DNS zone and A record for domain resolution
# security groups control inbound and outbound traffic
# storage account include blobs that store and manage scripts for VM configuration
# setup includes both individual VMs and VM scaling 



# ###########################################################################################################################
#                                      load balancing infrastructure - individual VMs                                      #
# ###########################################################################################################################
#  !  new virtual network architecture for load balaning !

# ------------------------------------- resource group -------------------------------------#
resource "azurerm_resource_group" "RG_lb" {
  name     = "RG_lb"
  location = var.West_US
}

#---- build a virtual network dedicated to load balancing ----#
resource "azurerm_virtual_network" "vnet_lb" {
  name                = "vnet_lb"
  location            = var.West_US 
  resource_group_name = azurerm_resource_group.RG_lb.name
  address_space       = ["10.0.0.0/24"]
} 

#---- public ip for load balancer ----#
resource "azurerm_public_ip" "lb_public_ip" {
  name                = "lb_public_ip"
  resource_group_name = azurerm_resource_group.RG_lb.name
  location            = var.West_US
  allocation_method   = "Static"
  sku = "Standard"                                                     # must be the same sku as load balancer
}

resource "azurerm_subnet" "subnet_lb_1" {    
    name                 = "subnet_lb_1"
    resource_group_name  = azurerm_resource_group.RG_lb.name
    virtual_network_name = azurerm_virtual_network.vnet_lb.name
    address_prefixes     = ["10.0.0.0/24"]
    depends_on = [
      azurerm_virtual_network.vnet_lb
    ]
}

#---- attach public/private IP addresses and vnet to interface ----#
resource "azurerm_network_interface" "lb_interface" {
  count=  var.number_of_machines
  name                = "lb-interface${count.index}"
  location            = var.West_US
  resource_group_name = azurerm_resource_group.RG_lb.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet_lb_1.id
    private_ip_address_allocation = "Dynamic"    

  }

  depends_on = [
    azurerm_virtual_network.vnet_lb
  ]
}

#---- main load balancer ---#
resource "azurerm_lb" "main_lb" {
  name                = "main-loadbalancer"
  location            = var.West_US
  resource_group_name = azurerm_resource_group.RG_lb.name
  sku = "Standard"                                                               # must be same sku as public ip address
  sku_tier = "Regional"                    # regional - use where low latency is critical for users in specific area, when users must compply with local data laws
#                                            global - targeting worldwide audience or when high availability is required                                                                                 
  frontend_ip_configuration {
    name                 = "public-lb-ip"
    public_ip_address_id = azurerm_public_ip.lb_public_ip.id
  }
}
#----------- address backend pool blocks ------------#
resource "azurerm_lb_backend_address_pool" "poolA" {
  loadbalancer_id = azurerm_lb.main_lb.id
  name            = "BackEndAddressPool"

  depends_on = [ azurerm_lb.main_lb ]
}

resource "azurerm_lb_backend_address_pool_address" "vm-lb-address" {
  count = var.number_of_machines
  name                                = "lb-vm${count.index}"
  backend_address_pool_id             = azurerm_lb_backend_address_pool.poolA.id
  virtual_network_id = azurerm_virtual_network.vnet_lb.id
  ip_address = azurerm_network_interface.lb_interface[count.index].private_ip_address

  depends_on = [ azurerm_lb_backend_address_pool.poolA, azurerm_lb.main_lb ]
}

# resource "azurerm_network_interface_backend_address_pool_association" "nic_assoc" {
#   count                   = var.number_of_machines  # Add count here
#   network_interface_id    = azurerm_network_interface.lb_interface[count.index].id
#   ip_configuration_name   = "testconfiguration1${count.index}"
#   backend_address_pool_id = azurerm_lb_backend_address_pool.poolA.id
# }

#---- health checks ----#
resource "azurerm_lb_probe" "lb_probe" {
  loadbalancer_id = azurerm_lb.main_lb.id
  name            = "ssh-running-probe"
  port            = 80
  protocol = "Tcp"

  depends_on = [ azurerm_lb.main_lb ]
}

#---------------- load balancer rules, zones and records -------------------#
resource "azurerm_lb_rule" "rule_1" {
  loadbalancer_id                = azurerm_lb.main_lb.id
  name                           = "rule_A"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "public-lb-ip"
  probe_id = azurerm_lb_probe.lb_probe.id

  backend_address_pool_ids = [azurerm_lb_backend_address_pool.poolA.id]

  depends_on = [ azurerm_lb.main_lb ]
}

resource "azurerm_dns_zone" "zone_1" {
  name                = "fejzic37.com"
  resource_group_name = azurerm_resource_group.RG_lb.name
}

resource "azurerm_dns_a_record" "a_record" {
  name                = "www"
  zone_name           = azurerm_dns_zone.zone_1.name
  resource_group_name = azurerm_resource_group.RG_lb.name
  ttl                 = 60
  records             = [azurerm_public_ip.lb_public_ip.ip_address]
}





#---------- storage account, container and blob ------------#
resource "azurerm_storage_account" "SA_lb" {
  name                     = "mf37loadbalancer"
  resource_group_name      = azurerm_resource_group.RG_lb.name
  location                 = var.West_US
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind = "StorageV2"  
  depends_on = [
    azurerm_resource_group.RG_lb
  ]
}

resource "azurerm_storage_container" "script_data_container" {
  name                  = "script-data"
  storage_account_name  = azurerm_storage_account.SA_lb.name
  container_access_type = "blob"
  depends_on=[
    azurerm_storage_account.SA_lb
    ]
}

resource "azurerm_storage_blob" "blob_script_ISSCONFIG" {
  name                   = "IIS_Config.ps1"
  storage_account_name   = azurerm_storage_account.SA_lb.name
  storage_container_name = azurerm_storage_container.script_data_container.name
  type                   = "Block"
  source                 = "IIS_Config.ps1"
   depends_on=[azurerm_storage_container.script_data_container,
    azurerm_storage_account.SA_lb]
}


#---- security groups ----#
resource "azurerm_network_security_group" "appnsg" {
  name                = "LB-app-nsg"
  location            = var.West_US
  resource_group_name = azurerm_resource_group.RG_lb.name

  security_rule {
    name                       = "AllowRDP"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "AllowHTTPOut"
    priority                   = 500
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }


depends_on = [
    azurerm_virtual_network.vnet_lb
  ]
}

resource "azurerm_subnet_network_security_group_association" "assoc_vnet_lb" {  
  subnet_id                 = azurerm_subnet.subnet_lb_1.id
  network_security_group_id = azurerm_network_security_group.appnsg.id

  depends_on = [
    azurerm_virtual_network.vnet_lb,
  ]
}

############################################################################################################################
#                                                singular virtual machines                                                 #
############################################################################################################################

#--- vm without scale set ---#
resource "azurerm_windows_virtual_machine" "lb_vm" {
  count=  var.number_of_machines
  name                = "LBvm${count.index}"
  resource_group_name = azurerm_resource_group.RG_lb.name
  location            = var.West_US
  size                = "Standard_D2s_v3"
  admin_username      = "adminuser"
  admin_password      = "Azure@123"  
    //availability_set_id = azurerm_availability_set.vmlb_avail_set.id
    network_interface_ids = [
    azurerm_network_interface.lb_interface[count.index].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
  depends_on = [
    azurerm_virtual_network.vnet_lb,
    azurerm_network_interface.lb_interface,
  ]
}
#---- vm extension ----#
resource "azurerm_virtual_machine_extension" "vmextension" {
  count                = var.number_of_machines
  name                 = "lbvm-extension${count.index}"
  virtual_machine_id   = azurerm_windows_virtual_machine.lb_vm[count.index].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  depends_on = [
    azurerm_storage_blob.blob_script_ISSCONFIG
  ]
  settings = <<SETTINGS
    {
        "fileUris": ["https://${azurerm_storage_account.SA_lb.name}.blob.core.windows.net/${azurerm_storage_blob.blob_script_ISSCONFIG.name}/IIS_Config.ps1"],
          "commandToExecute": "powershell -ExecutionPolicy Unrestricted -file IIS_Config.ps1"     
    }
SETTINGS

}

###########################################################################################################################
                                                scaling virtual machines                                                 #
###########################################################################################################################

resource "azurerm_windows_virtual_machine_scale_set" "appset" {  
  name                = "appset"
  resource_group_name = azurerm_resource_group.RG_lb.name
  location            = var.West_US 
  sku                = "Standard_B2"
  instances = var.number_of_machines
  admin_username      = "adminuser"
  admin_password      = "Azure@123"  
  upgrade_mode = "Automatic"
    
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  network_interface {
    name="scaleset-interface"
    primary=true

    ip_configuration {
    name="internal"
    primary=true
    subnet_id=azurerm_subnet.subnet_lb_1.id
    load_balancer_backend_address_pool_ids=[azurerm_lb_backend_address_pool.scalesetpool.id]
  }
  }

  depends_on = [
    azurerm_subnet.subnet_lb_1,    
    azurerm_resource_group.appgrp,
    azurerm_lb_backend_address_pool.scalesetpool
  ]
}

#---- vm scale set extension----#
resource "azurerm_virtual_machine_scale_set_extension" "scalesetextension" {  
  name                 = "scalesetextension"
  virtual_machine_scale_set_id   = azurerm_windows_virtual_machine_scale_set.appset.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"
  depends_on = [
    azurerm_storage_blob.IISConfig
  ]
  settings = <<SETTINGS
    {
        "fileUris": ["https://${azurerm_storage_account.SA_lb.name}.blob.core.windows.net/${azurerm_storage_blob.blob_script_ISSCONFIG.name}/IIS_Config.ps1"],
          "commandToExecute": "powershell -ExecutionPolicy Unrestricted -file IIS_Config.ps1"     
    }
SETTINGS

}
