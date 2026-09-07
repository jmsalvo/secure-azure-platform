locals {
  subscription_scope = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
}

module "naming" {
  source = "github.com/jmsalvo/terraform-azure-modules//modules/naming?ref=v0.1.0"

  workload    = "sap"
  environment = "dev"
  location    = var.location
  suffix      = ["tfstate"]
}

resource "azurerm_resource_group" "bootstrap" {
  name     = "rg-sap-dev-bootstrap"
  location = var.location
  tags     = module.naming.tags
}

#trivy:ignore:AVD-AZU-0012 -- public network access is required: GitHub-hosted Actions runners (used for every stack's plan/apply job) have no stable IP range to allowlist; access is instead restricted to Entra ID/RBAC via shared_access_key_enabled=false below, with no account key to leak.
resource "azurerm_storage_account" "tfstate" {
  name                = module.naming.names["storage_account"]
  resource_group_name = azurerm_resource_group.bootstrap.name
  location            = var.location

  account_tier              = "Standard"
  account_replication_type  = "LRS"
  min_tls_version           = "TLS1_2"
  shared_access_key_enabled = false # force Entra ID auth for state access, no account key

  blob_properties {
    versioning_enabled = true
  }

  tags = module.naming.tags
}

resource "azurerm_storage_container" "tfstate" {
  name               = "tfstate"
  storage_account_id = azurerm_storage_account.tfstate.id
}

# CI identities: user-assigned managed identities federated to GitHub OIDC.
# Plain ARM resources in the bootstrap resource group — creating them needs
# only Contributor on that RG (you have subscription Owner), no directory
# role and no Microsoft Graph permission. A managed identity's principal is a
# valid RBAC target and Entra group member, exactly as an app registration's
# service principal was.
resource "azurerm_user_assigned_identity" "ci_plan" {
  name                = "sap-dev-ci-plan"
  resource_group_name = azurerm_resource_group.bootstrap.name
  location            = var.location
  tags                = module.naming.tags
}

resource "azurerm_federated_identity_credential" "ci_plan_pull_request" {
  name                = "github-pull-request"
  resource_group_name = azurerm_resource_group.bootstrap.name
  parent_id           = azurerm_user_assigned_identity.ci_plan.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.github_repository}:pull_request"
}

resource "azurerm_user_assigned_identity" "ci_apply" {
  name                = "sap-dev-ci-apply"
  resource_group_name = azurerm_resource_group.bootstrap.name
  location            = var.location
  tags                = module.naming.tags
}

resource "azurerm_federated_identity_credential" "ci_apply_main" {
  name                = "github-push-main"
  resource_group_name = azurerm_resource_group.bootstrap.name
  parent_id           = azurerm_user_assigned_identity.ci_apply.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.github_repository}:ref:refs/heads/main"
}

# shared_access_key_enabled = false on the state account means state access is
# Entra-ID-only; each CI identity needs an explicit data-plane role on the
# storage account to read/write the state blob (separate from the
# Reader/Contributor role its Entra group later gets on each resource group).
resource "azurerm_role_assignment" "tfstate_ci_plan_read" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.ci_plan.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "tfstate_ci_apply_write" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.ci_apply.principal_id
  principal_type       = "ServicePrincipal"
}

# Blob access to the state account only gets CI as far as reading/writing
# state. The stacks themselves live at subscription scope: networking,
# observability and key-vault each create their own azurerm_resource_group,
# which no resource-group-scoped role can authorise.
resource "azurerm_role_assignment" "subscription_ci_plan_read" {
  scope                = local.subscription_scope
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.ci_plan.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "subscription_ci_apply_contribute" {
  scope                = local.subscription_scope
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.ci_apply.principal_id
  principal_type       = "ServicePrincipal"
}

# Contributor explicitly excludes Microsoft.Authorization/*/Write, so it cannot
# create the azurerm_role_assignment resources each stack owns. RBAC
# Administrator is the least-privileged built-in that adds exactly that (role
# assignment management, no other data or control plane rights) — deliberately
# not Owner or User Access Administrator.
resource "azurerm_role_assignment" "subscription_ci_apply_rbac_admin" {
  scope                = local.subscription_scope
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.ci_apply.principal_id
  principal_type       = "ServicePrincipal"
}
