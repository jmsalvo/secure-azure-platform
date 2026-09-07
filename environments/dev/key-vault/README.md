# key-vault

The platform-level Key Vault — shared/break-glass admin credentials, shared
TLS certs; not a workload vault (no application workload exists yet at
`v0.1`). Also the integration proof point for the landing zone: the only
stack that reads outputs from both others (`networking`, `observability`),
so a successful `apply` demonstrates the `terraform_remote_state` wiring
end-to-end.

`network_acls` restricts data-plane access to the `platform` subnet
`networking` creates (`Microsoft.KeyVault` service endpoint) plus Azure
services (`bypass = "AzureServices"`), with `default_action = "Deny"`
turning everything else away. The stack sets
`public_network_access_enabled = true` explicitly, overriding the module's
`false` default: network ACLs are enforced *on* the public endpoint, so
with public access off they never evaluate at all and the vault would
simply be private-endpoint-only — no private endpoint exists at `v0.1`, and
the subnet allowance documented here would be silently inert.

No VM or private endpoint lives in that subnet yet, so in practice the
vault's data plane is Azure-services-only until a future workload occupies
it — the human operator's `Key Vault Secrets Officer` role assignment is
ready for when that changes. Reaching the vault from a laptop today needs a
temporary `network_acls.ip_rules` entry for your public IP, deliberately
not wired up by default.

Depends on both other stacks (`networking`, `observability`); applies last.
