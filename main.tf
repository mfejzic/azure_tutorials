# ------------------------------------- local variables -------------------------------------#
locals {
  staging_env = "staging"
  development_env = "development"
  production_env = "prodcution"

  virtual_network = {
    name = "main_network"
    address_space = "10.0.0.0/16"
  }

  // used for the "for" line on resource main storage account - will use all 3 tags in resource -  ! find way to use only 1 of your choice !
  common_tags = {
    "tier_1" = "basic"
    "tier_2" = "standard"
    "tier_3" = "advanced"
  }

  subnets = [
    {
        name = "subnet1"
        address_prefixes = "10.0.1.0/24"
    },
    {
        name = "subnet2"
        address_prefixes = "10.0.2.0/24"
    }
    ,
    {
        name = "subnet3"
        address_prefixes = "10.0.3.0/24"
    },
    {
        name = "subnet4"
        address_prefixes = "10.0.4.0/24"
    },
    {
        name = "subnet5"
        address_prefixes = "10.0.5.0/24"
    },
    {
        name = "subnet6"
        address_prefixes = "10.0.6.0/24"
    }
  ]
}


# ------------------------------------- resource group -------------------------------------#
resource "azurerm_resource_group" "main_RG" {
  name     = "main_RG"
  location = var.East_US
}


# ------------------------------------- VNET + subnets -------------------------------------#
resource "azurerm_virtual_network" "vnet" {
  name                = local.virtual_network.name
  location            = azurerm_resource_group.main_RG.location
  resource_group_name = azurerm_resource_group.main_RG.name
  address_space       = [local.virtual_network.address_space]
  //dns_servers         = ["10.0.0.4", "10.0.0.5"]

  tags = {
    environment = local.staging_env
  }

}

#              Iterating subnets     //   needs to grab the first subnets from locals.subnet or else not gonna work ! depends on locals block !
resource "azurerm_subnet" "subnet_iteration" {
  count                = var.num_of_sub_it1
  name                 = local.subnets[count.index].name
  resource_group_name  = azurerm_resource_group.main_RG.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.subnets[count.index].address_prefixes]
  
}
#   add subnets through interation and interpolation, does not need local arguement ! MOST EFFICIENT WAY TO CREATE SUBNETS !
resource "azurerm_subnet" "sub_iteration_interpolation" {
  count                = var.num_of_sub_it2
  name                 = "subnet${count.index + 7}"
  resource_group_name  = azurerm_resource_group.main_RG.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.${count.index + 7}.0/24"]
  
}
#  ! least efficient way to make subnets !
# use subnet one as a service endpoint for your vm and storage account
resource "azurerm_subnet" "subnet1" {
  name                 = local.subnets[3].name
  resource_group_name  = azurerm_resource_group.main_RG.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.subnets[3].address_prefixes]
  service_endpoints = ["Microsoft.Sql"]                                             # remote into database from virtual machine
}
resource "azurerm_subnet" "subnet2" {
  name                 = local.subnets[4].name
  resource_group_name  = azurerm_resource_group.main_RG.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.subnets[4].address_prefixes]
}
resource "azurerm_subnet" "subnet3" {
  name                 = local.subnets[5].name
  resource_group_name  = azurerm_resource_group.main_RG.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.subnets[5].address_prefixes]
  
}
#   ! bastion subnet !
resource "azurerm_subnet" "bastion_subnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.main_RG.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.11.0/24"]
  
}


# ------------------------------------- network interface -------------------------------------#
#   ! used for bastion host for learning purposes !  
resource "azurerm_network_interface" "netInterface_1" {
  name                = "network_interface_1"
  location            = azurerm_resource_group.main_RG.location
  resource_group_name = azurerm_resource_group.main_RG.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.tutorial_ip_1.id
  }

  depends_on = [ azurerm_virtual_network.vnet, azurerm_subnet.subnet1 ]
}

resource "azurerm_network_interface" "netInterface_2" {
  name                = "network_interface_2"
  location            = azurerm_resource_group.main_RG.location
  resource_group_name = azurerm_resource_group.main_RG.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet2.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.tutorial_ip_2.id
  }

  depends_on = [ azurerm_virtual_network.vnet, azurerm_subnet.subnet2 ]
}

resource "azurerm_network_interface" "netInterface_3" {
  name                = "network_interface_3"
  location            = azurerm_resource_group.main_RG.location
  resource_group_name = azurerm_resource_group.main_RG.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet3.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.tutorial_ip_3.id
  }

  depends_on = [ azurerm_virtual_network.vnet, azurerm_subnet.subnet3 ]
}

#create multiple interface using var, count and interpolation/iteration
resource "azurerm_network_interface" "netInterface_iteration" {
  count = var.num_of_vms
  name                = "network_interface_iteration${count.index}"
  location            = azurerm_resource_group.main_RG.location
  resource_group_name = azurerm_resource_group.main_RG.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.sub_iteration_interpolation[count.index].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.ip_iteration[count.index].id
  }

  depends_on = [ azurerm_virtual_network.vnet, azurerm_subnet.sub_iteration_interpolation ]
}
#    ! bastion network interface !   ! make sure virtual machines have no ip addresses !  ! dedicated interface is NOT necessary but use this one for learning purposes
# resource "azurerm_network_interface" "bastion_interface" {
#   name                = "bastion_interface"
#   location            = azurerm_resource_group.main_RG.location
#   resource_group_name = azurerm_resource_group.main_RG.name

#   ip_configuration {
#     name                          = "internal"
#     subnet_id                     = azurerm_subnet.bastion_subnet.id
#     private_ip_address_allocation = "Dynamic"
#     //public_ip_address_id = azurerm_public_ip.bastion_ip.id
#   }

# }


# ------------------------------------- public IPs -------------------------------------#
resource "azurerm_public_ip" "tutorial_ip_1" {
  name                = "acceptanceTestPublicIp1"
  resource_group_name = azurerm_resource_group.main_RG.name
  location            = azurerm_resource_group.main_RG.location
  allocation_method   = "Static"
  sku = "Standard"
  //zones = [ "${count.index}" ]

  tags = {
    environment = local.staging_env
  }

  depends_on = [ azurerm_resource_group.main_RG ]
}

resource "azurerm_public_ip" "tutorial_ip_2" {
  name                = "acceptanceTestPublicIp2"
  resource_group_name = azurerm_resource_group.main_RG.name
  location            = azurerm_resource_group.main_RG.location
  allocation_method   = "Static"
  sku = "Standard"

  tags = {
    environment = local.staging_env
  }

  depends_on = [ azurerm_resource_group.main_RG ]
}

resource "azurerm_public_ip" "tutorial_ip_3" {
  name                = "acceptanceTestPublicIp3"
  resource_group_name = azurerm_resource_group.main_RG.name
  location            = azurerm_resource_group.main_RG.location
  allocation_method   = "Static"
  sku = "Standard"

  tags = {
    environment = local.staging_env
  }

  depends_on = [ azurerm_resource_group.main_RG ]
}

resource "azurerm_public_ip" "ip_iteration" {
  count = var.num_of_vms
  name                = "acceptanceTestPublicIp${4 + count.index}"
  resource_group_name = azurerm_resource_group.main_RG.name
  location            = azurerm_resource_group.main_RG.location
  allocation_method   = "Static"
  sku = "Standard"

  tags = {
    environment = local.staging_env
  }

  depends_on = [ azurerm_resource_group.main_RG ]
}

resource "azurerm_public_ip" "bastion_ip" {
  name                = "bastion_IP"
  resource_group_name = azurerm_resource_group.main_RG.name
  location            = azurerm_resource_group.main_RG.location
  allocation_method   = "Static"
  sku = "Standard"

  tags = {
    environment = local.staging_env
  }
}

# ------------------------------------- availability sets -------------------------------------#
#   makes sure your VMs are resiient to hardware failure and maintenance by distributing the VMs across different physical resources in a data center
#   keeps applications running smooth in case of failure
#   mutually exclusive with availability zones
resource "azurerm_availability_set" "AS_count" {
  name                = "AS_count"
  location            = azurerm_resource_group.main_RG.location
  resource_group_name = azurerm_resource_group.main_RG.name
  platform_fault_domain_count = 3 # VMs are divided into 3 groups, updating one group at a time
  platform_update_domain_count = 3 # VMs are spread across 3 different sets of physical hardware, if one fails the other 2 are operational

  tags = {
    environment = local.staging_env
  }
}

# ------------------------------------- bastion host -------------------------------------#
# comment out when not using, takes to long to provision
# resource "azurerm_bastion_host" "bastion" {
#   name                = "bastion_host"
#   location            = azurerm_resource_group.main_RG.location
#   resource_group_name = azurerm_resource_group.main_RG.name

#   ip_configuration {
#     name                 = "configuration"
#     subnet_id            = azurerm_subnet.bastion_subnet.id
#     public_ip_address_id = azurerm_public_ip.bastion_ip.id
#   }
# }

# ------------------------------------- virtual machines -------------------------------------#
// find a way to SSH into windows VMs
resource "azurerm_windows_virtual_machine" "vm" {
  name                = "vm"
  resource_group_name = azurerm_resource_group.main_RG.name
  location            = azurerm_resource_group.main_RG.location
  size                = "Standard_B2s"
  admin_username      = azurerm_key_vault_secret.KV_secret.name
  admin_password      = azurerm_key_vault_secret.KV_secret.value
  //zone = "3"

  network_interface_ids = [
    azurerm_network_interface.netInterface_1.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # source_image_reference {
  #   publisher = "MicrosoftWindowsServer"
  #   offer     = "WindowsServer"
  #   sku       = "2016-Datacenter"
  #   version   = "latest"
  # }

    source_image_reference {
    publisher = "MicrosoftSQLServer" #used to be Canonical
    offer     = "sql2019-ws2019"
    sku       = "sqldev"
    version   = "15.0.220510"
  }

  depends_on = [ azurerm_network_interface.netInterface_1, azurerm_resource_group.main_RG, azurerm_key_vault_secret.KV_secret, azurerm_key_vault.KV]
}

data "template_file" "cloudinit_linux_script" {
  template = file("linux_script.sh")
}
resource "azurerm_linux_virtual_machine" "linux_vm" { 
  name                = "linuxvm"
  resource_group_name = azurerm_resource_group.main_RG.name
  location            = azurerm_resource_group.main_RG.location
  size                = "Standard_B1s"
  admin_username      = "linuxuser"
  custom_data = base64encode(data.template_file.cloudinit_linux_script.rendered)

  network_interface_ids = [
    azurerm_network_interface.netInterface_3.id
  ]
// use remote-exec -> inline block to manually write out commands - do this if certain commands are not supported in cloud-init
  # provisioner "file" { // bootstrap default.html page in the server during its creation
  #   source = "default.html"
  #   destination = "var/www/html/default.html"

  #   connection { //use terminal to ssh into server <  ssh -i linuxkey.pem linuxuser@ipaddress  > get the ipaddress after vm creation - enter ip address in browser and backslash to find html page
  #     type = "ssh"
  #     user = "linuxuser"
  #     private_key = file("${local_file.linuxpemkey.filename}") // wont fetch pem key before its created - grab it dynamically using interpolation 
  #     host = "${azurerm_public_ip.tutorial_ip_3.ip_address}"

  #   }
    
  # }

  admin_ssh_key {
    username   = "linuxuser"
    public_key = tls_private_key.linuxkey.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  depends_on = [ azurerm_network_interface.netInterface_3,azurerm_resource_group.main_RG, tls_private_key.linuxkey ]
}

#   create mulitple VMs usnig var, count and interpolation
# resource "azurerm_windows_virtual_machine" "vm_count" {
#   count = var.num_of_vms
#   name                = "countVM${count.index}"
#   resource_group_name = azurerm_resource_group.main_RG.name
#   location            = azurerm_resource_group.main_RG.location
#   size                = "Standard_B1s"
#   admin_username      = "adminuser"
#   admin_password      = azurerm_key_vault_secret.KV_secret.value
#   availability_set_id = azurerm_availability_set.AS_count.id
  
#   network_interface_ids = [
#     azurerm_network_interface.netInterface_iteration[count.index].id
#   ]

#   os_disk {
#     caching              = "ReadWrite"
#     storage_account_type = "Standard_LRS"
#   }

#   source_image_reference {
#     publisher = "MicrosoftWindowsServer"
#     offer     = "WindowsServer"
#     sku       = "2016-Datacenter"
#     version   = "latest"
#   }

#   depends_on = [ azurerm_network_interface.netInterface_iteration, azurerm_resource_group.main_RG, azurerm_key_vault_secret.KV_secret, azurerm_key_vault.KV ]
# }

# ------------------------------------- virtual machine extension -------------------------------------#
# resource "azurerm_virtual_machine_extension" "vmextension" {
#   name                 = "vmextension"
#   virtual_machine_id   = azurerm_windows_virtual_machine.vm.id
#   publisher            = "Microsoft.Compute"
#   type                 = "CustomScriptExtension"
#   type_handler_version = "1.10"

#   settings = <<SETTINGS
#     {
#         "fileUris": ["https://${azurerm_storage_account.main_SA.name}.blob.core.windows.net/data/IIS_Config.ps1"],
#           "commandToExecute": "powershell -ExecutionPolicy Unrestricted -file IIS_Config.ps1"     
#     }
# SETTINGS


# }

# ------------------------------------- disks -------------------------------------#
# resource "azurerm_managed_disk" "disk_1" {
#   name                 = "disk_1"
#   location             = azurerm_resource_group.main_RG.location
#   resource_group_name  = azurerm_resource_group.main_RG.name
#   storage_account_type = "Standard_LRS"
#   create_option        = "Empty"
#   disk_size_gb         = "4"
#   //zone = "3"

#   tags = {
#     environment = local.staging_env
#   }
# }

# resource "azurerm_virtual_machine_data_disk_attachment" "disk_attachment_1" {
#   managed_disk_id    = azurerm_managed_disk.disk_1.id
#   virtual_machine_id = azurerm_windows_virtual_machine.vm.id
#   lun                = "0"
#   caching            = "ReadWrite"
# }

# ------------------------------------- private key for linux vm -------------------------------------#
resource "tls_private_key" "linuxkey" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "local_file" "linuxpemkey" {
  filename = "linuxkey.pem"
  content = tls_private_key.linuxkey.private_key_pem

  depends_on = [ tls_private_key.linuxkey ]
}

# ------------------------------------- security groups -------------------------------------#
// implement dynamic blocks to consolidate the security rules - 4 security rules, use dynamic block to have 1 rule
resource "azurerm_network_security_group" "sg_1" {
  name                = "sg"
  location            = azurerm_resource_group.main_RG.location
  resource_group_name = azurerm_resource_group.main_RG.name

  security_rule {
    name                       = "tutorial_sg_in"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "3389"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    
  }
  security_rule  {
    name                       = "tutorial_sg_out"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "3389"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-SSH"
     priority                    = 1000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix      = "0.0.0.0/0"
  destination_address_prefix   = "*"
  }
   security_rule {
  name                       = "Allow-1433"
  priority                    = 400
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "1433"
  source_address_prefix      = "0.0.0.0/0"
  destination_address_prefix   = "*"
  }

  tags = {
    environment = local.staging_env
  }

  depends_on = [ azurerm_resource_group.main_RG ]
}

resource "azurerm_network_security_group" "sg_2" {
  name                = "SSH_sg"
  location            = azurerm_resource_group.main_RG.location
  resource_group_name = azurerm_resource_group.main_RG.name


  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  

  tags = {
    environment = local.staging_env
  }
}

# ------------------------------------- SG subnet association -------------------------------------#
resource "azurerm_subnet_network_security_group_association" "subnet1" {
  subnet_id                 = azurerm_subnet.subnet1.id
  network_security_group_id = azurerm_network_security_group.sg_1.id
}
resource "azurerm_subnet_network_security_group_association" "subnet2" {
  subnet_id                 = azurerm_subnet.subnet2.id
  network_security_group_id = azurerm_network_security_group.sg_1.id
}
resource "azurerm_subnet_network_security_group_association" "subnet3" {
  subnet_id                 = azurerm_subnet.subnet3.id
  network_security_group_id = azurerm_network_security_group.sg_1.id
}
# associate iterated/interpolated subnets / depends on count argument
# resource "azurerm_subnet_network_security_group_association" "sub_interpolated_iterated_association" {
#   count = var.num_of_sub_it2
#   subnet_id                 = azurerm_subnet.sub_iteration_interpolation[count.index].id
#   network_security_group_id = azurerm_network_security_group.sg_1.id
# }

# assign subnet 3 to security group 1 and the rest to security group 2(ssh) / use ternary operators
resource "azurerm_subnet_network_security_group_association" "sub_interpolated_iterated_association" {
  count = var.num_of_sub_it2

  subnet_id = azurerm_subnet.sub_iteration_interpolation[count.index].id

  network_security_group_id = count.index == 0 ? azurerm_network_security_group.sg_1.id : azurerm_network_security_group.sg_2.id 
}

# ------------------------------------- SG interface association -------------------------------------#
resource "azurerm_network_interface_security_group_association" "NI_SG_association" {
  network_interface_id      = azurerm_network_interface.netInterface_1.id
  network_security_group_id = azurerm_network_security_group.sg_1.id
}

# ------------------------------------- key vaults -------------------------------------#
data "azurerm_client_config" "current" {} // fethces the tenant and object ID from providers

# used for main virtual machine
resource "azurerm_key_vault" "KV" {
  name                        = "KV-mf37"
  location                    = azurerm_resource_group.main_RG.location
  resource_group_name         = azurerm_resource_group.main_RG.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "Set", "Delete"
    ]

    key_permissions = [
      "Get", "Create", "Delete", "Update", "Import"
    ]

    certificate_permissions = [
      "Get", "Create", "Delete", "Update"
    ]
  }
}

resource "azurerm_key_vault_secret" "KV_secret" {
  name         = "adminuser"
  value        = "P@$$w0rd1234!"
  key_vault_id = azurerm_key_vault.KV.id
}

#  use data source to pull key vault from azure portal
# data "azurerm_key_vault" "KV_VMcount" {
#   name                = "KV-vmcount-mf37"
#   resource_group_name = azurerm_resource_group.main_RG.name
# }

# data "azurerm_key_vault_secret" "KV_VMcount_secret" {
#   name         = "vmpassword"
#   key_vault_id = data.azurerm_key_vault.KV_VMcount.id
# }

# ------------------------------------- storage account service endpoint -------------------------------------#

# resource "azurerm_subnet_service_endpoint_storage_policy" "service_endpoint_main_SA" {
#   name                = "example-policy"
#   resource_group_name = azurerm_resource_group.main_RG.name
#   location            = azurerm_resource_group.main_RG.location
#   definition {
#     name        = "SE_1"
#     description = "definition1"
#     service     = "Microsoft.Storage"
#     service_resources = [
#       azurerm_resource_group.main_RG.id,
#       azurerm_storage_account.main_SA.id
#     ]
#   }
#   definition {
#     name        = "name2"
#     description = "definition2"
#     service     = "Global"
#     service_resources = [
#       "/services/Azure",
#       "/services/Azure/Batch",
#       "/services/Azure/DataFactory",
#       "/services/Azure/MachineLearning",
#       "/services/Azure/ManagedInstance",
#       "/services/Azure/WebPI",
#     ]
#   }
# }

# ------------------------------------- storage account -> container -> blob -------------------------------------#
# resource "azurerm_storage_account" "main_SA" {
#   name                     = join("mf37", ["${var.storage_account_name}", substr(random_uuid.SA_identifier.result,0,8)])
#   resource_group_name      = azurerm_resource_group.main_RG.name
#   location                 = azurerm_resource_group.main_RG.location
#   account_tier             = "Standard"
#   account_replication_type = "LRS"
#   account_kind = "StorageV2"

#   # network_rules {
#   #   default_action             = "Allow"
#   #   ip_rules                   = ["208.73.135.244"]  // you can use a virtual machines ip address; only machine to access this SA
#   #   //virtual_network_subnet_ids = [azurerm_subnet.subnet1.id]
#   # }

#   is_hns_enabled = true // enable hierarchical namespace

#   tags = {
#     for name, value in local.common_tags : name=> "${value}"
#   }
# }

# resource "azurerm_storage_container" "main_container" {
#   name                  = "data"
#   storage_account_name  = azurerm_storage_account.main_SA.name
#   container_access_type = "blob"
# }

# resource "azurerm_storage_blob" "main_blob" {
#   for_each = {
#     sample1 = "C:\\sample_blobs\\sample1.txt"
#     sample2 = "C:\\sample_blobs\\sample2.txt"
#     sample3 = "C:\\sample_blobs\\sample3.txt"
#   }
#   name                   = "${each.key}.txt"
#   storage_account_name   = azurerm_storage_account.main_SA.name
#   storage_container_name = azurerm_storage_container.main_container.name
#   type                   = "Block"
#   source                 = each.value

#   depends_on = [ azurerm_storage_container.main_container]
# }
#                          count/iteration storage accounts, containers and blobs
resource "azurerm_storage_account" "SA_count" {
  count = 3
  name                     = "mf37${count.index}"
  resource_group_name      = azurerm_resource_group.main_RG.name
  location                 = azurerm_resource_group.main_RG.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind = "StorageV2"

  tags = {
    environment = local.staging_env
  }
}
resource "azurerm_storage_container" "container_count" {
  count = 3
  name                  = "data${count.index}" // creates 3 containers, names them data0, daa1, data2 by iteration
  storage_account_name  = azurerm_storage_account.SA_count[count.index].name
  container_access_type = "blob"
}
# resource "azurerm_storage_blob" "blob_count" {
#   name                   = "main.tf"
#   storage_account_name   = azurerm_storage_account.main_SA.name
#   storage_container_name = azurerm_storage_container.container_count.name
#   type                   = "Block"
#   source                 = "main.tf"

#   depends_on = [ azurerm_storage_container.container_count]
# }

 #                     for each/to set sotrage accounts, containers and blobs                                
resource "azurerm_storage_account" "SA_toset" {
  name                     = "tosetmf37"
  resource_group_name      = azurerm_resource_group.main_RG.name
  location                 = azurerm_resource_group.main_RG.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind = "StorageV2"

  tags = {
    environment = local.staging_env
  }
}
resource "azurerm_storage_container" "container_toset" {
  for_each = toset(["data", "files", "documents"]) // creates 3 containers, names them respectively
  name                  = each.key
  storage_account_name  = azurerm_storage_account.SA_toset.name
  container_access_type = "blob"
}
# resource "azurerm_storage_blob" "blob_toset" {
#   name                   = "main.tf"
#   storage_account_name   = azurerm_storage_account.main_SA.name
#   storage_container_name = azurerm_storage_container.container_toset.name
#   type                   = "Block"
#   source                 = "main.tf"

#   depends_on = [ azurerm_storage_container.container_toset]
# }

 #                     combine them / count 3 SA's and create multiple(3) containers in each                             
resource "azurerm_storage_account" "SA_combo" {
  count = 3
  name                     = "combomf37${count.index}"
  resource_group_name      = azurerm_resource_group.main_RG.name
  location                 = azurerm_resource_group.main_RG.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind = "StorageV2"

  tags = {
    environment = local.staging_env
  }
}
resource "azurerm_storage_container" "container_combo" {
  count = 9
  name                  = element(["files", "docs", "data"], count.index % 3)
  storage_account_name  = azurerm_storage_account.SA_combo[floor(count.index / 3)].name    # Using floor Function: floor(count.index / 3) to ensure that the index used for the SA_combo is an integer.
  container_access_type = "blob"
}


#   ! storage blob for script extension !
# resource "azurerm_storage_blob" "IISConfig" {
#   name                   = "IIS_Config.ps1"
#   storage_account_name   = "mf37"
#   storage_container_name = "data"
#   type                   = "Block"
#   source                 = "IIS_Config.ps1"
#    //depends_on=[azurerm_storage_container.data]
# }

# ------------------------------------- IAM permissions -------------------------------------#
   // fix these iam permissions so that terraform can make all necessary changes 
# resource "azurerm_role_assignment" "storage_blob_data_owner" {
#   principal_id        = "3806ad50-41aa-4ad0-b6d2-5f75a3882d18"  # Replace with the actual principal ID
#   role_definition_name = "Storage Blob Data Owner"
#   scope                = azurerm_storage_account.main_SA.id  # The ID of your storage account
# }

# ------------------------------------- random number generators -------------------------------------#

# resource "random_uuid" "SA_identifier" {
  
# }

# # output "SAI_output" {
# #   value = substr(random_uuid.SA_identifier.result,0,8)
# # }
# variable "storage_account_name" {
#   type = string
#   description = "prefix of storage account name"
# }

# ------------------------------------- web app service -------------------------------------# ! comment out foreach VMs for more to prevent quota limit !

// you can integrate web app to github
resource "azurerm_service_plan" "company_plan" {
  name                = "company_plan"
  resource_group_name = azurerm_resource_group.main_RG.name
  location            = "eastus2"
  os_type             = "Windows"
  sku_name            = "S1" # b1-b3 is basic - s1-s3 is standard - use standard or higher to use deployement slots
}
#create service plan before app
resource "azurerm_windows_web_app" "windows_web_app1" {
  name                = "mf37webapp1"
  resource_group_name = azurerm_resource_group.main_RG.name
  location            = "eastus2"
  service_plan_id     = azurerm_service_plan.company_plan.id

  #change settings without redeploying your code
  # powerful feature that allows for dynamic configuration of your apps
  app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY" =azurerm_application_insights.application_insights.instrumentation_key      # sends telemtry data like requests, exceptions to application insights
   "APPLICATIONINSIGHTS_CONNECTION_STRING"=azurerm_application_insights.application_insights.connection_string   # connection strong for app insights
  }

# activate logs
  logs {
    detailed_error_messages = true
    http_logs {
      azure_blob_storage {
        retention_in_days = 7
        sas_url = "https://${azurerm_storage_account.web_app_logging.name}.blob.core.windows.net/${azurerm_storage_container.SAS_container.name}${data.azurerm_storage_account_blob_container_sas.data_container_SAS.sas}"
      }
    }
  }

# ip restriction must go in the site_config block
  site_config {
    application_stack {
      current_stack = "dotnet"
      dotnet_version = "v6.0"
    }
# restrict/allow IPs
    ip_restriction {
      action = "Allow"
      ip_address = "0.0.0.0/0"
      name = "deny_all_traffic"
      priority = 100
    }
  }
  connection_string {                                                                                               # connect web app to database
    name = "SQLConnection"
    type = "SQLAzure"
    value = "Data Source=tcp: ${azurerm_mssql_server.mssql_server_1.fully_qualified_domain_name},1433; Initial Catalog=${azurerm_mssql_database.mssql_database.name}; User Id=${azurerm_mssql_server.mssql_server_1.administrator_login}; Password'${azurerm_mssql_server.mssql_server_1.administrator_login_password}';"
  }
}

# resource "azurerm_app_service_source_control" "source_co" {
#   app_id   = azurerm_linux_web_app.windows_web_app1.id
#   repo_url = "https://github.com/Azure-Samples/python-docs-hello-world"
#   branch   = "master"
# }

# ------------------------------------- web app logging ------------------------------------- #

resource "azurerm_storage_account" "web_app_logging" {
  name                     = "mf37webapplogging"
  resource_group_name      = azurerm_resource_group.main_RG.name
  location                 = "eastus2"
  account_tier             = "Standard"
  account_replication_type = "GRS"

  tags = {
    environment = local.staging_env
  }
}

resource "azurerm_storage_container" "SAS_container" {
  name                  = "logs"
  storage_account_name  = azurerm_storage_account.web_app_logging.name
  container_access_type = "private"
}

# use shared access signatrue or SAS token for exisitng container
# SAS tokens allow access control to various aspects of containers
data "azurerm_storage_account_blob_container_sas" "data_container_SAS" {
  connection_string = azurerm_storage_account.web_app_logging.primary_connection_string       # used to access storage account
  container_name    = azurerm_storage_container.SAS_container.name
  https_only        = true                                                                    #when true, ensures SAS token can only be used over HTTPS - prevetns token being used from unsecured connections

  ip_address = "168.1.5.65"                                                                   #restricts use of SAS token to this specified ip address

  start  = "2024-10-4"                                                                        #start time for tokens validity
  expiry = "2024-10-31"                                                                       #end time for tokens validity

  permissions {                                                                               #defines permissions granted by the SAS token
    read   = true
    add    = true
    create = true
    write  = true
    delete = true
    list   = true
  }

  cache_control       = "max-age=5"                                                          #means content can be cached for 5 seconds
  content_disposition = "inline"                                                             #how content should be displayed INLINE OR ATTACHMENT - inline should display in browser if possible
  content_encoding    = "deflate"                                                            # deflate means content is compressed using the deflate algorithm
  content_language    = "en-US"
  content_type        = "application/json"                                                   # blobs are in json files
}

output "sas_url_query_string" {
  value = data.azurerm_storage_account_blob_container_sas.data_container_SAS.sas
  sensitive = true                                                                          # marks output as sensitive - will not display in plain text
}
#deployement slot - staging, produciton, developement - each has its own URL
resource "azurerm_windows_web_app_slot" "DP_staging" {
  name           = "slot1"
  app_service_id = azurerm_windows_web_app.windows_web_app1.id

  site_config {                                                                             # configures site settings for deployment slot
    application_stack {
      current_stack = "dotnet"                                                              # uses .net as framework
      dotnet_version = "v6.0"
    }
  }
}

resource "azurerm_web_app_active_slot" "active_slot" {
  slot_id = azurerm_windows_web_app_slot.DP_staging.id

}

# ------------------------------------- log analytics & application insights for web app-------------------------------------#

#before enabling application insights, you must have log analystics workspace in place
resource "azurerm_log_analytics_workspace" "log_analytics_workspace_webapp" {
  name                = "analytics-webapp"
  location            = "eastus2"
  resource_group_name = azurerm_resource_group.main_RG.name
  sku                 = "PerGB2018"                                # defines pricing tier - perGB2018 means you pay for the data ingested
  retention_in_days   = 30                                         # specifies how lojng data will be retained
}

resource "azurerm_application_insights" "application_insights" {
  name                = "tf-test-appinsights"
  location            = "eastus2"
  resource_group_name = azurerm_resource_group.main_RG.name
  application_type    = "web"                                      # indicates type of application being monitored
  workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_webapp.id

  depends_on = [ azurerm_log_analytics_workspace.log_analytics_workspace_webapp ]
}

# ------------------------------------- sql database and server -------------------------------------#
# create a sql server in order to create a database
resource "azurerm_mssql_server" "mssql_server_1" {
  name                         = "mf37-sqlserver"
  resource_group_name          = azurerm_resource_group.main_RG.name
  location                     = "eastus"
  version                      = "12.0"
  administrator_login          = "missadministradminator"
  administrator_login_password = "Azure@3456"
  //minimum_tls_version          = "1.2"

  tags = {
    environment =  local.staging_env
  }
}

# connect database on main vm
resource "azurerm_mssql_database" "mssql_database" {
  name         = "mssql_database"
  server_id    = azurerm_mssql_server.mssql_server_1.id
  collation    = "SQL_Latin1_General_CP1_CI_AS"   #specifies collation of DV, affects how string comparison is performed
  license_type = "LicenseIncluded"                #specifies how sql server license is handled, LicenseIncluded mean the cost is included in azure sql database pricing
  max_size_gb  = 2
  sku_name     = "S0"                             #defines pricing tier
  enclave_type = "VBS"                            #database will use virtualization based SECURITY

  tags = {
    environment = local.staging_env
  }

  # prevent the possibility of accidental data loss
  # lifecycle {
  #   prevent_destroy = true
  # }

  lifecycle {                                                          # specifies certain attributes terraform should ignore during updates or refreshes - if license type of database changes, terraform will not update or recreate the database
    ignore_changes = [ license_type ]
  }

  depends_on = [ azurerm_mssql_server.mssql_server_1 ]
}
#firewall for mssql_database
resource "azurerm_mssql_firewall_rule" "mssql_firewall_rule1" {
  name             = "FirewallRule1"
  server_id        = azurerm_mssql_server.mssql_server_1.id
  start_ip_address = "4.34.67.180"
  end_ip_address   = "4.34.67.180"
}

# 
resource "azurerm_mssql_virtual_network_rule" "mssql_vnet_rule1" {
  name      = "sql-vnet-rule"
  server_id = azurerm_mssql_server.mssql_server_1.id
  subnet_id = azurerm_subnet.subnet1.id
}

# ------------------------------------- log analytics for sql database -------------------------------------#

# ! diagnostics = collecting data ---> log analysis = analyzing data !
#create ACR log and workspace -> enable auditing policy for the ACR SQL DB -> enable the diagnostic setting of the SQL DB so it can send data into the log and workspace
resource "azurerm_log_analytics_workspace" "log_analytics_workspace_sqldb" {                                   # collects performance data from resources - this one is collecting data from the sql DB
  name                = "acctest-01"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.main_RG.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_mssql_database_extended_auditing_policy" "auditing_poilcy_sqldb" {
  database_id                             = azurerm_mssql_database.mssql_database.id
  log_monitoring_enabled = true                                                                                  # sends logs and metrics to log analystics
  # storage_endpoint                        = azurerm_storage_account.example.primary_blob_endpoint              # points to which blob you want to store the audit logs in
  # storage_account_access_key              = azurerm_storage_account.example.primary_access_key                 # authenticates access to storage account
  # storage_account_access_key_is_secondary = false
  #retention_in_days                       = 6
}

resource "azurerm_monitor_diagnostic_setting" "diagnostic_sqldb" {                                               # collection of detailed metrics - you can send this data to storage accounts, log analysis, event hubs, etc
  name               = "monitor-diagnostic-settings"
  target_resource_id = azurerm_mssql_database.mssql_database.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_sqldb.id

  enabled_log {                                                                                                  # specify which log you want to capture                                                                      
    category = "SQLSecurityAuditEvents"                                                                          # captures security related events - user access, permissions change, data access, failed logins
  }

  metric {
    category = "AllMetrics"                                                                                      # all available performance metrics will be collected
  }
}

# ------------------------------------- insert data in database -------------------------------------#

# resource "null_resource" "database_setup" {
#   provisioner "local-exec" {
#     command = "sqlcmd -S ${azurerm_mssql_server.mssql_server_1.fully_qualified_domain_name} -U ${azurerm_mssql_server.mssql_server_1.administrator_login} -P ${azurerm_mssql_server.mssql_server_1.administrator_login_password} -d mssql_database -i 01.sql"
#   }
# }

# resource "null_resource" "database_setup" {
#   provisioner "local-exec" {
#     command = <<EOT
#   sqlcmd 
#   -S ${azurerm_mssql_server.mssql_server_1.fully_qualified_domain_name} 
#   -U ${azurerm_mssql_server.mssql_server_1.administrator_login} 
#   -P ${azurerm_mssql_server.mssql_server_1.administrator_login_password} 
#   -d ${azurerm_mssql_database.mssql_database.name}
#   -i 01.sql
# EOT
#   }
# }

# ------------------------------------- build SQL server virtual machine -------------------------------------#
# I chose the main VM to run the server database - use this block to provision the VM to run microsoft SQL server
#  !  register < Microsoft.SqlVirtualMachine > in subscriptios -> resource providers before using this block  !
#  !  allow traffic on port 1433 - add to your security group  !
resource "azurerm_mssql_virtual_machine" "sql_vm1" {
  virtual_machine_id               = azurerm_windows_virtual_machine.vm.id
  sql_license_type                 = "PAYG"
  sql_connectivity_port = 1433
  sql_connectivity_type = "PUBLIC"
  sql_connectivity_update_password = "Azure@345"
  sql_connectivity_update_username = "sqladmin"
}

# ------------------------------------- add data to the SQL VM -------------------------------------#   !  scripts.ps1 contains a command to run 01.sql  !
# create two blobs under the same container and storage account
#   # blob1 will contain the scripts.ps1 file, blob2 will contain the 01.SQL file

resource "azurerm_storage_account" "commands_SA" {
  name                     = "mf37commands"
  resource_group_name      = azurerm_resource_group.main_RG.name
  location                 = "eastus2"
  account_tier             = "Standard"
  account_replication_type = "GRS"

  tags = {
    environment = local.staging_env
  }
}

resource "azurerm_storage_container" "scripts_sql_container" {
  name                  = "database-commands"
  storage_account_name  = azurerm_storage_account.commands_SA.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "scripts_blob" {
  name                   = "scripts.ps1"
  storage_account_name   = "mf37commands"
  storage_container_name = "database-commands"
  type                   = "Block"
  source                 = "scripts.ps1"
}
resource "azurerm_storage_blob" "sql_blob" {
  name                   = "01.sql"
  storage_account_name   = "mf37commands"
  storage_container_name = "database-commands"
  type                   = "Block"
  source                 = "01.sql"
}

resource "azurerm_virtual_machine_extension" "sqlvmextension" {
  name                 = "sqlvmextension"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
    {
        "fileUris": ["https://${azurerm_storage_account.commands_SA.name}.blob.core.windows.net/database-commands/scripts.ps1"],
          "commandToExecute": "powershell -ExecutionPolicy Unrestricted -file scripts.ps1"     
    }
SETTINGS
}



############################################################################################################################
#                                              load balancing infrastructure                                               #
############################################################################################################################
#  !  new virtual network architecture for load balaning !

# resource "azurerm_virtual_network" "vnet_lb" {
#   name                = local.virtual_network.name
#   location            = var.West_US 
#   resource_group_name = azurerm_resource_group.main_RG.name
#   address_space       = [local.virtual_network.address_space]
# } 


# resource "azurerm_subnet" "subnet_lb_1" {    
#     name                 = "subnet_lb_1"
#     resource_group_name  = azurerm_resource_group.main_RG.name
#     virtual_network_name = azurerm_virtual_network.vnet_lb.name
#     address_prefixes     = ["10.0.0.0/24"]
#     depends_on = [
#       azurerm_virtual_network.appnetwork
#     ]
# }

# resource "azurerm_network_security_group" "appnsg" {
#   name                = "LB-app-nsg"
#   location            = var.West_US
#   resource_group_name = azurerm_resource_group.main_RG.name

#   security_rule {
#     name                       = "AllowRDP"
#     priority                   = 300
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                   = "Tcp"
#     source_port_range          = "*"
#     destination_port_range     = "3389"
#     source_address_prefix      = "*"
#     destination_address_prefix = "*"
#   }

#   security_rule {
#     name                       = "AllowHTTP"
#     priority                   = 400
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                   = "Tcp"
#     source_port_range          = "*"
#     destination_port_range     = "80"
#     source_address_prefix      = "*"
#     destination_address_prefix = "*"
#   }

# depends_on = [
#     azurerm_virtual_network.appnetwork
#   ]
# }

# resource "azurerm_subnet_network_security_group_association" "assoc_vnet_lb" {  
#   subnet_id                 = azurerm_subnet.subnet_lb_1.id
#   network_security_group_id = azurerm_network_security_group.appnsg.id

#   depends_on = [
#     azurerm_virtual_network.appnetwork,
#   ]
# }

# resource "azurerm_network_interface" "lb_interface" {
#   count=  var.number_of_machines
#   name                = "lb-interface${count.index}"
#   location            = var.West_US
#   resource_group_name = azurerm_resource_group.main_RG.name

#   ip_configuration {
#     name                          = "internal"
#     subnet_id                     = azurerm_subnet.subnet_lb_1.id
#     private_ip_address_allocation = "Dynamic"    
#   }

#   depends_on = [
#     azurerm_virtual_network.appnetwork
#   ]
# }


# resource "azurerm_windows_virtual_machine" "appvm" {
#   count=  var.number_of_machines
#   name                = "LBvm${count.index}"
#   resource_group_name = azurerm_resource_group.main_RG.name
#   location            = var.West_US
#   size                = "Standard_D2s_v3"
#   admin_username      = "adminuser"
#   admin_password      = "Azure@123"  
#     availability_set_id = azurerm_availability_set.appset.id
#     network_interface_ids = [
#     azurerm_network_interface.appinterface[count.index].id,
#   ]

#   os_disk {
#     caching              = "ReadWrite"
#     storage_account_type = "Standard_LRS"
#   }

#   source_image_reference {
#     publisher = "MicrosoftWindowsServer"
#     offer     = "WindowsServer"
#     sku       = "2019-Datacenter"
#     version   = "latest"
#   }
#   depends_on = [
#     azurerm_virtual_network.appnetwork,
#     azurerm_network_interface.appinterface,
#         azurerm_availability_set.appset
#   ]
# }

# resource "azurerm_availability_set" "appset" {
#   name                = "app-set"
#   location            = var.West_US
#   resource_group_name = azurerm_resource_group.main_RG.name
#   platform_fault_domain_count = 3
#   platform_update_domain_count = 3  
#   depends_on = [
#     azurerm_resource_group.appgrp
#   ]
# }


