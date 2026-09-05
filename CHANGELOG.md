# Changelog

All notable changes to this repo are documented here.

## [Unreleased]

### Added

- repo scaffold: conventions, tooling config (`.gitattributes`, `.gitignore`,
  `.pre-commit-config.yaml`, `.tflint.hcl`, `trivy.yaml`, `scripts/check.ps1`),
  `CONTRIBUTING.md`, and ADR 0001 (lifecycle-aligned stacks)
- bootstrap/: one-time state storage account + OIDC app registrations for CI
- environments/dev/identity/: the three Entra RBAC groups
- environments/dev/networking/: VNet, subnet, RBAC role assignments
- environments/dev/observability/: Log Analytics workspace, RBAC role assignments
- environments/dev/key-vault/: platform Key Vault, RBAC role assignments
- .github/workflows/ci.yml: OIDC-authenticated per-stack plan/apply CI, dependency-ordered
- root README.md: stack dependency diagram, first-time rollout order, CI shape,
  security considerations
- environments/dev/networking/: deny-by-default NSG on the `platform` subnet
- committed `.terraform.lock.hcl` for bootstrap and all four stacks
  (linux_amd64 + windows_amd64 hashes); CI inits with `-lockfile=readonly`
- .github/workflows/ci.yml: per-stack `concurrency` groups on the four
  `apply_*` jobs, so simultaneous merges queue instead of racing for state

### Fixed

- bootstrap: suppress AVD-AZU-0012 (public network access) on the tfstate
  storage account with a documented inline ignore — GitHub-hosted CI
  runners have no stable IP range to restrict to; Entra ID/RBAC-only access
  (`shared_access_key_enabled = false`) is the accepted boundary.
- ci: the `apply_*` jobs' `always()` condition disables GitHub's implicit
  `success()` gate over the whole `needs:` list, so a live `terraform apply`
  could proceed even after `fmt`/`validate`/`tflint`/`trivy` failed. Restored
  the gate with explicit `needs.<job>.result == 'success'` checks, now
  documented in-file so the condition isn't "simplified" back into the bug.
- bootstrap: grant the CI identities the subscription-scoped roles the stacks
  actually need — `Reader` for `sap-dev-ci-plan`, `Contributor` plus
  `Role Based Access Control Administrator` for `sap-dev-ci-apply`. Blob
  access to the state account alone couldn't create resource groups, and
  `Contributor` excludes `Microsoft.Authorization/*/Write`, so no stack's
  role assignments could ever have applied.
- environments/dev/key-vault: set `public_network_access_enabled = true`
  explicitly. The module defaults it to `false`, which made the vault
  private-endpoint-only and left the documented `network_acls` subnet
  restriction inert — ACLs are only evaluated on the public endpoint.
