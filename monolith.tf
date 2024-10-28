## ! BIG STUFF HAPPENING ! ##
# manually build a web server - create an image of that server
   # create 2019 windows datacenter vm
   # go to tools -> IIS manager -> webvm -> management service -> enable remote connection -> port should be 8172-> click on apply/start
   # disable enhanced secuirty configuration and install the following - IIS - .net 6.0 ASP.NET Core Runtime 6.0.35 hosting bundle - web deploy amd64_en_US.msi
   # configure port 8172 - change dns name

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
  resource_group_name = local.resource_group_name
  depends_on = [ module.general_module.main_RG ]
}

# create a virtual machine from the image
resource "azurerm_virtual_machine" "webvm" {
  name                  = "web-vm"
  location              = local.location
  resource_group_name   = local.resource_group_name
  network_interface_ids = [azurerm_network_interface.image_interface.id]
  vm_size               = "Standard_DS1_v2"

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
