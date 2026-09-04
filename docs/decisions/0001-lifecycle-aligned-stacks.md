# 0001 — Lifecycle-aligned Terraform stacks, not one state per environment

- **Status:** Accepted
- **Date:** 2026-09-01

## Context

Every resource in this landing zone lives in one `dev` environment. The
naive split is one Terraform state file per environment. But the resources
within `dev` don't share a lifecycle: an Entra group and a Key Vault change
for completely different reasons, at completely different times, and a
single shared state file would force every `apply` to consider all of them
together — the wrong blast radius for a change to any one of them.

## Decision

One state file per **lifecycle-aligned stack**, per environment, under
`environments/<env>/<stack>/`:

- `identity/` — three Entra groups. No dependencies.
- `networking/` — VNet, subnets. Depends on `identity` (assigns RBAC roles to
  its groups on its own resource group).
- `observability/` — Log Analytics workspace. Same dependency shape as
  `networking`.
- `key-vault/` — the platform Key Vault. Depends on all three above (subnet
  ID, group object IDs, workspace ID).

Stacks reference each other's outputs via native `terraform_remote_state`
data sources. No Terragrunt or Terraform Stacks — the dependency graph here
is four nodes deep at most, and native Terraform expresses that with nothing
extra to install or learn.

## Rationale

- **Blast radius matches intent.** A `key-vault` network-rule change cannot
  accidentally touch the VNet; an `identity` group-membership change cannot
  accidentally touch a resource group's RBAC (only the stack that assigns a
  role can drift that assignment, and only when that stack itself changes).
- **Independent apply cadence.** `identity` changes rarely (new group, new
  member); `key-vault` may change often (new secret consumer, network rule
  tweak). Coupling their state would force one's noise onto the other.
- **Matches the resource-container boundary.** Every stack with ARM
  resources gets exactly one resource group; the Terraform state boundary
  and the resource-group boundary are the same boundary everywhere they both
  exist.

## Alternative: one state file per environment

Simpler to set up (one backend config, one `apply`), and fine at very small
scale. Rejected here because the stacks already have genuinely different
change frequencies and blast-radius requirements even at four stacks — the
coarse split would have been the wrong default to carry into `v0.2` onward,
where the stack count only grows (`aks/` at `v0.2`, likely `policy/` at
`v0.4`).

## Consequences

- Four `terraform init`/`plan`/`apply` cycles instead of one — more moving
  parts in CI (see root `README.md`'s job graph), but each cycle is smaller
  and safer.
- Cross-stack references go through `terraform_remote_state`, which means a
  downstream stack's `plan` needs the upstream stack's state to already
  exist in the remote backend — not just its code to exist in this PR's
  diff. First-time rollout order matters (see root `README.md`).

## Revisit when

The stack count grows enough (roughly eight-plus) or a second CI system
enters the picture that hand-maintained `needs:` chains in one workflow stop
being the more legible option — at that point, Terragrunt or Terraform
Stacks becomes worth the added tooling.
