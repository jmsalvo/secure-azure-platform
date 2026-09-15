# bootstrap

Real Terraform, **local state**, run **once by hand** — this is the
infrastructure that has to predate "clone and go" for every other stack:

- the remote-state storage account;
- the two managed identities (`id-sap-dev-ci-plan`, `id-sap-dev-ci-apply`)
  CI authenticates as via GitHub OIDC (the `id-` prefix keeps them distinct
  from the same-suffixed Entra groups they belong to);
- **one resource group per stack** (`rg-sap-dev-networking`,
  `rg-sap-dev-observability`, `rg-sap-dev-key-vault`, `rg-sap-dev-aks`) and
  **every role
  assignment** in the landing zone — the CI groups' `Reader` / `Contributor`
  per resource group, and `sap-dev-humans`' Key Vault data-plane role. The
  stacks create resources *inside* their group but neither create the group
  nor assign roles, so the CI identities never need a subscription-scoped
  role. See [ADR 0002](../docs/decisions/0002-resource-groups-in-bootstrap.md).

## Prerequisites

- An Azure subscription you are **Owner** of — bootstrap assigns roles and
  registers resource providers, both subscription-scoped actions. Separate
  from any Entra directory role; you do **not** need one.
- **The three Entra groups already created**, with you an owner of each — see
  step 1. Their object IDs are inputs to `terraform apply` here, so this must
  happen first.
- `az login`, Terraform >= 1.6.

## Run it

### 1. Entra groups — directory admin, one-time

The admin creates three **assigned, cloud-only security groups** —
`sap-dev-humans`, `sap-dev-ci-plan`, `sap-dev-ci-apply` — (not dynamic:
membership is hand-managed; not on-prem-synced) and makes **you an owner** of
each. That is the admin's entire involvement — nothing in this repo writes to
the directory.

### 2. Fill in `terraform.tfvars`

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
```

Set `github_repository` if the repo isn't `jmsalvo/secure-azure-platform`,
and the three group object IDs (you are a group owner, so you can read them):

```bash
az ad group show --group sap-dev-humans   --query id -o tsv
az ad group show --group sap-dev-ci-plan  --query id -o tsv
az ad group show --group sap-dev-ci-apply --query id -o tsv
```

### 3. Apply

```bash
terraform init
terraform apply
```

`apply` is idempotent — re-run it if the first pass hits a transient Azure
error (role-assignment propagation, storage-account provisioning, or a
resource-provider registration still completing; `Microsoft.Insights`,
`Microsoft.KeyVault`, and `Microsoft.OperationalInsights` are registered
here, which can take a minute on a fresh subscription).

## After `apply` — manual steps, in order

1. **Add the CI identities to their groups** (as a group owner — no directory
   role needed):

   ```bash
   az ad group member add --group sap-dev-humans   --member-id "$(az ad signed-in-user show --query id -o tsv)"
   az ad group member add --group sap-dev-ci-plan  --member-id "$(terraform output -raw ci_plan_principal_id)"
   az ad group member add --group sap-dev-ci-apply --member-id "$(terraform output -raw ci_apply_principal_id)"
   ```

   A freshly created managed-identity principal can lag directory
   replication — if `member add` reports it "does not exist", wait a minute
   and retry.

2. **Copy `tfstate_storage_account_name`** into the `storage_account_name`
   field of every `environments/dev/<stack>/backend.hcl` (they ship a
   `REPLACE_AFTER_BOOTSTRAP` placeholder). Commit the real value — it's an
   account name, not a secret.

3. **Set GitHub repository variables** (Settings → Secrets and variables →
   Actions → Variables — non-secret identifiers, safe as `vars`):

   ```bash
   gh variable set ARM_TENANT_ID       --body "$(terraform output -raw tenant_id)"
   gh variable set ARM_SUBSCRIPTION_ID --body "$(terraform output -raw subscription_id)"
   gh variable set ARM_CLIENT_ID_PLAN  --body "$(terraform output -raw ci_plan_client_id)"
   gh variable set ARM_CLIENT_ID_APPLY --body "$(terraform output -raw ci_apply_client_id)"
   ```

   No group object IDs are set as repository variables — CI passes none to
   the stacks; `bootstrap/` is the only consumer and reads them from
   `terraform.tfvars`.

4. **Create a GitHub Environment** named `dev-apply` (Settings → Environments)
   with required reviewers. Already referenced by the `apply_*` jobs in
   `.github/workflows/ci.yml`.

> **Cross-check:** `terraform output stack_resource_group_names` should list
> exactly the three names each stack hardcodes in its
> `data "azurerm_resource_group" "this"` block — a quick check that the
> literals and `bootstrap/` have not drifted.

## Defender for Containers (optional)

Off by default. To turn it on briefly (e.g. to capture evidence of a
Defender finding), set `enable_defender_for_containers = true` in
`terraform.tfvars`, `terraform apply`, capture what you need, then set it
back to `false` and `terraform apply` again. It's subscription-wide and
roughly doubles the running `aks` cluster's cost while on — see the `v0.2`
design spec's cost summary.

## Teardown

Deleting the storage account destroys every other stack's state, and
`terraform destroy` here also deletes the stack resource groups (Azure
cascade-deletes everything in them). Destroy the stacks first, in reverse
dependency order (`key-vault` → `networking` / `observability`), so their
state does not go stale, then `terraform destroy` here. The Entra groups are
the directory admin's to remove.

One trap before you destroy the `key-vault` stack: the pinned `key-vault`
module defaults to `purge_protection_enabled = true` and
`soft_delete_retention_days = 90`, so `terraform destroy` leaves a
soft-deleted vault that **cannot be purged** and blocks recreating a vault
with the same (deterministic) name for 90 days.
