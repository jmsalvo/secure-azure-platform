module "naming" {
  source = "github.com/jmsalvo/terraform-azure-modules//modules/naming?ref=v0.1.0"

  workload    = "sap"
  environment = "dev"
  location    = var.location
}

data "azurerm_resource_group" "this" {
  name = "rg-sap-dev-observability"
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = module.naming.names["log_analytics_workspace"]
  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = module.naming.tags
}
