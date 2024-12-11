
output "dns_zone_name" {
  value = data.azurerm_dns_zone.dns_zone.name
  description = "The name of the DNS zone"
}

output "resource_group_name" {
  value = data.azurerm_resource_group.main_RG.name
  description = "The name of the resource group"
}
