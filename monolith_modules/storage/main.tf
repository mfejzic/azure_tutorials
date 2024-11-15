resource "azurerm_storage_account" "SA_name" {
  name                     = var.SA_name
  resource_group_name      = var.resource_group_name
  location                 = var.vnet_location
  account_tier             = "Standard"
  account_replication_type = "GRS"

  tags = {
    environment = "staging"
  }
}

resource "azurerm_storage_container" "container" {
  name                  = var.container_name
  storage_account_name  = var.SA_name
  container_access_type = var.container_access

  depends_on = [ azurerm_storage_account.SA_name ]
}

data "template_file" "userdata" {
    for_each = var.blobs
    template = file("${each.value}")
    vars = {
      SA_name = var.SA_name
      container_name = var.container_access
      app_container_name = var.app_container_name
    }
}

resource "azurerm_storage_blob" "blob" {
  for_each = var.blobs
  name                   = each.key
  storage_account_name   = var.SA_name
  storage_container_name = var.container_name
  type                   = "Block"
  source_content = data.template_file.userdata[each.key].rendered
  //source                 = each.value

  depends_on = [ azurerm_storage_container.container ]
}
