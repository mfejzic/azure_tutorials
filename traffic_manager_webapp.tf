# this config sets up a web application involving the creation of a resource group, app service plan, web apps, traffic manager and custome hostname bindings
# Two app service plans - one for each web app, a primary web app in the west US region with standard SKU, and a secondary web app in the east US region with basic SKU
# both apps are configured to run on the .NET 6.0 stack
# traffic manager is used to route traffic based on priority, primary has a priority of 1 while secondary has a priority of 2, if primary webapp fails, traffic manager will fallback to secondary webapp
## traffic routing method can be changed to failover, performance, weighted, etc
# custom hostname bindings are used to link the traffic manager's FQDN(fully qualified domain name) to their respective webapps 
# the endpoints manage traffic distribution between the two web apps, if primary goes down, TM will automatically redirect traffic to the secondary webapp


resource "azurerm_resource_group" "RG_webapp" {
  name = "webapp-RG"
  location = var.Central_US
}

#--------------- primary app in west us ----------------#
# create defualt.html pages manually in app service editor
resource "azurerm_service_plan" "primary_service_plan" {
  name                = "primary-service-plan"
  resource_group_name = azurerm_resource_group.RG_webapp.name
  location            = azurerm_resource_group.RG_webapp.location
  os_type             = "Windows"
  sku_name            = "S1"

depends_on = [ azurerm_resource_group.RG_webapp ]
}

resource "azurerm_windows_web_app" "primary_windows_webapp" {
  name                = "primary-webapp-mf37"
  resource_group_name = azurerm_resource_group.RG_webapp.name
  location            = azurerm_service_plan.primary_service_plan.location
  service_plan_id     = azurerm_service_plan.primary_service_plan.id

  site_config {
    application_stack {
      current_stack = "dotnet"
      dotnet_version = "v6.0"
    }
  }

  depends_on = [ azurerm_service_plan.primary_service_plan ]

}

#--------------- secondary app in east us ----------------#
# create defualt.html pages manually in app service editor
resource "azurerm_service_plan" "secondary_service_plan" {
  name                = "secondary-service-plan"
  resource_group_name = azurerm_resource_group.RG_webapp.name
  location            = var.West_US
  os_type             = "Windows"
  sku_name            = "B1"

  depends_on = [ azurerm_resource_group.RG_webapp ]
}

resource "azurerm_windows_web_app" "secondary_windows_webapp" {
  name                = "secondary-webapp-mf37"
  resource_group_name = azurerm_resource_group.RG_webapp.name
  location            = azurerm_service_plan.secondary_service_plan.location
  service_plan_id     = azurerm_service_plan.secondary_service_plan.id

  site_config {
    application_stack {
      current_stack = "dotnet"
      dotnet_version = "v6.0"
    }
  }

    depends_on = [ azurerm_service_plan.secondary_service_plan ]

}

#---------------- traffic manager profile --------------#
resource "azurerm_traffic_manager_profile" "TM_webapp" {
  name                   = "webapp-mf37"
  resource_group_name    = azurerm_resource_group.RG_webapp.name
  traffic_routing_method = "Priority"

  dns_config {
    relative_name = "webapp-mf37"
    ttl           = 100
  }

  monitor_config {
    protocol                     = "HTTPS"
    port                         = 443
    path                         = "/"
    interval_in_seconds          = 30
    timeout_in_seconds           = 9
    tolerated_number_of_failures = 3
  }

  depends_on = [ azurerm_resource_group.RG_webapp ]

  tags = {
    environment = "Production"
  }
}

#--------------- endpoints for primary/secondary webapps ----------------#
resource "azurerm_traffic_manager_azure_endpoint" "primary_endpoint" {
  name                 = "primary-endpoint"
  profile_id           = azurerm_traffic_manager_profile.TM_webapp.id
  priority = 1
  always_serve_enabled = true
  weight               = 100
  target_resource_id   = azurerm_windows_web_app.primary_windows_webapp.id

  custom_header {
    name = "host"
    value = "${azurerm_windows_web_app.primary_windows_webapp.name}.azurewebsites.net"
  }

  depends_on = [ azurerm_windows_web_app.primary_windows_webapp ]
}

resource "azurerm_traffic_manager_azure_endpoint" "secondary_endpoint" {
  name                 = "secondary-endpoint"
  profile_id           = azurerm_traffic_manager_profile.TM_webapp.id
  priority = 2
  always_serve_enabled = true
  weight               = 100
  target_resource_id   = azurerm_windows_web_app.secondary_windows_webapp.id

  custom_header {
    name = "host"
    value = "${azurerm_windows_web_app.secondary_windows_webapp.name}.azurewebsites.net"
  }

  depends_on = [ azurerm_windows_web_app.secondary_windows_webapp ]
}

#--------------- bindings for primary/secondary ----------------#
resource "azurerm_app_service_custom_hostname_binding" "primary_binding" {                       # bindings allows you to bind a custom domain name like webapp-mf37.trafficmanager.net to an azure web app/service
  hostname            = "${azurerm_traffic_manager_profile.TM_webapp.fqdn}"
  app_service_name    = azurerm_windows_web_app.primary_windows_webapp.name
  resource_group_name = azurerm_resource_group.RG_webapp.name

  depends_on = [ azurerm_traffic_manager_azure_endpoint.primary_endpoint ]
}

resource "azurerm_app_service_custom_hostname_binding" "secondary_binding" {
  hostname            = "${azurerm_traffic_manager_profile.TM_webapp.fqdn}"
  app_service_name    = azurerm_windows_web_app.secondary_windows_webapp.name
  resource_group_name = azurerm_resource_group.RG_webapp.name

  depends_on = [ azurerm_traffic_manager_azure_endpoint.secondary_endpoint ]
}
