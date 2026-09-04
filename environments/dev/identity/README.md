# identity

Creates the three Entra RBAC groups every other stack assigns roles to. No
ARM resources, no resource group — Entra ID groups are Microsoft Graph
objects, outside the ARM resource hierarchy.

No dependencies; applies first (see root README's stack dependency
diagram).

## Inputs

`human_operator_object_id` — your own Entra object ID (`az ad signed-in-user
show --query id -o tsv`). `ci_plan_service_principal_object_id` /
`ci_apply_service_principal_object_id` — from `bootstrap`'s outputs, copied
in by hand (see `bootstrap/README.md`).

## First apply

Needs the `Group.ReadWrite.All` admin-consented Graph permission on the
`sap-dev-ci-apply` app registration granted first (`bootstrap/README.md`
step 4) — Azure RBAC doesn't cover Graph objects, so without it this
stack's CI `apply` can't create/manage these groups.
