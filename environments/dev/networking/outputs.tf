output "vnet_id" {
  description = "Resource ID of the VNet."
  value       = module.networking.vnet_id
}

output "platform_subnet_id" {
  description = "Resource ID of the platform subnet, consumed by key-vault's network_acls."
  value       = module.networking.subnet_ids["platform"]
}

output "aks_subnet_id" {
  description = "Resource ID of the aks subnet, consumed by the aks stack's node pools."
  value       = module.networking.subnet_ids["aks"]
}
