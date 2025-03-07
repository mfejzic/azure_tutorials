# manually build a web server - create an image of that server
   # create 2019 windows datacenter vm
   # go to tools -> IIS manager -> webvm -> management service -> enable remote connection -> port should be 8172-> click on apply/start
   # disable enhanced secuirty configuration and install the following - IIS - .net 6.0 ASP.NET Core Runtime 6.0.35 hosting bundle - web deploy amd64_en_US.msi
   # configure port 8172 - change dns name



locals {
  resource_group_name = "main_resource_group"
  location            = "WESTUS"
  virtual_network = {
    address_space = "10.0.0.0/16"
  }
}

# ------------------------------------- general module -------------------------------------#

module "general_module" {
  source                  = "./monolith_modules/general"
  resource_group_name     = local.resource_group_name
  resource_group_location = local.location
}

# ------------------------------------- virtual network module -------------------------------------#

module "vnet" {
  source              = "./monolith_modules/vnet"
  resource_group_name = local.resource_group_name
  vnet_name           = "main_vnet"
  vnet_location       = local.location
  vnet_address_space  = "10.0.0.0/16"
  subnet_names        = ["web-subnet", "db-subnet"]
  bastion_required    = true # false by default

  #use type map(string)
  nsg_names = {
    "web-nsg" = "web-subnet"
    "db-nsg"  = "db-subnet"
  }

  nsg_rules = [{
    id                          = 1,
    priority                    = "200"
    network_security_group_name = "web-nsg"
    destination_port_range      = "3389"
    access                      = "Allow"
    }, {
    id                          = 2,
    priority                    = "300"
    network_security_group_name = "web-nsg"
    destination_port_range      = "80"
    access                      = "Allow"
    }, {
    id                          = 3,
    priority                    = "400"
    network_security_group_name = "web-nsg"
    destination_port_range      = "8173"
    access                      = "Allow"
    }, {
    id                          = 4,
    priority                    = "200"
    network_security_group_name = "db-nsg"
    destination_port_range      = "3389"
    access                      = "Allow"
  }]
}
# manually defines subnet space
/* subnet_names = {
    "web-subnet" = "10.0.0.0/24"
    "db-subnet" = "10.0.1.0/24"
  } */


# ------------------------------------- database module -------------------------------------#

module "compute" {
  source              = "./monolith_modules/compute"
  vnet_location       = local.location
  resource_group_name = local.resource_group_name
  db_subnet_id = module.vnet.subnets["db-subnet"].id
  nic_name = "db-nic"
  publicip_name = "db_name"
  publicip_required = false
  vmdb_name = "db-vm"
  admin_username = "adminuser"
  admin_password = "P@$$w0rd1234!"

  source_image_reference = {
    publisher = "MicrosoftSQLServer"
    offer     = "sql2019-ws2019"
    sku       = "sqldev"
    version   = "latest"
  }

  depends_on = [ module.vnet ]

}


# ------------------------------------- storage account module -------------------------------------#

# adds storage account, container and a blob for each script
module "storage_module" {
    source = "./monolith_modules/storage"
    vnet_location = local.location
    resource_group_name = local.resource_group_name
    SA_name = "mf37"
    container_name = "data"
    app_container_name = "images"
    container_access = "blob"
    blob_name = "script"
    blobs = {
        "01.sql" = "01.sql"
        "scripts.ps1" = "scripts.ps1"
    }

    depends_on = [ module.general_module ]
}


# ------------------------------------- custom script module -------------------------------------#

# adds extension to database virtual machine
module "customscript" {
  source = "./monolith_modules/compute/customscript"
  extension_name = "dbvm-extension"
  virtual_machine_id = module.compute.db_vm.id
  SA_name = "mf37"
  container_name = "data"
  extension_type = {
    publisher            = "Microsoft.Compute"
    type                 = "CustomScriptExtension"
    type_handler_version = "1.10"
  }
  depends_on = [ module.compute, module.storage_module ]
}


############################################################################################
#                                  webserver virtual machine                               #
############################################################################################

resource "azurerm_mssql_virtual_machine" "mysql_vm" {
  virtual_machine_id               = module.compute.db_vm.id
  sql_license_type   = "PAYG"
  sql_connectivity_update_password = "Azure@1234"
  sql_connectivity_update_username = "sqladmin"
  sql_connectivity_port            = 1433
  sql_connectivity_type            = "PRIVATE"

}

resource "azurerm_network_interface" "image_interface" {
  name                = "image-nic"
  location            = local.location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.vnet.subnets["web-subnet"].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.image_publicip.id
  }
  depends_on = [module.vnet.main_vnet, azurerm_public_ip.image_publicip]
}

resource "azurerm_public_ip" "image_publicip" {
  name                = "image-publicip"
  resource_group_name = local.resource_group_name
  location            = local.location
  allocation_method   = "Static"

  tags = {
    environment = "Production"
  }
}

# populate with name of image definition
data "azurerm_shared_image" "image" {
  name                = "defineimage1"
  gallery_name        = "imagegallery"
  resource_group_name = "new-grp"
  depends_on          = [module.general_module.main_RG]
}

# create a virtual machine from the image
resource "azurerm_virtual_machine" "webvm" {                            # incompatible with trusted launch
  name                  = "web-vm"
  location              = local.location
  resource_group_name   = local.resource_group_name
  network_interface_ids = [azurerm_network_interface.image_interface.id]
  vm_size               = "Standard_DC2s_v2"
  

  storage_image_reference {
    id = data.azurerm_shared_image.image.id
    
  }
  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  depends_on = [azurerm_network_interface.image_interface, module.general_module.main_RG]
}
