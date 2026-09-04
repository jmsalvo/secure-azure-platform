output "humans_group_object_id" {
  description = "Object ID of sap-dev-humans, for Contributor role assignments in other stacks."
  value       = azuread_group.humans.object_id
}

output "ci_plan_group_object_id" {
  description = "Object ID of sap-dev-ci-plan, for Reader role assignments in other stacks."
  value       = azuread_group.ci_plan.object_id
}

output "ci_apply_group_object_id" {
  description = "Object ID of sap-dev-ci-apply, for Contributor role assignments in other stacks."
  value       = azuread_group.ci_apply.object_id
}
