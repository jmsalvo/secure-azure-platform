# bootstrap

Real Terraform, **local state**, run **once by hand** — this is the
infrastructure that has to predate "clone and go" for every other stack:
the remote-state storage account, and the two OIDC app registrations CI
authenticates as.

## Prerequisites

- Personal Azure subscription + Entra tenant, Global Admin (`plan/docs/status.md` user to-do).
- `az login` as that Global Admin.
- Terraform >= 1.6.
- A principal with `Microsoft.Authorization/roleAssignments/write` **at
  subscription scope** — this config hands the CI identities subscription-scoped
  roles, which only a subscription `Owner` or `User Access Administrator` can
  grant. Entra **Global Admin is not automatically either of those**: a personal
  tenant's Global Admin has no Azure RBAC on the subscription until it's given
  some. If `terraform apply` here fails with `AuthorizationFailed` on a
  `roleAssignments/write` action, elevate once, out of band, then re-run:

  ```bash
  # one-time, from the Entra "Access management for Azure resources" toggle
  # (Entra ID → Properties) or an existing Owner:
  az role assignment create \
    --assignee "$(az ad signed-in-user show --query id -o tsv)" \
    --role Owner \
    --scope "/subscriptions/$(az account show --query id -o tsv)"
  ```

## Run it

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # edit if the repo isn't jmsalvo/secure-azure-platform
terraform init
terraform apply
```

## After `apply` — manual steps, in order

1. **Copy `tfstate_storage_account_name`** into the `storage_account_name`
   field of every `environments/dev/<stack>/backend.hcl` file (they ship
   with a `REPLACE_AFTER_BOOTSTRAP` placeholder). Commit the real value —
   it's an account name, not a secret.
2. **Set GitHub repository variables** (Settings → Secrets and variables →
   Actions → Variables — these are non-secret identifiers, safe as `vars`,
   not `secrets`):

   ```bash
   gh variable set ARM_TENANT_ID --body "$(terraform output -raw tenant_id)"
   gh variable set ARM_SUBSCRIPTION_ID --body "$(terraform output -raw subscription_id)"
   gh variable set ARM_CLIENT_ID_PLAN --body "$(terraform output -raw ci_plan_client_id)"
   gh variable set ARM_CLIENT_ID_APPLY --body "$(terraform output -raw ci_apply_client_id)"
   ```

   The `identity` stack itself needs three more inputs that CI's `plan-identity`/
   `apply_identity` jobs pass as `-var` flags (Task 7) — none are secrets,
   so they're repo variables too, not `terraform.tfvars`:

   ```bash
   gh variable set IDENTITY_HUMAN_OPERATOR_OBJECT_ID --body "$(az ad signed-in-user show --query id -o tsv)"
   gh variable set IDENTITY_CI_PLAN_SP_OBJECT_ID --body "$(terraform output -raw ci_plan_service_principal_object_id)"
   gh variable set IDENTITY_CI_APPLY_SP_OBJECT_ID --body "$(terraform output -raw ci_apply_service_principal_object_id)"
   ```
3. **Copy the same three values** into
   `environments/dev/identity/terraform.tfvars` (from
   `terraform.tfvars.example`) for local runs — CI reads the repo variables
   above instead of this file (it's gitignored, so CI never sees it). See
   that stack's README.
4. **Grant the Microsoft Graph permissions** — both sub-steps are manual and
   Global-Admin-only.

   **4a. Grant `Group.ReadWrite.All`** (admin-consented Microsoft Graph
   application permission) to the `sap-dev-ci-apply` app registration —
   tracked in `plan/docs/status.md`'s user to-do list. Azure RBAC roles
   don't cover Microsoft Graph objects, so without this the `identity`
   stack's own CI `apply` can't create/manage the Entra groups it owns.
   Portal: Entra ID → App registrations → `sap-dev-ci-apply` → API
   permissions → Add → Microsoft Graph → Application permissions →
   `Group.ReadWrite.All` → Grant admin consent.

   **4b. Grant `Group.Read.All`** (admin-consented Microsoft Graph
   application permission) to the `sap-dev-ci-plan` app registration — same
   portal path, just the other app and the read-only permission.
   `plan-identity` runs as `ARM_CLIENT_ID_PLAN` and has to refresh
   `azuread_group` / `azuread_group_member` state through Microsoft Graph;
   without this, every PR touching `environments/dev/identity/**` fails at
   `plan`. Like 4a this is manual and Global-Admin-only: Graph application
   permissions aren't Azure RBAC, so nothing a lesser-privileged CI identity
   runs can grant them.
5. **Create a GitHub Environment** named `dev-apply` (Settings →
   Environments) with required reviewers, and reference it from the four
   `apply_identity` / `apply_networking` / `apply_observability` /
   `apply_key_vault` jobs in `.github/workflows/ci.yml` (Task 7) — this is
   the "gated by branch protection and a GitHub Environment" property the
   design spec calls for.

## Teardown

Nothing here is meant to be torn down casually — deleting the storage
account destroys every other stack's state. If the whole landing zone is
being decommissioned, delete stacks in reverse dependency order first
(`key-vault` → `networking`/`observability` → `identity`), then
`terraform destroy` here last.

One trap worth knowing before you destroy the `key-vault` stack: the pinned
`key-vault` module defaults to `purge_protection_enabled = true` and
`soft_delete_retention_days = 90`, so `terraform destroy` leaves a
soft-deleted vault behind that **cannot be purged** and blocks recreating a
vault with the same name for the full 90 days. Vault names are
deterministic (`module.naming`), so a destroy/recreate cycle in `dev` will
fail on name collision until the retention window expires.
