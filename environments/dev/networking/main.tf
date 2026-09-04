data "terraform_remote_state" "identity" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-sap-dev-bootstrap"
    storage_account_name = var.tfstate_storage_account_name
    container_name       = "tfstate"
    key                  = "identity.tfstate"
    use_azuread_auth     = true
  }
}

module "naming" {
  source = "github.com/jmsalvo/terraform-azure-modules//modules/naming?ref=v0.1.0"

  workload    = "sap"
  environment = "dev"
  location    = var.location
}

resource "azurerm_resource_group" "networking" {
  name     = "rg-sap-dev-networking"
  location = var.location
  tags     = module.naming.tags
}

module "networking" {
  source = "github.com/jmsalvo/terraform-azure-modules//modules/networking?ref=v0.1.0"

  resource_group_name = azurerm_resource_group.networking.name
  location            = var.location
  vnet_name           = module.naming.names["virtual_network"]
  address_space       = ["10.30.0.0/16"]
  tags                = module.naming.tags

  # Single subnet for v0.1 — no workload exists yet to place elsewhere. The
  # Microsoft.KeyVault service endpoint is what lets key-vault's network_acls
  # allow traffic from this subnet (see environments/dev/key-vault).
  subnets = {
    platform = {
      address_prefixes  = ["10.30.1.0/24"]
      service_endpoints = ["Microsoft.KeyVault"]
    }
  }
}

resource "azurerm_role_assignment" "humans_contributor" {
  scope                = azurerm_resource_group.networking.id
  role_definition_name = "Contributor"
  principal_id         = data.terraform_remote_state.identity.outputs.humans_group_object_id
}

resource "azurerm_role_assignment" "ci_plan_reader" {
  scope                = azurerm_resource_group.networking.id
  role_definition_name = "Reader"
  principal_id         = data.terraform_remote_state.identity.outputs.ci_plan_group_object_id
}

resource "azurerm_role_assignment" "ci_apply_contributor" {
  scope                = azurerm_resource_group.networking.id
  role_definition_name = "Contributor"
  principal_id         = data.terraform_remote_state.identity.outputs.ci_apply_group_object_id
}
