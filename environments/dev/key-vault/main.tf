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

data "terraform_remote_state" "networking" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-sap-dev-bootstrap"
    storage_account_name = var.tfstate_storage_account_name
    container_name       = "tfstate"
    key                  = "networking.tfstate"
    use_azuread_auth     = true
  }
}

data "terraform_remote_state" "observability" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-sap-dev-bootstrap"
    storage_account_name = var.tfstate_storage_account_name
    container_name       = "tfstate"
    key                  = "observability.tfstate"
    use_azuread_auth     = true
  }
}

data "azurerm_client_config" "current" {}

module "naming" {
  source = "github.com/jmsalvo/terraform-azure-modules//modules/naming?ref=v0.1.0"

  workload    = "sap"
  environment = "dev"
  location    = var.location
}

resource "azurerm_resource_group" "key_vault" {
  name     = "rg-sap-dev-key-vault"
  location = var.location
  tags     = module.naming.tags
}

module "key_vault" {
  source = "github.com/jmsalvo/terraform-azure-modules//modules/key-vault?ref=v0.1.0"

  name                = module.naming.names["key_vault"]
  resource_group_name = azurerm_resource_group.key_vault.name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = module.naming.tags

  network_acls = {
    virtual_network_subnet_ids = [data.terraform_remote_state.networking.outputs.platform_subnet_id]
  }

  log_analytics_workspace_id = data.terraform_remote_state.observability.outputs.log_analytics_workspace_id
}

resource "azurerm_role_assignment" "humans_contributor" {
  scope                = azurerm_resource_group.key_vault.id
  role_definition_name = "Contributor"
  principal_id         = data.terraform_remote_state.identity.outputs.humans_group_object_id
}

resource "azurerm_role_assignment" "ci_plan_reader" {
  scope                = azurerm_resource_group.key_vault.id
  role_definition_name = "Reader"
  principal_id         = data.terraform_remote_state.identity.outputs.ci_plan_group_object_id
}

resource "azurerm_role_assignment" "ci_apply_contributor" {
  scope                = azurerm_resource_group.key_vault.id
  role_definition_name = "Contributor"
  principal_id         = data.terraform_remote_state.identity.outputs.ci_apply_group_object_id
}

# RG-level Contributor manages the vault as an ARM resource but does not grant
# data-plane access (the module sets enable_rbac_authorization = true, no
# access policies) — humans additionally need a Key Vault data-plane role to
# actually read/write secrets.
resource "azurerm_role_assignment" "humans_secrets_officer" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.terraform_remote_state.identity.outputs.humans_group_object_id
}
