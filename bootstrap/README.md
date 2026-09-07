# bootstrap

Real Terraform, **local state**, run **once by hand** — this is the
infrastructure that has to predate "clone and go" for every other stack:
the remote-state storage account, and the two managed identities
(`id-sap-dev-ci-plan`, `id-sap-dev-ci-apply`) CI authenticates as via GitHub
OIDC. The `id-` prefix keeps them distinct from the same-suffixed Entra
groups they are members of.

## Prerequisites

- An Azure subscription you are **Owner** of (needed to assign the
  subscription-scoped roles this config grants the CI identities). Subscription
  Owner is separate from any Entra directory role — you do **not** need a
  directory admin role for anything in this file.
- The three Entra groups already created by a directory admin — see step 2.
  `bootstrap` itself does not touch the directory, so this can happen before or
  after `terraform apply`, but the groups must exist before CI can run.
- `az login`.
- Terraform >= 1.6.

## Run it

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # edit if the repo isn't jmsalvo/secure-azure-platform
terraform init
terraform apply
```

`terraform apply` here is idempotent — if the first run hits a transient Azure
error (role assignment propagation or storage account provisioning), just
re-run it.

## After `apply` — manual steps, in order

1. **Copy `tfstate_storage_account_name`** into the `storage_account_name`
   field of every `environments/dev/<stack>/backend.hcl` file (they ship with
   a `REPLACE_AFTER_BOOTSTRAP` placeholder). Commit the real value — it's an
   account name, not a secret.
2. **Entra groups — directory admin, one-time.** The admin creates three
   **assigned, cloud-only security groups** — `sap-dev-humans`,
   `sap-dev-ci-plan`, `sap-dev-ci-apply` — (not dynamic: membership is hand
   managed; not on-prem-synced: membership lives in Entra) and makes **you an
   owner** of each. That is the admin's entire involvement.

   Then, as a group owner (no directory role required), add the members:

   ```bash
   az ad group member add --group sap-dev-humans   --member-id "$(az ad signed-in-user show --query id -o tsv)"
   az ad group member add --group sap-dev-ci-plan  --member-id "$(terraform output -raw ci_plan_principal_id)"
   az ad group member add --group sap-dev-ci-apply --member-id "$(terraform output -raw ci_apply_principal_id)"
   ```

   A freshly created managed-identity principal can lag directory
   replication — if `member add` reports the principal "does not exist", wait
   a minute and retry.

   No Microsoft Graph application permission and no admin consent is needed
   anywhere: nothing in this repo writes to the directory.
3. **Set GitHub repository variables** (Settings → Secrets and variables →
   Actions → Variables — non-secret identifiers, safe as `vars`, not
   `secrets`):

   ```bash
   gh variable set ARM_TENANT_ID       --body "$(terraform output -raw tenant_id)"
   gh variable set ARM_SUBSCRIPTION_ID --body "$(terraform output -raw subscription_id)"
   gh variable set ARM_CLIENT_ID_PLAN  --body "$(terraform output -raw ci_plan_client_id)"
   gh variable set ARM_CLIENT_ID_APPLY --body "$(terraform output -raw ci_apply_client_id)"
   ```

   The `networking`, `observability`, and `key-vault` stacks each need the
   three Entra group object IDs, passed by CI as `-var` flags. Get them from
   the directory admin, or read them yourself as a group owner (from step 2):

   ```bash
   gh variable set HUMANS_GROUP_OBJECT_ID   --body "$(az ad group show --group sap-dev-humans   --query id -o tsv)"
   gh variable set CI_PLAN_GROUP_OBJECT_ID  --body "$(az ad group show --group sap-dev-ci-plan  --query id -o tsv)"
   gh variable set CI_APPLY_GROUP_OBJECT_ID --body "$(az ad group show --group sap-dev-ci-apply --query id -o tsv)"
   ```
4. **Create a GitHub Environment** named `dev-apply` (Settings →
   Environments) with required reviewers. It is already referenced by the
   `apply_networking` / `apply_observability` / `apply_key_vault` jobs in
   `.github/workflows/ci.yml`.

## Teardown

Nothing here is meant to be torn down casually — deleting the storage account
destroys every other stack's state. If the whole landing zone is being
decommissioned, delete stacks in reverse dependency order first
(`key-vault` → `networking` / `observability`), then `terraform destroy` here.
The Entra groups are the directory admin's to remove.

One trap worth knowing before you destroy the `key-vault` stack: the pinned
`key-vault` module defaults to `purge_protection_enabled = true` and
`soft_delete_retention_days = 90`, so `terraform destroy` leaves a
soft-deleted vault behind that **cannot be purged** and blocks recreating a
vault with the same name for the full 90 days. Vault names are deterministic
(`module.naming`), so a destroy/recreate cycle in `dev` will fail on name
collision until the retention window expires.
