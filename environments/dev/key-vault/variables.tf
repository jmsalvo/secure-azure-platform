variable "location" {
  description = "Azure region for this stack's resources."
  type        = string
  default     = "eastus2"
}

variable "tfstate_storage_account_name" {
  description = "Name of the bootstrap-created storage account holding remote state (bootstrap output tfstate_storage_account_name)."
  type        = string
}

variable "humans_group_object_id" {
  description = "Object ID of the admin-precreated sap-dev-humans Entra group (GitHub repo variable HUMANS_GROUP_OBJECT_ID)."
  type        = string
}

variable "ci_plan_group_object_id" {
  description = "Object ID of the admin-precreated sap-dev-ci-plan Entra group (GitHub repo variable CI_PLAN_GROUP_OBJECT_ID)."
  type        = string
}

variable "ci_apply_group_object_id" {
  description = "Object ID of the admin-precreated sap-dev-ci-apply Entra group (GitHub repo variable CI_APPLY_GROUP_OBJECT_ID)."
  type        = string
}
