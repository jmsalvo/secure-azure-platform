variable "location" {
  description = "Azure region for the bootstrap resource group and storage account."
  type        = string
  default     = "eastus2"
}

variable "github_repository" {
  description = "GitHub \"owner/repo\" the OIDC federated credentials trust, for example \"jmsalvo/secure-azure-platform\"."
  type        = string
}

# GitHub's immutable OIDC subject claim format (rolled out 2026-04-23) bakes
# the owner and repository's numeric IDs into the sub claim as
# "owner@owner_id/repo@repo_id" so a renamed/recycled name can't mint a token
# matching an old trust config. Repos created after that rollout (this one
# included) get the immutable format from day one, so the federated
# credentials' subject must include these IDs or every OIDC exchange 401s
# with AADSTS700213. Find them with:
#   gh api repos/<owner>/<repo> --jq '{owner_id: .owner.id, repo_id: .id}'
variable "github_owner_id" {
  description = "Numeric GitHub user/org ID of the repository owner (see gh api repos/<owner>/<repo> --jq .owner.id)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be numeric."
  }
}

variable "github_repository_id" {
  description = "Numeric GitHub repository ID (see gh api repos/<owner>/<repo> --jq .id)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be numeric."
  }
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

variable "enable_defender_for_containers" {
  description = "Enable Microsoft Defender for Containers (subscription-wide). Costs ~$0.00941/vCore/hour across every AKS node while on — see the v0.2 design spec's cost summary. Default off; the operator toggles this on briefly to capture evidence, then off."
  type        = bool
  default     = false
}
