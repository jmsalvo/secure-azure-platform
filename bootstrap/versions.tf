terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Local state deliberately: this config creates the remote-state backend
  # every other stack uses, so it can't use that backend itself.
}

provider "azurerm" {
  features {}

  # The bootstrap state storage account has shared_access_key_enabled = false
  # (Entra-only). Without this, the provider's post-create blob-service poll
  # defaults to key auth and apply fails with KeyBasedAuthenticationNotPermitted.
  storage_use_azuread = true

  # The stacks run with resource-group-scoped identities that cannot register
  # resource providers (a subscription-scoped action). bootstrap runs as a
  # subscription Owner and registers every provider any stack needs, once.
  # With resource_provider_registrations = "none", Terraform registers *only*
  # the providers listed below — so every namespace any config touches,
  # including resources created inside pinned modules, must appear here,
  # regardless of which providers Azure would otherwise auto-register.
  resource_provider_registrations = "none"
  resource_providers_to_register = [
    # Microsoft.ContainerService: the aks stack creates an azurerm_kubernetes_cluster (v0.2).
    "Microsoft.ContainerService",
    # Microsoft.Insights: the key-vault module creates an azurerm_monitor_diagnostic_setting internally (stack passes a non-null log_analytics_workspace_id).
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.Storage",
  ]
}

data "azurerm_client_config" "current" {}
