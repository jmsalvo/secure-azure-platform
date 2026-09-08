# networking

VNet + one subnet (`platform`, with the `Microsoft.KeyVault` service
endpoint) + its NSG.

The resource group (`rg-sap-dev-networking`) and every RBAC assignment on it
is created by `bootstrap/` (run as a subscription Owner); this stack reads
the group with `data "azurerm_resource_group" "this"` and creates only the
networking resources inside it. See
`docs/decisions/0002-resource-groups-in-bootstrap.md`.

## NSG posture

The `platform` subnet carries a module-managed NSG (`nsg-platform`) with a
deny-by-default baseline: Internet inbound and Internet outbound are both
denied at priority 4096, with a single Allow at 4000 for TCP/443 to the
`AzureKeyVault` service tag — the one egress path the landing zone needs,
matching the service endpoint on the subnet. Azure's platform defaults
(intra-VNet traffic, load-balancer probes) sit at 65000/65001 and are left
intact deliberately: the Deny rules target the `Internet` service tag, not
`*`, so adding a workload here doesn't start from a subnet that can't talk
to itself.

No upstream stack dependency. The only input is `location`.
