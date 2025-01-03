
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
