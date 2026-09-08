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

  # The stacks run with resource-group-scoped identities that cannot register
  # resource providers (a subscription-scoped action). bootstrap runs as a
  # subscription Owner and registers every provider any stack needs, once.
  # "none" means *only* the list below is registered — Microsoft.Network /
  # Storage / ManagedIdentity are in the provider's "core" set but must still
  # be listed here; KeyVault and OperationalInsights are not in "core".
  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.Storage",
  ]
}

data "azurerm_client_config" "current" {}
