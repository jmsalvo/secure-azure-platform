module "naming" {
  source = "github.com/jmsalvo/terraform-azure-modules//modules/naming?ref=v0.1.0"

  workload    = "sap"
  environment = "dev"
  location    = var.location
}

resource "azurerm_resource_group" "observability" {
  name     = "rg-sap-dev-observability"
  location = var.location
  tags     = module.naming.tags
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = module.naming.names["log_analytics_workspace"]
  resource_group_name = azurerm_resource_group.observability.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = module.naming.tags
}

resource "azurerm_role_assignment" "humans_contributor" {
  scope                = azurerm_resource_group.observability.id
  role_definition_name = "Contributor"
  principal_id         = var.humans_group_object_id
}

resource "azurerm_role_assignment" "ci_plan_reader" {
  scope                = azurerm_resource_group.observability.id
  role_definition_name = "Reader"
  principal_id         = var.ci_plan_group_object_id
}

resource "azurerm_role_assignment" "ci_apply_contributor" {
  scope                = azurerm_resource_group.observability.id
  role_definition_name = "Contributor"
  principal_id         = var.ci_apply_group_object_id
}
