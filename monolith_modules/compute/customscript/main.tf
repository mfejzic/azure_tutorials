resource "azurerm_virtual_machine_extension" "vmextension" {
  name                 = var.extension_name
  virtual_machine_id   = var.virtual_machine_id
  publisher            = var.extension_type.publisher
  type                 = var.extension_type.type
  type_handler_version = var.extension_type.type_handler_version
  
  settings = <<SETTINGS
    {
        "fileUris": ["https://${var.SA_name}.blob.core.windows.net/${var.container_name}/Script.ps1"],
          "commandToExecute": "powershell -ExecutionPolicy Unrestricted -file Script.ps1"     
    }
SETTINGS

}
