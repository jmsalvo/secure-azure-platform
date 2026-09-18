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

data "azurerm_resource_group" "this" {
  name = "rg-sap-dev-aks"
}

module "aks" {
  source = "github.com/jmsalvo/terraform-azure-modules//modules/aks?ref=v0.2.0"

  name                = module.naming.names["kubernetes_cluster"]
  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.location
  dns_prefix          = "sap-dev"
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = module.naming.tags

  default_node_pool_subnet_id = data.terraform_remote_state.networking.outputs.aks_subnet_id
  log_analytics_workspace_id  = data.terraform_remote_state.observability.outputs.log_analytics_workspace_id
  admin_group_object_ids      = var.admin_group_object_ids

  # Public API server, firewalled to an explicit allow list instead of fully
  # private — avoids the jumpbox overhead a private cluster would need for a
  # project stood up and torn down repeatedly. See the v0.2 design spec's
  # "API server access" section.
  private_cluster_enabled         = false
  api_server_authorized_ip_ranges = [var.operator_public_ip_cidr]

  # System pool: fixed at 1 node, tainted so only kube-system schedules here.
  # vm_size is Standard_B2s_v2, not the original Standard_B2s: this
  # subscription's eastus2 quota only allows the v2 generation of the B-series
  # burstable SKUs (discovered from the live apply's 400 BadRequest, not from
  # any docs — Azure returns the current allow-list in the error body).
  default_node_pool = {
    name                         = "system"
    vm_size                      = "Standard_B2s_v2"
    node_count                   = 1
    only_critical_addons_enabled = true
  }

  # User pool: holds the sample workload, autoscales 1-2 nodes.
  user_node_pool = {
    name      = "user"
    vm_size   = "Standard_B2s_v2"
    min_count = 1
    max_count = 2
  }
}
