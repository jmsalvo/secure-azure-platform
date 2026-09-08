# 0002 — Resource groups and CI role assignments created in bootstrap

- **Status:** Accepted
- **Date:** 2026-09-07

## Context

Each lifecycle-aligned stack (`networking`, `observability`, `key-vault`)
created its own `azurerm_resource_group` and, on that group, the
`azurerm_role_assignment` resources granting the three Entra groups their
roles (`sap-dev-humans` → Contributor, `sap-dev-ci-plan` → Reader,
`sap-dev-ci-apply` → Contributor).

For that to work from an empty subscription, the CI **apply** identity needed
rights no resource-group-scoped role can give:

- creating a resource group is `Microsoft.Resources/.../resourceGroups/write`,
  which exists only at subscription (or management-group) scope;
- creating the stack's own role assignments is
  `Microsoft.Authorization/roleAssignments/write`, which `Contributor`
  explicitly excludes.

`bootstrap/` therefore granted the apply identity **subscription-scoped**
`Contributor` + `Role Based Access Control Administrator`, and the plan
identity subscription `Reader`. A leaked apply token could reach every
resource in the subscription and grant itself any non-privileged role
anywhere. On a landing zone whose headline is least privilege that blast
radius read as an oversight even with a comment explaining it, and the
resource-group-scoped grants the stacks made via the Entra groups were dead
weight — the subscription grants dominated them.

## Decision

`bootstrap/` creates every resource group and every role assignment:

- one resource group per stack (`rg-sap-dev-networking`,
  `rg-sap-dev-observability`, `rg-sap-dev-key-vault`), alongside the existing
  `rg-sap-dev-bootstrap`;
- on each, the three Entra-group role assignments the stacks used to make;
- `Key Vault Secrets Officer` for `sap-dev-humans` on the `key-vault`
  resource group — data-plane access to the platform vault, scoped to the RG
  (which holds only that vault) because `bootstrap/` has no reference to a
  vault the `key-vault` stack has not created yet;
- resource-provider registration (`resource_providers_to_register`), because
  RP registration is a subscription-scoped action the stacks' identities can
  no longer perform.

The stacks stop creating resource groups and role assignments. Each reads its
resource group back with `data "azurerm_resource_group"` (name hardcoded,
matching `bootstrap/`).

The CI identities hold **no subscription-scoped role**. Via their Entra
groups they have, per stack resource group: plan → `Reader`, apply →
`Contributor`. Neither holds `Microsoft.Authorization/*/Write` anywhere — all
role assignments are made by `bootstrap/`, run by hand by a subscription
Owner.

## Rationale

- **Blast radius matches intent.** A leaked apply token reaches three named
  resource groups, not the subscription, and cannot grant roles.
- **The privileged operations have a human in the loop.** Resource-group
  creation, role assignment, and RP registration all happen in `bootstrap/`,
  run by an Owner — not in a pipeline authenticating as a standing identity.
- **The Entra group membership becomes load-bearing.** It is now the only
  thing granting the CI identities any Azure access; before, it was redundant.
- **One place for RBAC.** Every role assignment in the landing zone is in
  `bootstrap/main.tf`, next to the resource group it targets.

## Alternatives considered

- **Accept subscription `Contributor` for `dev` and document it**, deferring
  the restructure. Defensible for a throwaway environment and common in CAF
  deployments, but leaves the headline artifact with a subscription-wide
  automated identity, and the next milestone (`v0.6` zero-trust) is about pod
  identity, not this — so "later" had no home.
- **ABAC `conditions` on a subscription-scoped role assignment**, restricted
  to a resource-group-name pattern. `azurerm` support for role-assignment
  conditions is awkward and the expression language is easy to get subtly
  wrong; rejected as more fragile than moving the resource groups.
- **Stacks keep making their own role assignments**, with `bootstrap/`
  granting the apply identity per-RG `Role Based Access Control Administrator`
  so it can. Keeps "access declared in the stack" but puts an
  authorization-write role back on the CI identity for no gain over
  `bootstrap/` making the assignments directly.

## Consequences

- Adding a stack is a two-step change: add its resource-group name to
  `local.stack_resource_groups` in `bootstrap/main.tf` (the `for_each`
  role-assignment blocks then cover it), and a human re-runs `bootstrap/`
  before the stack's first CI run. Documented in `CONTRIBUTING.md`.
  Acceptable at `dev` scale; revisit if stack churn increases.
- `bootstrap/` takes the three Entra group object IDs as input variables, so
  the groups must exist before its `apply`. The runbook in
  `bootstrap/README.md` is reordered accordingly.
- The three `*_GROUP_OBJECT_ID` GitHub repository variables are no longer
  used — CI passes no group IDs to any stack. Delete them from repo settings
  (not a repo file).
- `bootstrap/`'s state owns the stack resource groups. `terraform destroy` in
  a stack removes the resources *in* its group; the group is removed by
  `terraform destroy` in `bootstrap/`, last. Destroy stacks first so their
  state does not go stale.
- ADR 0001's lifecycle-aligned **state** split is unchanged: one state file
  per stack, one resource group per stack, the stack's state owns everything
  in that group. Only the group's *creation* and its RBAC move out.

## Supersedes

The 2026-09-06 amendment to [ADR 0001](0001-lifecycle-aligned-stacks.md) on
two points: group object IDs are a `bootstrap/` input, not a per-stack GitHub
repository variable; and the per-group role assignments are made by
`bootstrap/`, not "by each owning stack against its own resource group".
