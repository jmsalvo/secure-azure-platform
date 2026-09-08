locals {
  # Resource groups for the three lifecycle-aligned stacks. Created here in
  # bootstrap, not by the stacks themselves: a stack that created its own
  # resource group would force the CI apply identity to hold a
  # subscription-scoped role to make the first one. Creating them here keeps
  # every CI grant resource-group-scoped. See docs/decisions/0002-resource-groups-in-bootstrap.md.
  stack_resource_groups = toset([
    "rg-sap-dev-networking",
    "rg-sap-dev-observability",
    "rg-sap-dev-key-vault",
  ])
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
  name                = "id-sap-dev-ci-plan"
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
  name                = "id-sap-dev-ci-apply"
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

# The three lifecycle-aligned stacks own the resources *inside* one of these
# groups but do not create the group — they read it back with a data source.
# bootstrap creates it so no CI identity ever needs a subscription-scoped role.
resource "azurerm_resource_group" "stack" {
  for_each = local.stack_resource_groups
  name     = each.value
  location = var.location
  tags     = module.naming.tags
}

# Per-resource-group grants to the admin-managed Entra groups, replacing the
# subscription-scoped Reader / Contributor / RBAC Administrator grants this
# file used to make. The CI identities are members of the plan / apply groups
# (see README); a leaked apply token now reaches three named resource groups,
# not the whole subscription, and cannot create role assignments.
resource "azurerm_role_assignment" "stack_humans_contributor" {
  for_each             = azurerm_resource_group.stack
  scope                = each.value.id
  role_definition_name = "Contributor"
  principal_id         = var.humans_group_object_id
  principal_type       = "Group"
}

resource "azurerm_role_assignment" "stack_ci_plan_reader" {
  for_each             = azurerm_resource_group.stack
  scope                = each.value.id
  role_definition_name = "Reader"
  principal_id         = var.ci_plan_group_object_id
  principal_type       = "Group"
}

resource "azurerm_role_assignment" "stack_ci_apply_contributor" {
  for_each             = azurerm_resource_group.stack
  scope                = each.value.id
  role_definition_name = "Contributor"
  principal_id         = var.ci_apply_group_object_id
  principal_type       = "Group"
}

# Data-plane access to the platform Key Vault for human operators. The vault
# is created by the key-vault stack; granting Key Vault Secrets Officer on its
# resource group (which holds only that vault) reaches it without bootstrap
# referencing a resource that does not exist yet, and keeps every role
# assignment in this file. The key-vault module sets
# enable_rbac_authorization = true, so an RG-scoped data-plane role inherits
# to the vault.
resource "azurerm_role_assignment" "key_vault_humans_secrets_officer" {
  scope                = azurerm_resource_group.stack["rg-sap-dev-key-vault"].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.humans_group_object_id
  principal_type       = "Group"
}
