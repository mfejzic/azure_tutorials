# resource "azurerm_resource_group" "main_RG" {
#   name     = "main-resource-group"
#   location = "South Central US"
# }

data "azurerm_resource_group" "main_RG" {
  name = "main"
}
// 1. add custom domain to azure domain names, create txt record in route53 and add the value from azure domain names
// 2. chnage access type to blob on each $web container
// 3. change blob content type to text/html

// figure out which endpoint is best used for cname record
# ------------------------------------- US West -------------------------------------#

data "azurerm_storage_account" "westus" {
  name                = azurerm_storage_account.SA_west.name
  resource_group_name = data.azurerm_resource_group.main_RG.name
}

resource "azurerm_storage_account" "SA_west" {
  name                     = "mf37west"
  resource_group_name      = data.azurerm_resource_group.main_RG.name
  location                 = "westus"
  account_tier             = "Standard"
  account_replication_type = "RAGRS"

#   custom_domain {
#     name = "www.fejzic37.com"
#     use_subdomain = true
#   }

#   static_website {
#     index_document     = "index.html"
#     error_404_document = "error.html"
#   }

  tags = {
    environment = "staging"
  }
}

resource "azurerm_storage_account_static_website" "SA_west_static_website" {
  storage_account_id = azurerm_storage_account.SA_west.id
  error_404_document = "error.html"
  index_document     = "index.html"

  depends_on = [azurerm_storage_account.SA_west]
}

# resource "azurerm_storage_container" "west_container" {                               // if default $web is created first, manually delete it, then re-run apply  - or delete container block and manually upload index file into defualt $web container and switch access to blob
#   name                  = "$web"
#   storage_account_name = azurerm_storage_account.SA_west.name
#   container_access_type = "blob"
# }

data "azurerm_storage_container" "web_container_west" {
  name                  = "$web"
  storage_account_name  = azurerm_storage_account.SA_west.name
  

  depends_on = [ azurerm_storage_account_static_website.SA_west_static_website ]
}

resource "azurerm_storage_blob" "west_blob" {
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.SA_west.name
  storage_container_name = data.azurerm_storage_container.web_container_west.name      // $web is created by default after enabling static website, its recommended to upload index.html in this container
  type                   = "Block"
  source                 = "index.html"
  content_type = "text/html"
}

resource "azurerm_storage_blob" "west_error_blob" {
  name                   = "error.html"
  storage_account_name   = azurerm_storage_account.SA_west.name
  storage_container_name = data.azurerm_storage_container.web_container_west.name
  type                   = "Block"
  source                 = "error.html"
  content_type = "text/html"
}

resource "azurerm_storage_account_network_rules" "west_logs" {
  storage_account_id = azurerm_storage_account.SA_west.id

  default_action             = "Allow"
  ip_rules                   = ["0.0.0.0/0"]
  bypass                     = ["Metrics"]
}


# ------------------------------------- US East 2 -------------------------------------#

# data "azurerm_storage_account" "SA_east" {
#   name                = azurerm_storage_account.SA_east.name
#   resource_group_name = data.azurerm_resource_group.main_RG.name
# }

resource "azurerm_storage_account" "SA_east" {
  name                     = "mf37east"
  resource_group_name      = data.azurerm_resource_group.main_RG.name
  location                 = "eastus2"
  account_tier             = "Standard"
  account_replication_type = "RAGRS"

#   custom_domain {
#     name = "www.fejzic37.com"
#     use_subdomain = true
#   }

#   static_website {
#     index_document     = "index.html"
#     error_404_document = "error.html"
#   }

  tags = {
    environment = "staging"
  }
}

resource "azurerm_storage_account_static_website" "SA_east_static_website" {
  storage_account_id = azurerm_storage_account.SA_east.id
  error_404_document = "error.html"
  index_document     = "index.html"

  depends_on = [azurerm_storage_account.SA_east]
}

# resource "azurerm_storage_container" "east_container" {
#   name                  = "$web"
#   storage_account_name = azurerm_storage_account.SA_east.name
#   container_access_type = "blob"
# }

# Data block to reference the $web container created by Azure
data "azurerm_storage_container" "web_container_east" {
  name                  = "$web"
  storage_account_name  = azurerm_storage_account.SA_east.name

  depends_on = [ azurerm_storage_account_static_website.SA_east_static_website ]
}

resource "azurerm_storage_blob" "east_blob" {
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.SA_east.name
  storage_container_name = data.azurerm_storage_container.web_container_east.name                                       // $web is created by default after enabling static website, its recommended to upload index.html in this container
  type                   = "Block"
  source                 = "index.html"
  content_type = "text/html"
}

resource "azurerm_storage_blob" "east_error_blob" {
  name                   = "error.html"
  storage_account_name   = azurerm_storage_account.SA_east.name
  storage_container_name = data.azurerm_storage_container.web_container_east.name 
  type                   = "Block"
  source                 = "error.html"
  content_type = "text/html"
}

resource "azurerm_storage_account_network_rules" "east_logs" {
  storage_account_id = azurerm_storage_account.SA_east.id

  default_action             = "Allow"
  ip_rules                   = ["0.0.0.0/0"]
  bypass                     = ["Metrics"]
}


# ------------------------------------- Log Analytics -------------------------------------#

# Create the Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main_workspace" {
  name                = "main-log-analytics-workspace"
  location            = data.azurerm_resource_group.main_RG.location
  resource_group_name = data.azurerm_resource_group.main_RG.name
  sku                 = "PerGB2018"

  retention_in_days = 30

  tags = {
    environment = "staging"
  }

  depends_on = [ azurerm_cdn_profile.cdn_profile ]
}

# Enable diagnostic settings for Storage Account in US West
resource "azurerm_monitor_diagnostic_setting" "west_diagnostic" {
  name               = "west-diagnostics"
  target_resource_id = azurerm_cdn_endpoint.primary_endpoint.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main_workspace.id

#    enabled_log {
#     category = "Transaction"                                             //Enables CDN audit logs 
#   }

  enabled_log {
    category = "CoreAnalytics"                                               //Enables CDN metrics logs 
  }

  depends_on = [ azurerm_log_analytics_workspace.main_workspace, azurerm_cdn_endpoint.primary_endpoint ]
}

# Enable diagnostic settings for Storage Account in US East
resource "azurerm_monitor_diagnostic_setting" "east_diagnostic" {
  name               = "east-diagnostics"
  target_resource_id = azurerm_cdn_endpoint.secondary_endpoint.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main_workspace.id

#   enabled_log {
#     category = "Transaction"                                             //Enables CDN audit logs 
#   }

  enabled_log {
    category = "CoreAnalytics"                                               //Enables CDN metrics logs 
  }

  depends_on = [ azurerm_log_analytics_workspace.main_workspace, azurerm_cdn_endpoint.secondary_endpoint]
}

# ------------------------------------- CDN profile & endpoints -------------------------------------#

# Generate a random ID to append to the endpoint name
resource "random_id" "random_id" {
  byte_length = 8
}

# Create Azure CDN profile
resource "azurerm_cdn_profile" "cdn_profile" {
  name                = "cdn-profile"
  resource_group_name = data.azurerm_resource_group.main_RG.name
  location            = "Global"
  sku = "Standard_Microsoft"
}

# Primary CDN Endpoint in US West (points to primary storage)
resource "azurerm_cdn_endpoint" "primary_endpoint" {
  name               = "primary-endpoint-${random_id.random_id.hex}"
  profile_name       = azurerm_cdn_profile.cdn_profile.name
  resource_group_name = data.azurerm_resource_group.main_RG.name
  location = data.azurerm_resource_group.main_RG.location
  optimization_type = "GeneralWebDelivery"
  is_https_allowed = true
  
  origin {
    name      = "primary"
    host_name = replace(replace(azurerm_storage_account.SA_west.primary_web_endpoint, "https://", ""), "/", "")    // use replace regex to remove the https:// and last slash from the host name - went from "https://mf37west.z22.web.core.windows.net/\ to mf37west.z22.web.core.windows.net/ 
    //host_name = azurerm_storage_account.SA_west.primary_blob_host
    //host_name = azurerm_storage_account.SA_west.primary_web_host
  }

  depends_on = [ azurerm_cdn_profile.cdn_profile, azurerm_storage_account.SA_west ]
}

# Secondary CDN Endpoint in US East (points to secondary storage)
resource "azurerm_cdn_endpoint" "secondary_endpoint" {
  name               = "secondary-endpoint-${random_id.random_id.hex}"
  profile_name       = azurerm_cdn_profile.cdn_profile.name
  resource_group_name = data.azurerm_resource_group.main_RG.name
  location = "eastus2"
  optimization_type = "GeneralWebDelivery"

  origin {
    name      = "secondary"
    host_name = replace(replace(azurerm_storage_account.SA_east.secondary_web_endpoint, "https://", ""), "/", "") // enable GRS or RA_GRS in storage account to use the secondary web endpoint as a backup!!! if stil facing issues with secondary, use primary until GRS propogates across regions
    //host_name = azurerm_storage_account.SA_east.secondary_web_host
  }

  depends_on = [ azurerm_cdn_profile.cdn_profile, azurerm_storage_account.SA_east /* add primary endpoint */]
}

resource "azurerm_cdn_endpoint_custom_domain" "primary_endpoint_custom_domain" {
  name            = "domain"
  cdn_endpoint_id = azurerm_cdn_endpoint.primary_endpoint.id
  host_name       = "www.fejzic37.com"
#   cdn_managed_https {
#     certificate_type = "Shared"
#     protocol_type = "IPBased"                                              // manually enable custom https on azure portal - no idea why im getting cert type not supported error
#   }

   depends_on = [ azurerm_cdn_endpoint.primary_endpoint ]
}

# ------------------------------------- Route53 -------------------------------------#

data "aws_route53_zone" "hosted_zone" {
  name = "fejzic37.com"                                                          // your actual domain name managed in Route 53
}

# Primary CNAME Record (points to the Azure CDN endpoint for primary)
resource "aws_route53_record" "primary_cname" {
  zone_id = data.aws_route53_zone.hosted_zone.id
  name    = "www.${data.aws_route53_zone.hosted_zone.name}"
  type    = "CNAME"
  ttl     = 60
  health_check_id = aws_route53_health_check.primary_health_check.id

  records = [azurerm_storage_account.SA_west.primary_web_host]                                // or try azurerm_cdn_endpoint.secondary_endpoint.fqdn - "mf37west.z22.web.core.windows.net"

  set_identifier = "primary"
  failover_routing_policy {
    type = "PRIMARY"
  }
}

resource "aws_route53_health_check" "primary_health_check" {
  //fqdn = azurerm_cdn_endpoint.primary_endpoint.fqdn                                          // Your primary CDN endpoint
   //fqdn = azurerm_storage_account.SA_west.primary_blob_endpoint
   fqdn = "mf37west.z22.web.core.windows.net"
  type = "HTTP"
}

//Secondary CNAME Record (points to the Azure CDN endpoint for secondary with failover)
# resource "aws_route53_record" "secondary_cname" {
#   zone_id = data.aws_route53_zone.hosted_zone.zone_id
#   name    = "www.${data.aws_route53_zone.hosted_zone.name}"
#   type    = "CNAME"
#   ttl     = 60
#   records = [azurerm_cdn_endpoint.secondary_endpoint.fqdn]

#   set_identifier = "secondary"
#   failover_routing_policy {
#     type = "SECONDARY"
#   }

# #   depends_on = [ azurerm_cdn_endpoint.primary_endpoint, aws_route53_record.primary_cname ]
# }
