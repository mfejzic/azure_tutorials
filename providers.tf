terraform {
  # backend "azurerm" {
  #   resource_group_name  = "tutorial_RG"
  #   storage_account_name  = "mf37"
  #   container_name        = "<your-container-name>"
  #   key                   = "data.tfstate"
  # }
  required_providers {
    
    azurerm = {
      source = "hashicorp/azurerm"
      version = "4.2.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "064b2bea-3fc1-4bf7-b067-3d942c23e4dd"
  tenant_id = "16983dae-9f48-4a35-b9f5-0519bf3cdf09"
  client_id = "a4815ff2-fc06-4608-b1c6-9b902ac9ffb3"
  client_secret = "MWh8Q~ga.sD4kz6HEvOalPL_cwYTZJXxX47eZbkX"
}