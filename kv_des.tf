# ------------------------------------- basic startup -------------------------------------#

resource "azurerm_resource_group" "rg1" {
  name     = "resource-group"
  location = "West Europe"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_group" "sg1" {
  name                = "security-group1"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name
}

resource "azurerm_virtual_network" "vm1" {
  name                = "vm1"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name
  address_space       = ["10.0.0.0/16"]
  dns_servers         = ["10.0.0.4", "10.0.0.5"]

  tags = {
    environment = "Production"
  }
}

resource "azurerm_subnet" "subnet1" {
  name                 = "subnet1"
  resource_group_name  = azurerm_resource_group.rg1.name
  virtual_network_name = azurerm_virtual_network.vm1.name
  address_prefixes     = ["10.0.1.0/24"]
}


# ------------------------------------- azure virtual machine & interface -------------------------------------#

resource "azurerm_network_interface" "interface" {
  name                = "nic1"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.subnet1.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_virtual_machine" "main" {
  name                  = "vm1"
  location              = azurerm_resource_group.rg1.location
  resource_group_name   = azurerm_resource_group.rg1.name
  network_interface_ids = [azurerm_network_interface.interface.id]
  vm_size               = "Standard_DS1_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
   delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "hostname"
    admin_username = "testadmin"
    admin_password = "Password1234!"
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    environment = "staging"
  }
}


# ------------------------------------- key vault & disk encryption -------------------------------------#

data "azurerm_client_config" "kv1" {

}


# Create Key Vault
resource "azurerm_key_vault" "kv1" {
  tenant_id = data.azurerm_client_config.kv1.tenant_id
  name                = "kv1mf37"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name
  sku_name            = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.kv1.tenant_id
    object_id = data.azurerm_client_config.kv1.object_id

    key_permissions = [
      "Get",
      "List",
    ]

    secret_permissions = [
      "Get",
      "List",
      "Set",
    ]
  }
}

# Store VM password as a secret
resource "azurerm_key_vault_secret" "vm1_password" {
  name         = "vm1-password"
  value        = "Password1234!" # You can also use a variable here if you want
  key_vault_id = azurerm_key_vault.kv1.id
}

resource "azurerm_disk_encryption_set" "des_1" {
  name                = "des-1"
  resource_group_name = azurerm_resource_group.rg1.name
  location            = azurerm_resource_group.rg1.location
  key_vault_key_id    = azurerm_key_vault_key.kv1.id

  identity {
    type = "SystemAssigned"
  }
}
