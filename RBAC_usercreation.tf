# configuration focuses on governance and access control
# creates a mock user with designated principal name
# assigns built in reader role to mock user, granting read only access to resources within resource group 
# custom role is created to allow specific actions to virtual machines, which is assigned to mock user
# policy is retrived from Azure that restricts resource creation in this resource group to ONLY virtual machines - all other resources cannot be created, unless allowed


# create resource group
resource "azurerm_resource_group" "user_RG" {
  name     = "user-resource-group"
  location = var.West_US
}

# create a mock user - leave password empty
resource "azuread_user" "mock_user" {
  user_principal_name = "mockUser@muhazic3gmail.onmicrosoft.com"
  mail_nickname       = "mockuser"
  display_name        = "mockuser"
  password            = ""
}

# create reader role assignment - assign mock user
resource "azurerm_role_assignment" "reader_role" {
  scope                = azurerm_resource_group.user_RG.id
  role_definition_name = "Reader"                                           # built in azure role defintion
  principal_id         = azuread_user.mock_user.object_id

  depends_on = [ azurerm_resource_group.user_RG, azuread_user.mock_user ]
}

# create data block linking your subscription to the role definition assingable scope
data "azurerm_subscription" "subscription" {
}

# create custom role and link it to the role definition
resource "azurerm_role_assignment" "custom_role" {
  scope                = azurerm_resource_group.user_RG.id 
  role_definition_name = azurerm_role_definition.role_definition.name       # link to role definition block
  principal_id         = azuread_user.mock_user.object_id

  depends_on = [ azurerm_resource_group.user_RG, azuread_user.mock_user, azurerm_role_definition.role_definition ]
}

# link role definintion to the custom role
resource "azurerm_role_definition" "role_definition" {
  name        = "customrole-availabilitysets"
  scope       = data.azurerm_subscription.subscription.id                  # link to current subscription data block
  description = "availability sets red/write/delete"

  permissions {
    #specifies list of permissions granted by role
    actions     = ["Microsoft.Compute/*/read",                             # user can view details about these resources 
      "Microsoft.Compute/virtualMachines/start/action",                    # useful for users who need to use VMs for tasks, but cannot start or stop them
      "Microsoft.Compute/virtualMachines/restart/action" ]                 # for users that need ability to restart virtual machines for maintenance or torubleshooting
    not_actions = []
  }
  assignable_scopes = [
    data.azurerm_subscription.subscription.id
  ]
}

# !! enforce a policy that restricts resource creation in this resource group to only virtual machines
# use this block to retrieve an existing azure policy definition
data "azurerm_policy_definition" "allowed_resource_types" {
  display_name = "Allowed resource types"                                           # specifies the display name of policy definition to use - this one used to find the correct policy definition within azures predfinied policies
}

# this block assigns specified policy definition to a resource group
resource "azurerm_resource_group_policy_assignment" "policy_assignment" {
  name                 = "assign-policy"
  resource_group_id    = azurerm_resource_group.user_RG.id                         
  policy_definition_id = data.azurerm_policy_definition.allowed_resource_types.id   # refers to ID of policy definition - use ID from data block - points to the allowed resource types policy

  # specififes allowed resource types - the value means only virtual machines can be created in this resource group, all other types will be denied
  parameters = <<PARAMS
    {
      "listOfResourceTypesAllowed": {
        "value": ["microsoft.compute/virtualmachines"]
      }
    }
PARAMS
}
