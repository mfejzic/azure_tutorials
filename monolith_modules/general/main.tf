
resource "azurerm_resource_group" "main_RG" {
  name = var.resource_group_name
  location = var.resource_group_location
}
