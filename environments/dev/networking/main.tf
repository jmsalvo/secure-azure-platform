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

      # Deny-by-default baseline. Setting security_rules makes the module
      # create nsg-platform and associate it with the subnet. Azure's own
      # default rules already deny all inbound but *allow* all outbound to the
      # Internet, so the two Deny rules below make the inbound posture explicit
      # (it survives any future rule inserted above priority 4096) and close the
      # outbound hole. Both are scoped to the Internet service tag rather than
      # "*" so the platform defaults at 65000/65001 — intra-VNet traffic and
      # load-balancer probes — keep working; the single Allow carves out the one
      # egress path this landing zone actually needs today, Key Vault over the
      # Microsoft.KeyVault service endpoint declared above.
      security_rules = [
        {
          name                       = "allow-key-vault-outbound"
          priority                   = 4000
          direction                  = "Outbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "443"
          source_address_prefix      = "VirtualNetwork"
          destination_address_prefix = "AzureKeyVault"
        },
        {
          name                       = "deny-internet-inbound"
          priority                   = 4096
          direction                  = "Inbound"
          access                     = "Deny"
          protocol                   = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
          source_address_prefix      = "Internet"
          destination_address_prefix = "*"
        },
        {
          name                       = "deny-internet-outbound"
          priority                   = 4096
          direction                  = "Outbound"
          access                     = "Deny"
          protocol                   = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
          source_address_prefix      = "*"
          destination_address_prefix = "Internet"
        },
      ]
    }
  }
}

resource "azurerm_role_assignment" "humans_contributor" {
  scope                = azurerm_resource_group.networking.id
  role_definition_name = "Contributor"
  principal_id         = var.humans_group_object_id
}

resource "azurerm_role_assignment" "ci_plan_reader" {
  scope                = azurerm_resource_group.networking.id
  role_definition_name = "Reader"
  principal_id         = var.ci_plan_group_object_id
}

resource "azurerm_role_assignment" "ci_apply_contributor" {
  scope                = azurerm_resource_group.networking.id
  role_definition_name = "Contributor"
  principal_id         = var.ci_apply_group_object_id
}
