output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace, consumed by key-vault's diagnostic setting."
  value       = azurerm_log_analytics_workspace.this.id
}
