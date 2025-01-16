
output "subnets_zone1" {
  value       = local.subnets_zone1
  description = "List of subnets in Zone 1"
}

output "subnets_zone2" {
  value       = local.subnets_zone2
  description = "List of subnets in Zone 2"
}

output "public_subnets" {
  value = local.public_subnets
  description = "List of public subnet names in zone 1 and zone 2"
}

output "zone_names" {
  value = local.zones
  description = "List of zone names"
}

output "public_ip_nat_agw_zone2" {
  value = azurerm_public_ip.public_ip_nat_agw.zones
  description = "public_ip_nat_agw zone"
}

output "vmscale_set_1_zone" {
  value = azurerm_linux_virtual_machine_scale_set.linux_vm.zones
  description = "prisub1 vm zone"
}


