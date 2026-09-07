# Changelog

All notable changes to this repo are documented here.

## [Unreleased]

### Added

- repo scaffold: conventions, tooling config (`.gitattributes`, `.gitignore`,
  `.pre-commit-config.yaml`, `.tflint.hcl`, `trivy.yaml`, `scripts/check.ps1`),
  `CONTRIBUTING.md`, and ADR 0001 (lifecycle-aligned stacks)
- bootstrap/: one-time state storage account + user-assigned managed
  identities (GitHub OIDC federated) for CI
- environments/dev/networking/: VNet, subnet, RBAC role assignments
- environments/dev/observability/: Log Analytics workspace, RBAC role assignments
- environments/dev/key-vault/: platform Key Vault, RBAC role assignments
- .github/workflows/ci.yml: OIDC-authenticated per-stack plan/apply CI, dependency-ordered
- root README.md: stack dependency diagram, first-time rollout order, CI shape,
  security considerations
- environments/dev/networking/: deny-by-default NSG on the `platform` subnet
- committed `.terraform.lock.hcl` for bootstrap and all three stacks
  (linux_amd64 + windows_amd64 hashes); CI inits with `-lockfile=readonly`
- .github/workflows/ci.yml: per-stack `concurrency` groups on the three
  `apply_*` jobs, so simultaneous merges queue instead of racing for state

### Changed

- Default branch renamed `master` → `main` (matches what `ci.yml` and
  `bootstrap/`'s federated-credential subject already reference).
- `networking`, `observability`, and `key-vault` take the three Entra group
  object IDs as input variables (GitHub repo variables `HUMANS_GROUP_OBJECT_ID`
  / `CI_PLAN_GROUP_OBJECT_ID` / `CI_APPLY_GROUP_OBJECT_ID`) instead of reading
  them from the `identity` stack's remote state.

### Removed

- `environments/dev/identity/`. The three Entra RBAC groups are now created
  and membership-managed by a directory admin outside this repo (assigned,
  cloud-only security groups); the repo makes no Microsoft Graph writes and
  the `azuread` provider is gone. Stack dependency graph drops from three
  tiers to two.

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
  `apply_key_vault` retains `always()` and the explicit checks because it still
  has skippable upstream applies; `apply_networking` / `apply_observability` no
  longer have any skippable dependency and rely on GitHub's implicit
  `success()` gate.
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
