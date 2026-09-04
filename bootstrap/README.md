# bootstrap

Real Terraform, **local state**, run **once by hand** — this is the
infrastructure that has to predate "clone and go" for every other stack:
the remote-state storage account, and the two OIDC app registrations CI
authenticates as.

## Prerequisites

- Personal Azure subscription + Entra tenant, Global Admin (`plan/docs/status.md` user to-do).
- `az login` as that Global Admin.
- Terraform >= 1.6.

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
4. **Grant `Group.ReadWrite.All`** (admin-consented Microsoft Graph
   application permission) to the `sap-dev-ci-apply` app registration —
   tracked in `plan/docs/status.md`'s user to-do list. Azure RBAC roles
   don't cover Microsoft Graph objects, so without this the `identity`
   stack's own CI `apply` can't create/manage the Entra groups it owns.
   Portal: Entra ID → App registrations → `sap-dev-ci-apply` → API
   permissions → Add → Microsoft Graph → Application permissions →
   `Group.ReadWrite.All` → Grant admin consent.
5. **Create a GitHub Environment** named `dev-apply` (Settings →
   Environments) with required reviewers, and reference it from every
   `apply-*` job in `.github/workflows/ci.yml` (Task 7) — this is the
   "gated by branch protection and a GitHub Environment" property the
   design spec calls for.

## Teardown

Nothing here is meant to be torn down casually — deleting the storage
account destroys every other stack's state. If the whole landing zone is
being decommissioned, delete stacks in reverse dependency order first
(`key-vault` → `networking`/`observability` → `identity`), then
`terraform destroy` here last.
