variable "human_operator_object_id" {
  description = "Entra object ID of the human operator, added as a member of sap-dev-humans."
  type        = string
}

variable "ci_plan_service_principal_object_id" {
  description = "Object ID of the sap-dev-ci-plan app registration's service principal (bootstrap output ci_plan_service_principal_object_id)."
  type        = string
}

variable "ci_apply_service_principal_object_id" {
  description = "Object ID of the sap-dev-ci-apply app registration's service principal (bootstrap output ci_apply_service_principal_object_id)."
  type        = string
}
