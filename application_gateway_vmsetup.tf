locals {
  function = ["videos", "images"]
}

##############################################################################################################################
#                                               resource group & vnet components                                             #
##############################################################################################################################

# create a resource group
resource "azurerm_resource_group" "RG_AGW" {
    location = var.West_US
    name = "resourcegroup-applicationgateway"  
}

#create a virtual private network 
resource "azurerm_virtual_network" "vnet" {
  location = azurerm_resource_group.RG_AGW.location
  name = "vnet"
  resource_group_name = azurerm_resource_group.RG_AGW.name
  address_space = [ "10.0.0.0/16" ]
}

# create a singular subnet
resource "azurerm_subnet" "subnetA" {    
    name                 = "SubnetA"
    resource_group_name  = azurerm_resource_group.RG_AGW.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes     = ["10.0.0.0/24"]
    depends_on = [
      azurerm_virtual_network.vnet
    ]
}

# one block to create two interfaces using the for_each attribute
resource "azurerm_network_interface" "interface" {
  for_each = toset(local.function)
  name                = "${each.key}-interface"
  location            = azurerm_resource_group.RG_AGW.location  
  resource_group_name = azurerm_resource_group.RG_AGW.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnetA.id
    private_ip_address_allocation = "Dynamic"    
  }

  depends_on = [
    azurerm_virtual_network.vnet
  ]
}

##############################################################################################################################
#                                                  virtual machine + extension                                               #
##############################################################################################################################

# create two vms using one resource block, apply for_each and each.key to create a vm for images/videos
resource "azurerm_windows_virtual_machine" "vm" {
  for_each = toset(local.function)
  name                = "${each.key}vm"
  resource_group_name = azurerm_resource_group.RG_AGW.name                               # quota cannot pass 10 cores in this region
  location            = azurerm_resource_group.RG_AGW.location 
  size                = each.key == "videos" ? "Standard_D4s_v3" : "Standard_B2s"        # 6 cores for videos vm, 2 cores for images vm
  admin_username      = "adminuser"
  admin_password      = "Azure@123"      
    network_interface_ids = [
    azurerm_network_interface.interface[each.key].id,
  ]

  os_disk {                                                                              # configures operating system disk properties
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"                                                # sets storage type to - locally redundant storage
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"                                                # publisher of the OS image is microsoft 
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
  depends_on = [
    azurerm_virtual_network.vnet,
    azurerm_network_interface.interface
  ]
}

# one extension block will create an extension for each VM using the for_each attribute
resource "azurerm_virtual_machine_extension" "vmextension" {                             # will execute powershell script on a VM 
  for_each = toset(local.function)
  name                 = "${each.key}-extension"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm[each.key].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"                                        # this type will handle the powershell scripts for the VMs
  type_handler_version = "1.10"
  depends_on = [
    azurerm_storage_blob.IISConfig_blob
  ]                                                                                     # filesuri will point to the blobs that contain the scripts
  settings = <<SETTINGS                                 
    {
        "fileUris": ["https://${azurerm_storage_account.storage_account.name}.blob.core.windows.net/${azurerm_storage_container.container.name}/IIS_Config_${each.key}.ps1"],
          "commandToExecute": "powershell -ExecutionPolicy Unrestricted -file IIS_Config_${each.key}.ps1"     
    }
    SETTINGS

}

##############################################################################################################################
#                                             application gateway + IP + subnet                                              #
##############################################################################################################################

# create a public ip for subnet dedicated to the application gateway
resource "azurerm_public_ip" "ip_AGW" {
  name                = "application-gateway-ip"
  resource_group_name = azurerm_resource_group.RG_AGW.name
  location            = azurerm_resource_group.RG_AGW.location
  allocation_method   = "Static" 
  sku                 ="Standard"
  sku_tier            = "Regional"
}

# We need an additional subnet decicated to the application gateway
resource "azurerm_subnet" "SubnetB" {
  name                 = "subnet-AGW"
  resource_group_name  = azurerm_resource_group.RG_AGW.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"] 
}

# create an application gateway
resource "azurerm_application_gateway" "network_agw" {
  name                = "main-application-gateway"
  resource_group_name = azurerm_resource_group.RG_AGW.name
  location            = azurerm_resource_group.RG_AGW.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2                                                                    # sets the instance count to 2
  }

  gateway_ip_configuration {
    name      = "gateway-ip-configuration"
    subnet_id = azurerm_subnet.SubnetB.id                                           # mapped to subnet B
  }

  frontend_port {
    name = "front-end-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-configuration"
    public_ip_address_id = azurerm_public_ip.ip_AGW.id                              # mapped to public IP address aboce 
  }

  dynamic "backend_address_pool" {                                                  # creates 2 back end address pools based on local.functions -> images/videos
    for_each = toset(local.function)
    content {
      name = "${backend_address_pool.value}-pool"                                   # this value will be either images or videos

      ip_addresses = [ "${azurerm_network_interface.interface[backend_address_pool.value].private_ip_address}" ]      # specifies private IP address for each image/video
    }
  }

  backend_http_settings {
    name                  = "backend-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 2
  }

  http_listener {
    name                           = "gateway-listener"
    frontend_ip_configuration_name = "frontend-ip-configuration"
    frontend_port_name             = "front-end-port"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "routing-rule_a"
    rule_type                  = "PathBasedRouting"                                       # requests to /imaages/ go to its dedicated backend pool while /videos/ go to its own pool
    priority                   = 25                                                       # lower numbers indicate higher priority
    http_listener_name         = "gateway-listener"
    url_path_map_name          = "RoutingPath"
  }

url_path_map {
  name = "RoutingPath"
  default_backend_address_pool_name = "${local.function[0]}-pool"                        # sets default backend address pool if no path is specified, videos is first
  default_backend_http_settings_name = "backend-http-settings"

  dynamic "path_rule" {
    for_each = toset(local.function)                                                     # iterates a new path rule for images and videos
    content {
      name = "${path_rule.value}-RoutingRule"                                            # name of rule path is images-routingrule or videos-routingrule
      backend_address_pool_name = "${path_rule.value}-pool"
      backend_http_settings_name = "backend-http-settings"
      paths = [ "/${path_rule.value}/*" ]                                                # url pattern that will trigger path rule: ex /images/ - /videos/
      
        }
    }
  }
}


##############################################################################################################################
#                                                      security groups                                                       #
##############################################################################################################################


resource "azurerm_network_security_group" "sg" {
  name                = "sg_1"
  location            = azurerm_resource_group.RG_AGW.location
  resource_group_name = azurerm_resource_group.RG_AGW.name

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

depends_on = [
    azurerm_virtual_network.vnet
  ]
}

# associate subnetA with this security group
resource "azurerm_subnet_network_security_group_association" "sg_assoc" {  
  subnet_id                 = azurerm_subnet.subnetA.id
  network_security_group_id = azurerm_network_security_group.sg.id

  depends_on = [
    azurerm_virtual_network.vnet,
    azurerm_network_security_group.sg
  ]
}

##############################################################################################################################
#                                      storage account + container + blob                                   #
##############################################################################################################################

# create a storage account
resource "azurerm_storage_account" "storage_account" {
  name                     = "mf37"
  resource_group_name      = azurerm_resource_group.RG_AGW.name
  location                 = azurerm_resource_group.RG_AGW.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind = "StorageV2"  
  depends_on = [
    azurerm_resource_group.RG_AGW
  ]
}

#create a container 
resource "azurerm_storage_container" "container" {
  name                  = "scripts-data"
  storage_account_name  = azurerm_storage_account.storage_account.name
  container_access_type = "blob"
  depends_on=[
    azurerm_storage_account.storage_account
    ]
}

# create a blob from the two powershell scripts
resource "azurerm_storage_blob" "IISConfig_blob" {
  for_each = toset(local.function)
  name                   = "IIS_Config_${each.key}.ps1"
  storage_account_name   = azurerm_storage_account.storage_account.name
  storage_container_name = azurerm_storage_container.container.name
  type                   = "Block"
  source                 = "IIS_Config_${each.key}.ps1"
   depends_on=[azurerm_storage_container.container,
    azurerm_storage_account.storage_account]
}

