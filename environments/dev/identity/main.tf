resource "azuread_group" "humans" {
  display_name     = "sap-dev-humans"
  description      = "Human operator: manual work, debugging, break-glass access to the dev landing zone."
  security_enabled = true
}

resource "azuread_group" "ci_plan" {
  display_name     = "sap-dev-ci-plan"
  description      = "CI identity for terraform plan on pull requests. Reader only."
  security_enabled = true
}

resource "azuread_group" "ci_apply" {
  display_name     = "sap-dev-ci-apply"
  description      = "CI identity for terraform apply on merge to main. Contributor."
  security_enabled = true
}

resource "azuread_group_member" "humans_operator" {
  group_object_id  = azuread_group.humans.object_id
  member_object_id = var.human_operator_object_id
}

resource "azuread_group_member" "ci_plan_service_principal" {
  group_object_id  = azuread_group.ci_plan.object_id
  member_object_id = var.ci_plan_service_principal_object_id
}

resource "azuread_group_member" "ci_apply_service_principal" {
  group_object_id  = azuread_group.ci_apply.object_id
  member_object_id = var.ci_apply_service_principal_object_id
}
