# Changelog

All notable changes to this repo are documented here.

## [Unreleased]

### Added

- bootstrap/: one-time state storage account + OIDC app registrations for CI
- environments/dev/identity/: the three Entra RBAC groups
- environments/dev/networking/: VNet, subnet, RBAC role assignments
- environments/dev/observability/: Log Analytics workspace, RBAC role assignments
- environments/dev/key-vault/: platform Key Vault, RBAC role assignments
- .github/workflows/ci.yml: OIDC-authenticated per-stack plan/apply CI, dependency-ordered

### Fixed

- bootstrap: suppress AVD-AZU-0012 (public network access) on the tfstate
  storage account with a documented inline ignore — GitHub-hosted CI
  runners have no stable IP range to restrict to; Entra ID/RBAC-only access
  (`shared_access_key_enabled = false`) is the accepted boundary.
