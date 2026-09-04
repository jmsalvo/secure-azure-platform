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
  description = "Client (application) ID of the sap-dev-ci-plan app registration. Copy into the ARM_CLIENT_ID_PLAN GitHub repo variable."
  value       = azuread_application.ci_plan.client_id
}

output "ci_plan_service_principal_object_id" {
  description = "Object ID of the sap-dev-ci-plan service principal. Copy into environments/dev/identity's tfvars."
  value       = azuread_service_principal.ci_plan.object_id
}

output "ci_apply_client_id" {
  description = "Client (application) ID of the sap-dev-ci-apply app registration. Copy into the ARM_CLIENT_ID_APPLY GitHub repo variable."
  value       = azuread_application.ci_apply.client_id
}

output "ci_apply_service_principal_object_id" {
  description = "Object ID of the sap-dev-ci-apply service principal. Copy into environments/dev/identity's tfvars."
  value       = azuread_service_principal.ci_apply.object_id
}

output "tenant_id" {
  description = "Entra tenant ID. Copy into the ARM_TENANT_ID GitHub repo variable."
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Azure subscription ID. Copy into the ARM_SUBSCRIPTION_ID GitHub repo variable."
  value       = data.azurerm_client_config.current.subscription_id
}
