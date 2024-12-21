
# output "dns_zone_name" {
#   value = data.azurerm_dns_zone.dns_zone.name
#   description = "The name of the DNS zone"
# }

# output "resource_group_name" {
#   value = data.azurerm_resource_group.main_RG.name
#   description = "The name of the resource group"
# }

output "secondary_web_endpoint" {
  value = azurerm_storage_account.SA_east.secondary_web_endpoint
}

output "primary_web_endpoint" {
  value = azurerm_storage_account.SA_west.primary_web_endpoint
}
