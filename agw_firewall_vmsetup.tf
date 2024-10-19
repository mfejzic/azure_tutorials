# !! DONT RUN TOO EXPENSIVE  !! #

# this config sets up two VMs for handling images and video, each have extensions that execute powershell scripts
# images VM has 2 cores while videos has 6 for more processing power
# application gateway(agw) is configured with a static IP enabling path-based routing to the VMs based on the URL paths
# storage account and containers hold the powershell scripts in a blob based storage
# security groups allow inbound http and rdp traffic
# configured with firewall, NAT and application rule collection to manage security and traffic routing
# route table directs traffic to through the firewall 
# creates read-only management lock on VMs to prevent any changes
# the action group sends email notifications to the admin when specific events occur, like alerts related to network outage
# metric alert is used to monitor network output which tirggers notifications if a total exceeds the threshold
# activity log alert is set up to noitfy admin whenever a VM is deallocated 
# the Log Analytics Workspace collects and analyzes log data. an extension is installed on each vm to faciliate this monitoring
# add description for management lock & action group & metric/log alert - log analytics workspace $ vm extension/agent   

locals {
  function = ["videos", "images"]
}

##############################################################################################################################
#                                               resource group & vnet components                                             #
##############################################################################################################################

# create a resource group
resource "azurerm_resource_group" "RG_AGW" {
    location = var.northeurope
    name = "resourcegroup-applicationgateway"  
}

#create a virtual private network 
resource "azurerm_virtual_network" "vnet" {
  location = azurerm_resource_group.RG_AGW.location
  name = "vnet"
  resource_group_name = azurerm_resource_group.RG_AGW.name
  address_space = [ "10.0.0.0/16" ]
}

# create a singular subnet
resource "azurerm_subnet" "subnetA" {    
    name                 = "SubnetA"
    resource_group_name  = azurerm_resource_group.RG_AGW.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes     = ["10.0.0.0/24"]
    depends_on = [
      azurerm_virtual_network.vnet
    ]
}

# one block to create two interfaces using the for_each attribute
resource "azurerm_network_interface" "interface" {
  for_each = toset(local.function)
  name                = "${each.key}-interface"
  location            = azurerm_resource_group.RG_AGW.location  
  resource_group_name = azurerm_resource_group.RG_AGW.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnetA.id
    private_ip_address_allocation = "Dynamic"    
  }

  depends_on = [
    azurerm_virtual_network.vnet
  ]
}

##############################################################################################################################
#                                                  virtual machine + extension                                               #
##############################################################################################################################

# create two vms using one resource block, apply for_each and each.key to create a vm for images/videos
resource "azurerm_windows_virtual_machine" "vm" {
  for_each = toset(local.function)
  name                = "${each.key}vm"
  resource_group_name = azurerm_resource_group.RG_AGW.name                               # quota cannot pass 10 cores in this region
  location            = azurerm_resource_group.RG_AGW.location 
  size                = each.key == "videos" ? "Standard_D4s_v3" : "Standard_B2s"        # 6 cores for videos vm, 2 cores for images vm
  admin_username      = "adminuser"
  admin_password      = "Azure@123"      
    network_interface_ids = [
    azurerm_network_interface.interface[each.key].id,
  ]

  os_disk {                                                                              # configures operating system disk properties
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"                                                # sets storage type to - locally redundant storage
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"                                                # publisher of the OS image is microsoft 
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
  depends_on = [
    azurerm_virtual_network.vnet,
    azurerm_network_interface.interface
  ]
}

# one extension block will create an extension for each VM using the for_each attribute
resource "azurerm_virtual_machine_extension" "vmextension" {                             # will execute powershell script on a VM 
  for_each = toset(local.function)
  name                 = "${each.key}-extension"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm[each.key].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"                                        # this type will handle the powershell scripts for the VMs
  type_handler_version = "1.10"
  depends_on = [
    azurerm_storage_blob.IISConfig_blob
  ]                                                                                     # filesuri will point to the blobs that contain the scripts
  settings = <<SETTINGS
    {
        "fileUris": ["https://${azurerm_storage_account.storage_account.name}.blob.core.windows.net/${azurerm_storage_container.container.name}/IIS_Config_${each.key}.ps1"],
          "commandToExecute": "powershell -ExecutionPolicy Unrestricted -file IIS_Config_${each.key}.ps1"     
    }
SETTINGS

}

##############################################################################################################################
#                                             application gateway + IP + subnet                                              #
##############################################################################################################################

# create a public ip for subnet dedicated to the application gateway
resource "azurerm_public_ip" "ip_AGW" {
  name                = "application-gateway-ip"
  resource_group_name = azurerm_resource_group.RG_AGW.name
  location            = azurerm_resource_group.RG_AGW.location
  allocation_method   = "Static" 
  sku                 ="Standard"
  sku_tier            = "Regional"
}

# We need an additional subnet decicated to the application gateway
resource "azurerm_subnet" "SubnetB" {
  name                 = "subnet-AGW"
  resource_group_name  = azurerm_resource_group.RG_AGW.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"] 
}

# create an application gateway
resource "azurerm_application_gateway" "network_agw" {
  name                = "main-application-gateway"
  resource_group_name = azurerm_resource_group.RG_AGW.name
  location            = azurerm_resource_group.RG_AGW.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2                                                                    # sets the instance count to 2
  }

  gateway_ip_configuration {
    name      = "gateway-ip-configuration"
    subnet_id = azurerm_subnet.SubnetB.id                                           # mapped to subnet B
  }

  frontend_port {
    name = "front-end-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-configuration"
    public_ip_address_id = azurerm_public_ip.ip_AGW.id                              # mapped to public IP address aboce 
  }

  dynamic "backend_address_pool" {                                                  # creates 2 back end address pools based on local.functions -> images/videos
    for_each = toset(local.function)
    content {
      name = "${backend_address_pool.value}-pool"                                   # this value will be either images or videos

      ip_addresses = [ "${azurerm_network_interface.interface[backend_address_pool.value].private_ip_address}" ]      # specifies private IP address for each image/video
    }
  }

  backend_http_settings {
    name                  = "backend-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 2
  }

  http_listener {
    name                           = "gateway-listener"
    frontend_ip_configuration_name = "frontend-ip-configuration"
    frontend_port_name             = "front-end-port"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "routing-rule_a"
    rule_type                  = "PathBasedRouting"                                       # requests to /imaages/ go to its dedicated backend pool while /videos/ go to its own pool
    priority                   = 25                                                       # lower numbers indicate higher priority
    http_listener_name         = "gateway-listener"
    url_path_map_name          = "RoutingPath"
  }

url_path_map {
  name = "RoutingPath"
  default_backend_address_pool_name = "${local.function[0]}-pool"                        # sets default backend address pool if no path is specified, videos is first
  default_backend_http_settings_name = "backend-http-settings"

  dynamic "path_rule" {
    for_each = toset(local.function)                                                     # iterates a new path rule for images and videos
    content {
      name = "${path_rule.value}-RoutingRule"                                            # name of rule path is images-routingrule or videos-routingrule
      backend_address_pool_name = "${path_rule.value}-pool"
      backend_http_settings_name = "backend-http-settings"
      paths = [ "/${path_rule.value}/*" ]                                                # url pattern that will trigger path rule: ex /images/ - /videos/
      
        }
    }
  }
}


##############################################################################################################################
#                                                      security groups                                                       #
##############################################################################################################################


resource "azurerm_network_security_group" "sg" {
  name                = "sg_1"
  location            = azurerm_resource_group.RG_AGW.location
  resource_group_name = azurerm_resource_group.RG_AGW.name

  security_rule {
    name                       = "AllowRDP"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

depends_on = [
    azurerm_virtual_network.vnet
  ]
}

# associate subnetA with this security group
resource "azurerm_subnet_network_security_group_association" "sg_assoc" {  
  subnet_id                 = azurerm_subnet.subnetA.id
  network_security_group_id = azurerm_network_security_group.sg.id

  depends_on = [
    azurerm_virtual_network.vnet,
    azurerm_network_security_group.sg
  ]
}

##############################################################################################################################
#                                               storage account + container + blob                                           #
##############################################################################################################################

# create a storage account
resource "azurerm_storage_account" "storage_account" {
  name                     = "mf37"
  resource_group_name      = azurerm_resource_group.RG_AGW.name
  location                 = azurerm_resource_group.RG_AGW.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind = "StorageV2"  
  depends_on = [
    azurerm_resource_group.RG_AGW
  ]
}

# create a container 
resource "azurerm_storage_container" "container" {
  name                  = "scripts-data"
  storage_account_name  = azurerm_storage_account.storage_account.name
  container_access_type = "blob"
  depends_on=[
    azurerm_storage_account.storage_account
    ]
}

# create a blob from the two powershell scripts
resource "azurerm_storage_blob" "IISConfig_blob" {
  for_each = toset(local.function)
  name                   = "IIS_Config_${each.key}.ps1"
  storage_account_name   = azurerm_storage_account.storage_account.name
  storage_container_name = azurerm_storage_container.container.name
  type                   = "Block"
  source                 = "IIS_Config_${each.key}.ps1"
   depends_on=[azurerm_storage_container.container,
    azurerm_storage_account.storage_account]
}


##############################################################################################################################
#                                                              FIREWALL                                                      #
##############################################################################################################################

# create a public IP used for firewall
resource "azurerm_public_ip" "firewall_ip" {
  name                = "firewall-ip"
  resource_group_name = azurerm_resource_group.RG_AGW.name
  location            = azurerm_resource_group.RG_AGW.location
  allocation_method   = "Static"                                        # IP address will not change over time - Dynamic will change
  sku = "Standard"                                                      # standard supports zone redundancy
  sku_tier = "Regional"

  depends_on = [ azurerm_resource_group.RG_AGW ]
}

resource "azurerm_subnet" "firewall_subnet" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.RG_AGW.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]                                # allows 256 addresses
}

resource "azurerm_firewall" "firewall" {
  name                = "firewall"
  location            = azurerm_resource_group.RG_AGW.location
  resource_group_name = azurerm_resource_group.RG_AGW.name
  sku_name            = "AZFW_VNet"                                    # indicates its a virtual network firewall
  sku_tier            = "Standard"                                     # standard performance
  firewall_policy_id = azurerm_firewall_policy.firewall_policy.id

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.firewall_subnet.id           # links this firewall resource to its dedicated subnet
    public_ip_address_id = azurerm_public_ip.firewall_ip.id            # links firewall to public IP
    
  }
}

# firewall policy contains various rules
resource "azurerm_firewall_policy" "firewall_policy" {
  name                = "firewall_policy"
  resource_group_name = azurerm_resource_group.RG_AGW.name
  location            = azurerm_resource_group.RG_AGW.location
}

# create multiple rule collections for firewall policy
resource "azurerm_firewall_policy_rule_collection_group" "fwpolicy_rcg" {
  for_each = toset(local.function)                                          # create 2 instances based on locals images/videos
  name               = "fwpolicy-rcg"
  firewall_policy_id = azurerm_firewall_policy.firewall_policy.id
  priority           = 500

  nat_rule_collection {                            # operates at NETWORK LAYER 3 managing IP address translations
    name     = "nat_rule_collection1"
    priority = 300
    action   = "Dnat"                                                     # destination NAT(network address translation)
    rule {
        name = "allowrdp"
        protocols = [ "TCP" ]                                              # RDP uses TCP for communication - only TCP packets will be processed by this rule
        source_addresses = [ "0.0.0.0/0" ]
        destination_address = "${azurerm_public_ip.firewall_ip.ip_address}"   # uses firewall public IP as destination - external clients will connect to this IP when using RDP service
        destination_ports = [ "4000" ]                                        # the port that will receive traffic - use this port to RDP into vm and use images/video credentials
        translated_address = "${azurerm_network_interface.interface[each.key].private_ip_address}"    # when traffic arrives to the firewall public IP, will be sent to these two private IP in subnetA - allowing their VMs to handle the connections
        translated_port = "3389"                                             # the traffic being redirected to the private IPs above will be used for RDP
    }
  }

 application_rule_collection {                   # operates at APPLICATION LAYER 7 focuses on web traffic and domains
    name     = "app_rule_collection1"
    priority = 600
    action   = "Deny"
    rule {
      name = "allow-microsoft"
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses  = ["${azurerm_network_interface.interface[each.key].private_ip_address}"]   # IP addresses allowed to initiate connections
      destination_fqdns = ["www.microsoft.com"]                                                     # allows traffic to microsoft
    }
  }
}

######################################################################################################################
#                                                       ROUTE TABLE                                                  #
######################################################################################################################


resource "azurerm_route_table" "route_table" {
  name                = "route-table"
  location            = azurerm_resource_group.RG_AGW.location
  resource_group_name = azurerm_resource_group.RG_AGW.name
  bgp_route_propagation_enabled = false                          # disbales border gateway protocol - use BGP in vnets for dynamic routing

  depends_on = [ azurerm_resource_group.RG_AGW ]
}

resource "azurerm_route" "route_1" {
  name                = "acceptanceTestRoute1"
  resource_group_name = azurerm_resource_group.RG_AGW.name
  route_table_name    = azurerm_route_table.route_table.name
  address_prefix      = "0.0.0.0/0"
  next_hop_type       = "VirtualAppliance"                                                # virtal appliance is a type of network device or service thats handles routing
  next_hop_in_ip_address = azurerm_firewall.firewall.ip_configuration[0].private_ip_address

  depends_on = [ azurerm_route_table.route_table ]
}

resource "azurerm_subnet_route_table_association" "RT_assoc" {
  subnet_id      = azurerm_subnet.subnetA.id
  route_table_id = azurerm_route_table.route_table.id
}

######################################################################################################################
#                                   management lock & action group & metric/log alert                                #
######################################################################################################################

# create a lock on your VM to read only
resource "azurerm_management_lock" "resource-group-level" {                                       # go to subscription -> IAM role assignment -> assign user access management to terraform
  for_each   = toset(local.function)
  name       = "resource-group-level"
  scope      = azurerm_windows_virtual_machine.vm[each.key].id                                    # scope is the ID of your virtual machine
  lock_level = "ReadOnly"
  notes      = "no changes can be made"
}

# create action group to notify your email
resource "azurerm_monitor_action_group" "action_group" {
  name                = "CriticalAlertsAction"
  resource_group_name = azurerm_resource_group.RG_AGW.name
  short_name          = "email-alerts"

  email_receiver {
    name          = "sendtoadmin"
    email_address = "muhazic3@gmail.com"
  } 
}

# create a m
resource "azurerm_monitor_metric_alert" "networkout_alert" {
  for_each = toset(local.function)
  name                = "networkout-alert"
  resource_group_name = azurerm_resource_group.RG_AGW.name
  scopes              = [azurerm_windows_virtual_machine.vm[each.key].id]                       # targets for the alerts -> videos/images VMs
  description         = "Action will be triggered when Transactions count is greater than 50."

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"                                       # this namespace included CPU usage, I/O traffic etc
    metric_name      = "Network Out Total"                                                       # uses bytes - network out tracks ammount of data leaving the vm, in this case the VMs
    aggregation      = "Total"                                                                   # other aggregation types are minimum, maximum, average
    operator         = "GreaterThan"
    threshold        = 70
  }
  action {
    action_group_id = azurerm_monitor_action_group.action_group.id
  }

  depends_on = [ azurerm_windows_virtual_machine.vm, azurerm_monitor_action_group.action_group ]
}

resource "azurerm_monitor_activity_log_alert" "vm_operation" {
  for_each = toset(local.function)
  name                = "vm-log-alerts"
  resource_group_name = azurerm_resource_group.RG_AGW.name
  location            = azurerm_resource_group.RG_AGW.location
  scopes              = [azurerm_resource_group.RG_AGW.id]
  description         = "sends alert regarding vm deallocation"

  criteria {
    resource_id    = azurerm_windows_virtual_machine.vm[each.key].id
    operation_name = "Microsoft.Compute/virtualMachines/deallocate/action"                      # alerts whenever a VM is deallocated, stopped or released from memory
    category       = "Administrative"                                                           # admin category includes creating, modifying or deleting resources
  }

  action {
    action_group_id = azurerm_monitor_action_group.action_group.id
  }

  depends_on = [ azurerm_windows_virtual_machine.vm, azurerm_monitor_action_group.action_group ]
}


######################################################################################################################
#                                      log analytics workspace $ vm extension/agent                                  #
######################################################################################################################

resource "azurerm_log_analytics_workspace" "LAW" {
  name                = "logs-mf37"
  location            = azurerm_resource_group.RG_AGW.location
  resource_group_name = azurerm_resource_group.RG_AGW.name 
  sku                 = "PerGB2018"                                                             # SKU determines billing, data retention and available features in this workspace
  retention_in_days   = 30
}

resource "azurerm_virtual_machine_extension" "vmagent" {
  for_each = toset(local.function)
  name                 = "vmagent"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm[each.key].id
  publisher            = "Microsoft.EnterpriseCloud.Monitoring"                                # identifies the source for verifying authenticity and support
  type                 = "MicrosoftMonitoringAgent"                                            # extension type being installed, in this case monitoring
  type_handler_version = "1.0"
  
  auto_upgrade_minor_version = "true"                                                          # indicates whether minor versions of the extension should auto upgrade, ensures that the extension 
  
  # workspaceID: connects agent to the log analysts workspace, enabling data collection
  # protected settings: provides necessary credentils for the agent to authenticate with the LAW securely
  settings = <<SETTINGS
    {
      "workspaceId": "${azurerm_log_analytics_workspace.LAW.id}"                               
    } 
SETTINGS
   protected_settings = <<PROTECTED_SETTINGS
   {
      "workspaceKey": "${azurerm_log_analytics_workspace.LAW.primary_shared_key}"
   }
PROTECTED_SETTINGS

depends_on = [
  azurerm_log_analytics_workspace.LAW,
  azurerm_windows_virtual_machine.vm
]
}

resource "azurerm_log_analytics_datasource_windows_event" "system_events" {
  name                = "system-events"
  resource_group_name = azurerm_resource_group.RG_AGW.name
  workspace_name      = azurerm_log_analytics_workspace.LAW.workspace_id
  event_log_name      = "System"                                                        # specifies which log source will be monitored, captures system events for analysis
  event_types         = ["Information"]                                                 # only collects informational events from the system log
}
