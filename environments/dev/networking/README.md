# networking

VNet + one subnet (`platform`, with the `Microsoft.KeyVault` service
endpoint) + its NSG, plus this stack's own Contributor/Reader role
assignments for the three Entra groups `identity` creates.

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

Depends on `identity` (reads its remote state for the three group object
IDs — `identity` must have a real applied state in the backend before this
stack's `plan`/`apply` can succeed, not just exist in the same PR's diff).
