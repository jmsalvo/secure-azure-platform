# networking

VNet + one subnet (`platform`, with the `Microsoft.KeyVault` service
endpoint) + its NSG, plus this stack's own Contributor/Reader role
assignments for the three admin-managed Entra groups (`sap-dev-humans`,
`sap-dev-ci-plan`, `sap-dev-ci-apply`).

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

No upstream stack dependency. The three group object IDs arrive as input
variables (`humans_group_object_id`, `ci_plan_group_object_id`,
`ci_apply_group_object_id`), fed by GitHub repository variables
(`HUMANS_GROUP_OBJECT_ID`, `CI_PLAN_GROUP_OBJECT_ID`,
`CI_APPLY_GROUP_OBJECT_ID`); the groups are created and managed by an admin
outside this repo.
