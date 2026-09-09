variable "location" {
  description = "Azure region for the bootstrap resource group and storage account."
  type        = string
  default     = "eastus2"
}

variable "github_repository" {
  description = "GitHub \"owner/repo\" the OIDC federated credentials trust, for example \"jmsalvo/secure-azure-platform\"."
  type        = string
}

variable "humans_group_object_id" {
  description = "Object ID of the admin-precreated sap-dev-humans Entra group. Same value as the HUMANS_GROUP_OBJECT_ID GitHub repo variable used before 2026-09-07; now a bootstrap-only input."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.humans_group_object_id))
    error_message = "humans_group_object_id must be a GUID."
  }
}

variable "ci_plan_group_object_id" {
  description = "Object ID of the admin-precreated sap-dev-ci-plan Entra group."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.ci_plan_group_object_id))
    error_message = "ci_plan_group_object_id must be a GUID."
  }
}

variable "ci_apply_group_object_id" {
  description = "Object ID of the admin-precreated sap-dev-ci-apply Entra group."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.ci_apply_group_object_id))
    error_message = "ci_apply_group_object_id must be a GUID."
  }
}
