output "virtual_network" {
  value=azurerm_virtual_network.main_vnet
}

output "subnets" {
  value=azurerm_subnet.subnets
}
