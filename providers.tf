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
  subscription_id = ""
  tenant_id = ""
  client_id = ""
  client_secret = ""
}
