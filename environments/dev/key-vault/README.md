# key-vault

The platform-level Key Vault — shared/break-glass admin credentials, shared
TLS certs; not a workload vault (no application workload exists yet at
`v0.1`). Also the integration proof point for the landing zone: the only
stack that reads outputs from all three others, so a successful `apply`
demonstrates the `terraform_remote_state` wiring end-to-end.

`network_acls` restricts data-plane access to the `platform` subnet
`networking` creates (`Microsoft.KeyVault` service endpoint) plus Azure
services (module default). No VM or private endpoint lives in that subnet
yet, so in practice the vault's data plane is Azure-services-only until a
future workload occupies it — the human operator's `Key Vault Secrets
Officer` role assignment is ready for when that changes, but reaching the
vault from a laptop today needs a temporary `network_acls.ip_rules` entry
or `public_network_access_enabled = true`, deliberately not wired up by
default.

Depends on all three other stacks; applies last.
