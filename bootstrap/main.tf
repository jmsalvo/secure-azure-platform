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

resource "azuread_application" "ci_plan" {
  display_name = "sap-dev-ci-plan"
}

resource "azuread_service_principal" "ci_plan" {
  client_id = azuread_application.ci_plan.client_id
}

resource "azuread_application_federated_identity_credential" "ci_plan_pull_request" {
  application_id = azuread_application.ci_plan.id
  display_name   = "github-pull-request"
  description    = "Federated credential for terraform plan on pull requests."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repository}:pull_request"
}

resource "azuread_application" "ci_apply" {
  display_name = "sap-dev-ci-apply"
}

resource "azuread_service_principal" "ci_apply" {
  client_id = azuread_application.ci_apply.client_id
}

resource "azuread_application_federated_identity_credential" "ci_apply_main" {
  application_id = azuread_application.ci_apply.id
  display_name   = "github-push-main"
  description    = "Federated credential for terraform apply on merge to main."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repository}:ref:refs/heads/main"
}

resource "azurerm_role_assignment" "tfstate_ci_plan_read" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azuread_service_principal.ci_plan.object_id
}

resource "azurerm_role_assignment" "tfstate_ci_apply_write" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.ci_apply.object_id
}
