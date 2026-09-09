terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}

  # Resource providers are registered once by bootstrap (run as a
  # subscription Owner). This stack's CI identity is resource-group-scoped
  # and cannot register them. See docs/decisions/0002-resource-groups-in-bootstrap.md.
  resource_provider_registrations = "none"
}
