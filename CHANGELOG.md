# Changelog

All notable changes to this repo are documented here.

## [Unreleased]

## [0.1.0] - 2026-09-11

### Added

- repo scaffold: conventions, tooling config (`.gitattributes`, `.gitignore`,
  `.pre-commit-config.yaml`, `.tflint.hcl`, `trivy.yaml`, `scripts/check.ps1`),
  `CONTRIBUTING.md`, and ADR 0001 (lifecycle-aligned stacks)
- bootstrap/: one-time state storage account + user-assigned managed
  identities (GitHub OIDC federated) for CI
- environments/dev/networking/: VNet, subnet
- environments/dev/observability/: Log Analytics workspace
- environments/dev/key-vault/: platform Key Vault
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
- CI `plan-*` / `apply_*` steps extracted into a `.github/actions/tf-stack`
  composite action — one definition for all six jobs instead of six copies.
- CI managed identities renamed `id-sap-dev-ci-plan` / `id-sap-dev-ci-apply`
  (were `sap-dev-ci-plan` / `sap-dev-ci-apply`) so they are not confused with
  the same-named Entra groups they belong to.
- `bootstrap/` creates the three per-stack resource groups
  (`rg-sap-dev-networking` / `-observability` / `-key-vault`) and every role
  assignment in the landing zone (the CI groups' per-resource-group `Reader` /
  `Contributor`, and `sap-dev-humans`' Key Vault Secrets Officer on the
  `key-vault` RG). The stacks read their resource group with a `data` source
  and make no role assignments; `networking` and `observability` take no
  input variables, `key-vault` keeps only `tfstate_storage_account_name`.
- `bootstrap/` registers the resource providers every stack needs
  (`resource_providers_to_register`); the stacks set
  `resource_provider_registrations = "none"` because their
  resource-group-scoped identities cannot register providers.
- The three Entra group object IDs are a `bootstrap/` input
  (`terraform.tfvars`), not GitHub repository variables — CI passes no group
  IDs to any stack, and the `tf-stack` composite action drops its three
  group-ID inputs.

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
- bootstrap: the CI identities are granted `Reader` / `Contributor` on each
  stack's resource group only, never a subscription-scoped role. An earlier
  iteration of `[Unreleased]` gave the apply identity subscription
  `Contributor` + `Role Based Access Control Administrator` to work around
  resource groups being created by the stacks themselves; moving
  resource-group creation into `bootstrap/` removed the need. See ADR 0002
  (`docs/decisions/0002-resource-groups-in-bootstrap.md`).
- environments/dev/key-vault: set `public_network_access_enabled = true`
  explicitly. The module defaults it to `false`, which made the vault
  private-endpoint-only and left the documented `network_acls` subnet
  restriction inert — ACLs are only evaluated on the public endpoint.
- bootstrap: added `storage_use_azuread = true` to the `azurerm` provider
  block. The tfstate storage account has `shared_access_key_enabled = false`,
  but the provider's post-create blob-service poll defaults to key auth and
  failed with `KeyBasedAuthenticationNotPermitted` on the first live apply.
- bootstrap: dropped the deprecated `resource_group_name` argument from the
  two `azurerm_federated_identity_credential` resources (redundant with
  `parent_id`), then renamed `parent_id` → `user_assigned_identity_id` ahead
  of its removal in AzureRM provider v5.
- ci: granted the `changes` job `pull-requests: read`. `dorny/paths-filter`
  falls back to the GitHub API's list-files call when the checkout is too
  shallow to diff locally, and that call 401'd ("Resource not accessible by
  integration") under the workflow's `contents: read`-only top-level
  permissions.
- bootstrap: built the OIDC federated-credential subjects with GitHub's
  immutable `owner@owner_id/repo@repo_id` format instead of plain names.
  Repositories created after GitHub's 2026-04-23 rollout get this baked into
  the token's `sub` claim; the plain-name subject never matched, 401ing the
  first live PR's `plan-networking` job with `AADSTS700213`.
- bootstrap: fixed the ci-apply federated credential's OIDC subject to
  `environment:dev-apply` instead of `ref:refs/heads/main`. Every `apply_*`
  job runs under the `dev-apply` GitHub Environment, so GitHub always mints
  an environment-scoped subject — the ref-scoped one could never match,
  401ing the first live `apply_networking` / `apply_observability` runs.
