variable "location" {
  description = "Azure region for this stack's resources."
  type        = string
  default     = "eastus2"
}

variable "tfstate_storage_account_name" {
  description = "Name of the bootstrap-created storage account holding remote state (bootstrap output tfstate_storage_account_name)."
  type        = string
}
