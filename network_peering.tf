# locals {
#   location= var.Central_US
#   environment = {
#     staging="10.0.0.0/16"
#     test="10.1.0.0/16"
#     }
# }

# resource "azurerm_resource_group" "RG_networkpeering" {
#   name     = "network_peering_resource_group"
#   location = var.Central_US
# }

# resource "azurerm_virtual_network" "network" {
#   for_each = local.environment
#   name                = "${each.key}-network"
#   location            = local.location  
#   resource_group_name = azurerm_resource_group.RG_networkpeering.name
#   address_space       = [each.value]
#   depends_on = [
#     azurerm_resource_group.RG_networkpeering
#   ]  

#   subnet {
#     name           = "${each.key}subnet"
#     address_prefixes = [cidrsubnet(each.value,8,0)]
#   }
# } 

# resource "azurerm_virtual_network_peering" "peeringconnection1" {
#   name                      = "stagingtotest"
#   resource_group_name       = azurerm_resource_group.RG_networkpeering.name
#   virtual_network_name      = azurerm_virtual_network.network["staging"].name
#   remote_virtual_network_id = azurerm_virtual_network.network["test"].id
# }

# resource "azurerm_virtual_network_peering" "peeringconnection2" {
#   name                      = "testtostaging"
#   resource_group_name       = azurerm_resource_group.RG_networkpeering.name
#   virtual_network_name      = azurerm_virtual_network.network["test"].name
#   remote_virtual_network_id = azurerm_virtual_network.network["staging"].id
# }


# resource "azurerm_network_interface" "interface" {
#   for_each = local.environment
#   name                = "${each.key}-interface"
#   location            = local.location  
#   resource_group_name = azurerm_resource_group.RG_networkpeering.name

#   ip_configuration {
#     name                          = "internal"
#     subnet_id                     = azurerm_virtual_network.network[each.key].subnet.*.id[0]
#     private_ip_address_allocation = "Dynamic"    
#     public_ip_address_id = azurerm_public_ip.ip[each.key].id
#   }

#   depends_on = [
#     azurerm_virtual_network.network
#   ]
# }

# resource "azurerm_public_ip" "ip" {
#  for_each = local.environment
#   name                = "${each.key}-ip"
#   resource_group_name = azurerm_resource_group.RG_networkpeering.name
#   location            = local.location  
#   allocation_method   = "Static"
#   sku = "Standard"
#   depends_on = [
#     azurerm_resource_group.RG_networkpeering
#   ]
# }


# resource "azurerm_windows_virtual_machine" "vm" {
#   for_each = local.environment
#   name                = "${each.key}vm"
#   resource_group_name = azurerm_resource_group.RG_networkpeering.name
#   location            = local.location 
#   size                = "Standard_D2s_v3"
#   admin_username      = "adminuser"
#   admin_password      = "Azure@123"      
#     network_interface_ids = [
#     azurerm_network_interface.interface[each.key].id,
#   ]

#   os_disk {
#     caching              = "ReadWrite"
#     storage_account_type = "Standard_LRS"
#   }

#   source_image_reference {
#     publisher = "MicrosoftWindowsServer"
#     offer     = "WindowsServer"
#     sku       = "2019-Datacenter"
#     version   = "latest"
#   }
#   depends_on = [
#     azurerm_virtual_network.network,
#     azurerm_network_interface.interface
#   ]
# }



# resource "azurerm_network_security_group" "nsg" {
#   for_each = local.environment
#   name                = "${each.key}-nsg"
#   location            = azurerm_resource_group.RG_networkpeering.location
#   resource_group_name = azurerm_resource_group.RG_networkpeering.name

#   security_rule {
#     name                       = "AllowRDP"
#     priority                   = 300
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                   = "Tcp"
#     source_port_range          = "*"
#     destination_port_range     = "3389"
#     source_address_prefix      = "*"
#     destination_address_prefix = "*"
#   }
  
# depends_on = [
#     azurerm_virtual_network.network
#   ]
# }

# resource "azurerm_subnet_network_security_group_association" "nsg-link" {
#   for_each = local.environment
#   subnet_id                 = azurerm_virtual_network.network[each.key].subnet.*.id[0]
#   network_security_group_id = azurerm_network_security_group.nsg[each.key].id

#   depends_on = [
#     azurerm_virtual_network.network,
#     azurerm_network_security_group.nsg
#   ]
# }


# resource "azurerm_storage_account" "storage_account" {
#   name                     = "scriptsmf37"
#   resource_group_name      = azurerm_resource_group.RG_networkpeering.name
#   location                 = local.location
#   account_tier             = "Standard"
#   account_replication_type = "LRS"
#   account_kind = "StorageV2"  
#   depends_on = [
#     azurerm_resource_group.RG_networkpeering
#   ]
# }

# resource "azurerm_storage_container" "container" {
#   name                  = "script-data"
#   storage_account_name  = azurerm_storage_account.storage_account.name
#   container_access_type = "blob"
#   depends_on=[
#     azurerm_storage_account.storage_account
#     ]
# }

# resource "azurerm_storage_blob" "IISConfig" {
#   name                   = "IIS_Config.ps1"
#   storage_account_name   = azurerm_storage_account.storage_account.name
#   storage_container_name = azurerm_storage_container.container.name
#   type                   = "Block"
#   source                 = "IIS_Config.ps1"
#    depends_on=[azurerm_storage_container.container,
#     azurerm_storage_account.storage_account]
# }


# resource "azurerm_virtual_machine_extension" "extension" {  
#   name                 = "extension"
#   virtual_machine_id   = azurerm_windows_virtual_machine.vm["test"].id
#   publisher            = "Microsoft.Compute"
#   type                 = "CustomScriptExtension"
#   type_handler_version = "1.10"
#   depends_on = [
#     azurerm_storage_blob.IISConfig,
#     azurerm_windows_virtual_machine.vm
#   ]
#   settings = <<SETTINGS
#     {
#         "fileUris": ["https://${azurerm_storage_account.storage_account.name}.blob.core.windows.net/${azurerm_storage_container.container.name}/IIS_Config.ps1"],
#           "commandToExecute": "powershell -ExecutionPolicy Unrestricted -file IIS_Config.ps1"     
#     }
# SETTINGS


# }
