module "naming" {
  source = "github.com/jmsalvo/terraform-azure-modules//modules/naming?ref=v0.1.0"

  workload    = "sap"
  environment = "dev"
  location    = var.location
}

data "azurerm_resource_group" "this" {
  name = "rg-sap-dev-networking"
}

module "networking" {
  source = "github.com/jmsalvo/terraform-azure-modules//modules/networking?ref=v0.1.0"

  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.location
  vnet_name           = module.naming.names["virtual_network"]
  address_space       = ["10.30.0.0/16"]
  tags                = module.naming.tags

  # Two subnets: platform (this landing zone's original workloads) and aks
  # (v0.2, defined below). The Microsoft.KeyVault service endpoint here is
  # what lets key-vault's network_acls allow traffic from this subnet (see
  # environments/dev/key-vault).
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
    aks = {
      address_prefixes = ["10.30.2.0/24"]

      # Inbound-deny-only, mirroring platform's deny-internet-inbound rule.
      # Outbound is deliberately left unrestricted: AKS nodes need broad
      # egress (Microsoft Container Registry, the API server, Azure Monitor,
      # OS package repos, ...) that's impractical to allow-list accurately in
      # a plain NSG. Real egress lockdown is Azure Firewall + FQDN filtering
      # — out of scope for v0.2 (see the design spec's "Out of scope").
      security_rules = [
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
      ]
    }
  }
}
