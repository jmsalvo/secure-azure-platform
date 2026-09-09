output "tfstate_resource_group_name" {
  description = "Resource group holding the remote-state storage account."
  value       = azurerm_resource_group.bootstrap.name
}

output "tfstate_storage_account_name" {
  description = "Storage account holding every stack's remote state. Copy into each stack's backend.hcl."
  value       = azurerm_storage_account.tfstate.name
}

output "tfstate_container_name" {
  description = "Blob container holding every stack's remote state."
  value       = azurerm_storage_container.tfstate.name
}

output "ci_plan_client_id" {
  description = "Client ID of the id-sap-dev-ci-plan managed identity. Copy into the ARM_CLIENT_ID_PLAN GitHub repo variable."
  value       = azurerm_user_assigned_identity.ci_plan.client_id
}

output "ci_plan_principal_id" {
  description = "Principal (object) ID of the id-sap-dev-ci-plan managed identity. Add as a member of the sap-dev-ci-plan Entra group (see bootstrap/README.md)."
  value       = azurerm_user_assigned_identity.ci_plan.principal_id
}

output "ci_apply_client_id" {
  description = "Client ID of the id-sap-dev-ci-apply managed identity. Copy into the ARM_CLIENT_ID_APPLY GitHub repo variable."
  value       = azurerm_user_assigned_identity.ci_apply.client_id
}

output "ci_apply_principal_id" {
  description = "Principal (object) ID of the id-sap-dev-ci-apply managed identity. Add as a member of the sap-dev-ci-apply Entra group (see bootstrap/README.md)."
  value       = azurerm_user_assigned_identity.ci_apply.principal_id
}

output "tenant_id" {
  description = "Entra tenant ID. Copy into the ARM_TENANT_ID GitHub repo variable."
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Azure subscription ID. Copy into the ARM_SUBSCRIPTION_ID GitHub repo variable."
  value       = data.azurerm_client_config.current.subscription_id
}

output "stack_resource_group_names" {
  description = "Resource groups bootstrap created for the lifecycle-aligned stacks. Each stack reads its own back with a data source."
  value       = sort([for rg in azurerm_resource_group.stack : rg.name])
}
