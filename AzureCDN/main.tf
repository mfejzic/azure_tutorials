# resource "azurerm_resource_group" "main_RG" {
#   name     = "main-resource-group"
#   location = "South Central US"
# }

data "azurerm_resource_group" "main_RG" {
  name = "main"
}


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

  static_website {
    index_document     = "index.html"
    error_404_document = "error.html"
  }

  tags = {
    environment = "staging"
  }
}

resource "azurerm_storage_container" "west_container" {
  name                  = "primary-blob"
  storage_account_name = azurerm_storage_account.SA_west.name
  container_access_type = "blob"

  depends_on = [ azurerm_storage_account.SA_west ]
}

resource "azurerm_storage_blob" "west_blob" {
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.SA_west.name
  storage_container_name = azurerm_storage_container.west_container.name
  type                   = "Block"
  source                 = "index.html"
}

resource "azurerm_storage_blob" "west_error_blob" {
  name                   = "error.html"
  storage_account_name   = azurerm_storage_account.SA_west.name
  storage_container_name = azurerm_storage_container.west_container.name
  type                   = "Block"
  source                 = "error.html"
}

resource "azurerm_storage_account_network_rules" "west_logs" {
  storage_account_id = azurerm_storage_account.SA_west.id

  default_action             = "Allow"
  ip_rules                   = ["0.0.0.0/0"]
  bypass                     = ["Metrics"]
}


# ------------------------------------- US East 2 -------------------------------------#

data "azurerm_storage_account" "SA_east" {
  name                = azurerm_storage_account.SA_east.name
  resource_group_name = data.azurerm_resource_group.main_RG.name
}

resource "azurerm_storage_account" "SA_east" {
  name                     = "mf37east"
  resource_group_name      = data.azurerm_resource_group.main_RG.name
  location                 = "eastus2"
  account_tier             = "Standard"
  account_replication_type = "RAGRS"

  static_website {
    index_document     = "index.html"
    error_404_document = "error.html"
  }

  tags = {
    environment = "staging"
  }
}

resource "azurerm_storage_container" "east_container" {
  name                  = "secondary-blob"
  storage_account_name = azurerm_storage_account.SA_east.name
  container_access_type = "blob"
}

resource "azurerm_storage_blob" "east_blob" {
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.SA_east.name
  storage_container_name = azurerm_storage_container.east_container.name
  type                   = "Block"
  source                 = "index.html"
}

resource "azurerm_storage_blob" "east_error_blob" {
  name                   = "error.html"
  storage_account_name   = azurerm_storage_account.SA_east.name
  storage_container_name = azurerm_storage_container.east_container.name
  type                   = "Block"
  source                 = "error.html"
}

resource "azurerm_storage_account_network_rules" "east_logs" {
  storage_account_id = azurerm_storage_account.SA_east.id

  default_action             = "Allow"
  ip_rules                   = ["0.0.0.0/0"]
  bypass                     = ["Metrics"]
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
  }

  depends_on = [ azurerm_cdn_profile.cdn_profile ]
}

# Secondary CDN Endpoint in US East (points to secondary storage)
resource "azurerm_cdn_endpoint" "secondary_endpoint" {
  name               = "secondary-endpoint-${random_id.random_id.hex}"
  profile_name       = azurerm_cdn_profile.cdn_profile.name
  resource_group_name = data.azurerm_resource_group.main_RG.name
  location = "EASTUS2"
  optimization_type = "GeneralWebDelivery"

  origin {
    name      = "secondary"
    host_name = replace(replace(azurerm_storage_account.SA_east.secondary_web_endpoint, "https://", ""), "/", "") // enable GRS or RA_GRS in storage account to use the secondary web endpoint as a backup!!! if stil facing issues with secondary, use primary until GRS propogates across regions
  }

  depends_on = [ azurerm_cdn_profile.cdn_profile, azurerm_cdn_endpoint.primary_endpoint ]
}

# resource "azurerm_cdn_endpoint_custom_domain" "primary_endpoint_custom_domain" {
#   name            = "domain"
#   cdn_endpoint_id = azurerm_cdn_endpoint.primary_endpoint.id
#   host_name       = "www.fejzic37.com"
#   cdn_managed_https {
#     certificate_type = "Shared"
#     protocol_type = "IPBased"                                   // manually enable custom https on azure portal - no idea why im getting cert type not supported error
#   }

# #   depends_on = [ azurerm_cdn_endpoint.primary_endpoint ]
# }


# ------------------------------------- Route53 -------------------------------------#

data "aws_route53_zone" "hosted_zone" {
  name = "fejzic37.com"  # Replace with your actual domain name managed in Route 53
}

# Primary CNAME Record (points to the Azure CDN endpoint for primary)
resource "aws_route53_record" "primary_cname" {
  zone_id = data.aws_route53_zone.hosted_zone.id
  name    = "www.${data.aws_route53_zone.hosted_zone.name}"
  type    = "CNAME"
  ttl     = 60
  health_check_id = aws_route53_health_check.primary_health_check.id

  records = [azurerm_cdn_endpoint.primary_endpoint.fqdn]

  set_identifier = "primary"
  failover_routing_policy {
    type = "PRIMARY"
  }
}

resource "aws_route53_health_check" "primary_health_check" {
  fqdn = azurerm_cdn_endpoint.primary_endpoint.fqdn  # Your primary CDN endpoint

  type = "HTTPS"
  resource_path = "/index.html"
  failure_threshold = 3
  request_interval = 30
  port = 443
}

# Secondary CNAME Record (points to the Azure CDN endpoint for secondary with failover)
resource "aws_route53_record" "secondary_cname" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name    = "www.${data.aws_route53_zone.hosted_zone.name}"
  type    = "CNAME"
  ttl     = 60
  records = [azurerm_cdn_endpoint.secondary_endpoint.fqdn]

  set_identifier = "secondary"
  failover_routing_policy {
    type = "SECONDARY"
  }

#   depends_on = [ azurerm_cdn_endpoint.primary_endpoint, aws_route53_record.primary_cname ]
}

# resource "aws_route53_record" "primary_cname" {
#   zone_id = data.aws_route53_zone.dns_zone.zone_id
#   name    = "www.${data.aws_route53_zone.domain.name}"
#   type    = "CNAME"
#   ttl     = "60"

#   records = [azurerm_cdn_endpoint.primary_endpoint.name]
# }

# resource "aws_route53_record" "secondary_cname" {
#   zone_id = data.aws_route53_zone.dns_zone.zone_id
#   name    = "www.${data.aws_route53_zone.domain.name}"
#   type    = "CNAME"
#   ttl     = "60"

#   records = [azurerm_cdn_endpoint.secondary_endpoint.name]
# }

# ------------------------------------- Log Analytics -------------------------------------#

# resource "azurerm_log_analytics_workspace" "example" {
#   name                = "example-workspace"
#   location            = azurerm_resource_group.main_RG.location
#   resource_group_name = azurerm_resource_group.main_RG.name
#   sku                 = "PerGB2018"

#   retention_in_days = 30
# }

# # Diagnostic Settings to monitor Storage Account logs and metrics
# resource "azurerm_monitor_diagnostic_setting" "example" {
#   name               = "example"
#   target_resource_id = azurerm_key_vault.example.id
#   storage_account_id = azurerm_storage_account.example.id

#   enabled_log {
#     category = "AuditEvent"
#   }

#   metric {
#     category = "AllMetrics"
#   }
# }

# ------------------------------------- DNS Zone -------------------------------------#

# resource "azurerm_dns_zone" "dnszone" {
#   name                = "www.fejzic37.com"
#   resource_group_name = azurerm_resource_group.main_RG.name

#   depends_on = [ azurerm_resource_group.main_RG ]
# }

# resource "azurerm_dns_cname_record" "cname" {
#   name                = "test"
#   zone_name           = azurerm_dns_zone.dnszone.name
#   resource_group_name = azurerm_resource_group.main_RG.name
#   ttl                 = 300
#   record              = azurerm_frontdoor.cdn.frontend_endpoint[0].host_name

#   depends_on = [ azurerm_resource_group.main_RG ]
# }

# # ------------------------------------- Front Door CDN -------------------------------------#

# resource "azurerm_frontdoor" "cdn" {
#   name                = "mf37frontdoor"
#   resource_group_name = azurerm_resource_group.main_RG.name

#   frontend_endpoint {
#     name      = "front-endpoint"
#     host_name = "www.fejzic37.com"
#   }

# # ------------------------------------- South Central -------------------------------------#
#   routing_rule {
#     name               = "route-to-southcentral"
#     accepted_protocols = ["Https"]
#     patterns_to_match  = ["/sc/*"]                                    
#     frontend_endpoints = ["front-endpoint"]

#     forwarding_configuration {
#       forwarding_protocol = "MatchRequest"
#       backend_pool_name   = "backend-pool-southcentral"
#     }
#   }

#   backend_pool {
#     name = "backend-pool-southcentral"
#     backend {
#       host_header = "www.fejzic37.com"     # Replace with your storage account's static website endpoint - may use data block?
#       address     = "www.fejzic37.com"
#       http_port   = 80
#       https_port  = 443
#     }

#     health_probe_name   = "southcentral-healthprobe"
#     load_balancing_name = "load-balancing"
#   }

#   backend_pool_health_probe {
#     name = "southcentral-healthprobe"
#     interval_in_seconds = 30
#     path = "/index.html"
#     protocol = "Https"
    
#   }

# # ------------------------------------- US West -------------------------------------#
#   routing_rule {
#     name               = "route-to-west"
#     accepted_protocols = ["Https"]
#     patterns_to_match  = ["/west/*"]                                    # matches all URL's
#     frontend_endpoints = ["front-endpoint"]

#     forwarding_configuration {
#       forwarding_protocol = "MatchRequest"
#       backend_pool_name   = "backend-pool-west"
#     }
#   }

#   backend_pool {
#     name = "backend-pool-west"
#     backend {
#       host_header = "www.fejzic37.com"
#       address     = "www.fejzic37.com"
#       http_port   = 80
#       https_port  = 443
#     }

#     health_probe_name = "west-healthprobe"
#     load_balancing_name = "load-balancing"
#   }

#   backend_pool_health_probe {
#     name = "west-healthprobe"
#     interval_in_seconds = 30
#     path = "/index.html"
#     protocol = "Https"
#   }

# # ------------------------------------- US East 2 -------------------------------------#
#   routing_rule {
#     name               = "route-to-east"
#     accepted_protocols = ["Https"]
#     patterns_to_match  = ["/east/*"]                                    # matches all URL's
#     frontend_endpoints = ["front-endpoint"]

#     forwarding_configuration {
#       forwarding_protocol = "MatchRequest"
#       backend_pool_name   = "backend-pool-east"
#     }
#   }

#   backend_pool {
#     name = "backend-pool-east"
#     backend {
#       host_header = "www.fejzic37.com"
#       address     = "www.fejzic37.com"
#       http_port   = 80
#       https_port  = 443
#     }

#     health_probe_name = "east-healthprobe"
#     load_balancing_name = "load-balancing"
    
#   }

#   backend_pool_health_probe {
#     name = "east-healthprobe"
#     interval_in_seconds = 30
#     path = "/index.html"
#     protocol = "Https"
#   }
# # ----------- backend load balancing -----------#

#   backend_pool_load_balancing {
#     name = "load-balancing"
#     sample_size           = 4           # The number of samples to consider
#     successful_samples_required = 2      # Number of successful samples needed
#     additional_latency_milliseconds = 0
#   }

#   depends_on = [ 
#     azurerm_storage_account.SA_southcentral,  # Ensure the storage account in South Central is created first
#     azurerm_storage_account.SA_west,         # Ensure the storage account in US West is created first
#     azurerm_storage_account.SA_east,        # Ensure the storage account in US East 2 is created first
#     azurerm_resource_group.main_RG,
#     azurerm_dns_zone.dnszone,
#  ]  
# }


#  # add certificate
# resource "azurerm_frontdoor_custom_https_configuration" "excustom_https" {
#   frontend_endpoint_id              = azurerm_frontdoor.cdn.frontend_endpoints["front-endpoint"]
#   custom_https_provisioning_enabled = true

# }

# ------------------------------------- CDN Firewall -------------------------------------#


# resource "azurerm_frontdoor_firewall_policy" "example" {
#   name                              = "examplefdwafpolicy"
#   resource_group_name               = azurerm_resource_group.example.name
#   enabled                           = true
#   mode                              = "Prevention"
#   redirect_url                      = "https://www.contoso.com"
#   custom_block_response_status_code = 403
#   custom_block_response_body        = "PGh0bWw+CjxoZWFkZXI+PHRpdGxlPkhlbGxvPC90aXRsZT48L2hlYWRlcj4KPGJvZHk+CkhlbGxvIHdvcmxkCjwvYm9keT4KPC9odG1sPg=="

#   custom_rule {
#     name                           = "Rule1"
#     enabled                        = true
#     priority                       = 1
#     rate_limit_duration_in_minutes = 1
#     rate_limit_threshold           = 10
#     type                           = "MatchRule"
#     action                         = "Block"

#     match_condition {
#       match_variable     = "RemoteAddr"
#       operator           = "IPMatch"
#       negation_condition = false
#       match_values       = ["192.168.1.0/24", "10.0.0.0/24"]
#     }
#   }

#   custom_rule {
#     name                           = "Rule2"
#     enabled                        = true
#     priority                       = 2
#     rate_limit_duration_in_minutes = 1
#     rate_limit_threshold           = 10
#     type                           = "MatchRule"
#     action                         = "Block"

#     match_condition {
#       match_variable     = "RemoteAddr"
#       operator           = "IPMatch"
#       negation_condition = false
#       match_values       = ["192.168.1.0/24"]
#     }

#     match_condition {
#       match_variable     = "RequestHeader"
#       selector           = "UserAgent"
#       operator           = "Contains"
#       negation_condition = false
#       match_values       = ["windows"]
#       transforms         = ["Lowercase", "Trim"]
#     }
#   }

#   managed_rule {
#     type    = "DefaultRuleSet"
#     version = "1.0"

#     exclusion {
#       match_variable = "QueryStringArgNames"
#       operator       = "Equals"
#       selector       = "not_suspicious"
#     }

#     override {
#       rule_group_name = "PHP"

#       rule {
#         rule_id = "933100"
#         enabled = false
#         action  = "Block"
#       }
#     }

#     override {
#       rule_group_name = "SQLI"

#       exclusion {
#         match_variable = "QueryStringArgNames"
#         operator       = "Equals"
#         selector       = "really_not_suspicious"
#       }

#       rule {
#         rule_id = "942200"
#         action  = "Block"

#         exclusion {
#           match_variable = "QueryStringArgNames"
#           operator       = "Equals"
#           selector       = "innocent"
#         }
#       }
#     }
#   }

#   managed_rule {
#     type    = "Microsoft_BotManagerRuleSet"
#     version = "1.0"
#   }
  
# }
