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

  # network_acls only apply to the public endpoint. The module defaults
  # public_network_access_enabled to false, which would make the vault
  # private-endpoint-only and leave the subnet rule below completely inert —
  # so turn the public endpoint on and let deny-by-default plus the service
  # endpoint from networking's platform subnet do the actual restricting.
  # No private endpoint exists at v0.1 (nothing to attach one to).
  public_network_access_enabled = true

  network_acls = {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [data.terraform_remote_state.networking.outputs.platform_subnet_id]
  }

  log_analytics_workspace_id = data.terraform_remote_state.observability.outputs.log_analytics_workspace_id
}

resource "azurerm_role_assignment" "humans_contributor" {
  scope                = azurerm_resource_group.key_vault.id
  role_definition_name = "Contributor"
  principal_id         = var.humans_group_object_id
}

resource "azurerm_role_assignment" "ci_plan_reader" {
  scope                = azurerm_resource_group.key_vault.id
  role_definition_name = "Reader"
  principal_id         = var.ci_plan_group_object_id
}

resource "azurerm_role_assignment" "ci_apply_contributor" {
  scope                = azurerm_resource_group.key_vault.id
  role_definition_name = "Contributor"
  principal_id         = var.ci_apply_group_object_id
}

# RG-level Contributor manages the vault as an ARM resource but does not grant
# data-plane access (the module sets enable_rbac_authorization = true, no
# access policies) — humans additionally need a Key Vault data-plane role to
# actually read/write secrets.
resource "azurerm_role_assignment" "humans_secrets_officer" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.humans_group_object_id
}
