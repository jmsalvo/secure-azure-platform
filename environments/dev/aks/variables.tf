variable "location" {
  description = "Azure region for this stack's resources."
  type        = string
  default     = "eastus2"
}

variable "tfstate_storage_account_name" {
  description = "Name of the bootstrap-created storage account holding remote state (bootstrap output tfstate_storage_account_name)."
  type        = string
}

variable "operator_public_ip_cidr" {
  description = "Your current public IP as a /32 CIDR (e.g. \"203.0.113.5/32\"), authorized to reach the API server's public endpoint. Changes across sessions/networks — find yours with `(Invoke-RestMethod ifconfig.me)` on Windows or `curl ifconfig.me` elsewhere, then append /32."
  type        = string

  validation {
    condition     = can(cidrhost(var.operator_public_ip_cidr, 0))
    error_message = "operator_public_ip_cidr must be a valid CIDR, e.g. \"203.0.113.5/32\"."
  }
}

variable "admin_group_object_ids" {
  description = "Entra group object IDs granted cluster-admin via Azure RBAC for Kubernetes — set to [sap-dev-humans' object ID] so you can `az aks get-credentials` + `kubectl apply` the sample workload by hand. Not a bootstrap-owned ARM role assignment (ADR 0002 is about who creates *ARM* role assignments); this is a value read into an AKS resource property, so ci-apply's resource-group-scoped Contributor role is enough to set it. Default empty means no one has kubectl access until you set this."
  type        = list(string)
}
