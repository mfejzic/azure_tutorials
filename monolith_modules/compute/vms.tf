resource "azurerm_network_interface" "db_nic" {
  name                = var.nic_name
  location            = var.vnet_location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.db_subnet_id
    private_ip_address_allocation = var.private_ip_address_allocation
    public_ip_address_id = try(azurerm_public_ip.db_public_ip[0].id,null)
  }
  depends_on = [ azurerm_public_ip.db_public_ip ]
}


resource "azurerm_public_ip" "db_public_ip" {
  count = var.publicip_required ? 1 : 0                                   # if true, count is 1 - if false, count is 0
  name                = var.publicip_name
  resource_group_name = var.resource_group_name
  location            = var.vnet_location
  allocation_method   = "Static"

  tags = {
    environment = "Production"
  }
}

resource "azurerm_windows_virtual_machine" "db_vm" {
  name                = "db-vm"
  resource_group_name = var.resource_group_name
  location            = var.vnet_location
  size                = "Standard_F2"
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  network_interface_ids = [
    azurerm_network_interface.db_nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = var.source_image_reference.publisher
    offer     = var.source_image_reference.offer
    sku       = var.source_image_reference.sku
    version   = var.source_image_reference.version
  }
}
