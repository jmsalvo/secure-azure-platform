# CI Identity Blast Radius — Resource Groups & RBAC into `bootstrap/` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move resource-group creation, every Azure role assignment, and
resource-provider registration out of the three stacks and into `bootstrap/`,
so the CI OIDC identities hold no subscription-scoped role — only
per-resource-group `Reader` (plan) / `Contributor` (apply) via their Entra
groups.

**Architecture:** `bootstrap/` (run by hand by a subscription Owner) already
creates `rg-sap-dev-bootstrap`, the state storage account, and the two CI
managed identities. It gains: one resource group per stack
(`rg-sap-dev-networking`, `-observability`, `-key-vault`), the per-group role
assignments each stack used to make on itself, `sap-dev-humans`' Key Vault
data-plane role on the `key-vault` RG, and `resource_providers_to_register`
for the providers the stacks need. It drops the three subscription-scoped
role assignments (`Reader`, `Contributor`, `Role Based Access Control
Administrator`). Each stack replaces `resource "azurerm_resource_group"` with
`data "azurerm_resource_group"`, deletes its `azurerm_role_assignment`
resources and the now-unused group-object-id variables, and sets
`resource_provider_registrations = "none"`. CI stops passing group IDs to any
stack. Recorded as ADR 0002.

**Tech Stack:** Terraform >= 1.6 (CI/local pinned 1.16.0), `azurerm` provider
`~> 4.0` only, GitHub Actions with OIDC, a `.github/actions/tf-stack`
composite action, tflint + azurerm ruleset, trivy config scan, `gh` CLI,
`scripts/check.ps1` for credential-free local checks.

**Spec:** `docs/superpowers/specs/2026-09-02-v0.1-landing-zone-design.md`
(this plan adds the 2026-09-07 amendment — Task 4).

## Global Constraints

- Modules stay pinned: `source = "github.com/jmsalvo/terraform-azure-modules//modules/<name>?ref=v0.1.0"` — never `?ref=main`.
- One Terraform state file per stack; cross-stack references only via `terraform_remote_state`. A stack's own resource group is **not** a cross-stack reference — it is read with `data "azurerm_resource_group"`, name hardcoded, matching the name `bootstrap/` creates.
- No stored Azure client secret anywhere — OIDC / `az login` only.
- No Microsoft Graph writes and no `azuread` provider anywhere. The three Entra groups (`sap-dev-humans`, `sap-dev-ci-plan`, `sap-dev-ci-apply`) are created and membership-managed by a directory admin outside this repo, as assigned cloud-only security groups.
- **After this change the CI identities hold no subscription-scoped role.** Every `azurerm_role_assignment` in the repo lives in `bootstrap/main.tf`. The plan identity's group gets `Reader` per stack RG; the apply identity's group gets `Contributor` per stack RG; neither gets `Microsoft.Authorization/*/Write` anywhere.
- Group → role mapping is unchanged in intent: `sap-dev-humans` = `Contributor` (+ `Key Vault Secrets Officer` on the `key-vault` RG), `sap-dev-ci-plan` = `Reader`, `sap-dev-ci-apply` = `Contributor` — all now assigned by `bootstrap/`, per resource group.
- Apply order is unchanged: `networking` and `observability` in parallel (no upstream stack) → `key-vault` last (depends on both).
- `workload = "sap"`, `environment = "dev"`, `location = "eastus2"` across every config.
- Nothing here can `terraform apply` for real yet — the tenant rollout is a later step. Every task's deliverable is `scripts/check.ps1` (`terraform fmt` / offline `validate` / `tflint` / `trivy`, all credential-free) passing, plus targeted greps, plus a YAML sanity check on `ci.yml` for the CI task. `terraform validate` does not evaluate data sources or register providers, so the credential-free story is intact.
- **Execution environment note:** the scoop shims directory `C:\Users\Jenni\scoop\shims` (holding `terraform`, `tflint`, `trivy`) is not always on `PATH` in a sandboxed session. If a tool is "not found", prepend that directory to `PATH` for the command. Shell state does not persist between tool calls.

---

## Cold-start walkthrough

The design rationale is that this sequence works from an empty subscription
with **no subscription-scoped grant on any CI identity**. Verified on paper
during planning; re-check it if any task deviates.

**Preconditions:** the operator is subscription **Owner**; a directory admin
will create three Entra groups.

1. **Directory admin** creates `sap-dev-humans` / `sap-dev-ci-plan` /
   `sap-dev-ci-apply` (assigned, cloud-only security groups) and makes the
   operator an owner of each. *(Unchanged, except it must now precede
   `bootstrap/` — its object IDs are a bootstrap input.)*
2. **Operator** reads the three group object IDs (`az ad group show`) into
   `bootstrap/terraform.tfvars`.
3. **Operator** runs `terraform apply` in `bootstrap/` **as Owner**. This:
   - registers `Microsoft.KeyVault` / `Microsoft.OperationalInsights` /
     `Microsoft.Network` / `Microsoft.Storage` / `Microsoft.ManagedIdentity`
     (subscription-scoped — Owner can; the stacks' identities cannot);
   - creates `rg-sap-dev-bootstrap`, the state storage account + container;
   - creates the two user-assigned identities + federated credentials, and
     each identity's blob-data role on the state account;
   - creates `rg-sap-dev-networking`, `rg-sap-dev-observability`,
     `rg-sap-dev-key-vault`;
   - assigns, per stack RG: `sap-dev-humans` → `Contributor`,
     `sap-dev-ci-plan` → `Reader`, `sap-dev-ci-apply` → `Contributor`;
   - assigns `sap-dev-humans` → `Key Vault Secrets Officer` on
     `rg-sap-dev-key-vault` (data-plane access to the platform vault; RG
     scope because the vault does not exist yet and the RG holds only it);
   - **makes no subscription-scoped role assignment.**
4. **Operator** adds the identity principals to the plan/apply groups (needs
   `ci_plan_principal_id` / `ci_apply_principal_id` outputs); sets GitHub repo
   variables (`ARM_*` only — no group IDs); creates the `dev-apply`
   environment; writes the state account name into the three `backend.hcl`
   and commits.
5. **PR touching `networking/` + `observability/`** → `plan-*` jobs run as
   `id-sap-dev-ci-plan` (member of `sap-dev-ci-plan` → `Reader` on those RGs;
   `Storage Blob Data Reader` on state). `terraform plan`:
   - `data "azurerm_resource_group" "this"` resolves — RG exists, `Reader`
     can read it;
   - the provider does **not** attempt RP registration
     (`resource_provider_registrations = "none"`);
   - plans VNet / subnet / NSG / workspace — read-only, fine.
6. **Merge** → `apply_*` jobs run as `id-sap-dev-ci-apply` (`Contributor` on
   those RGs; `Storage Blob Data Contributor` on state). `terraform apply`
   creates the resources in the RG (`Contributor`) and writes state. No role
   assignment is created by the stack, so no `Microsoft.Authorization`
   permission is needed.
7. **PR + merge touching `key-vault/`** → same, plus it reads `networking` /
   `observability` remote state (blob-data role on the state account). The
   vault's data-plane access for humans was already granted at RG scope in
   step 3, so the stack creates no role assignment.

**Failure modes checked:**

- *Group deleted / wrong ID when `bootstrap/` runs* → GUID `validation` catches
  a malformed value; a well-formed ID for a missing group fails the role
  assignment with `PrincipalNotFound` — re-run `apply` after the admin fixes
  it (same class the runbook already documents for the identities).
- *RP not registered + a stack applies* → would fail with
  `MissingSubscriptionRegistration`. Prevented by step 3 + `"none"` on the
  stacks.
- *Someone adds a 4th stack and forgets the `bootstrap/` entry* → that stack's
  `data "azurerm_resource_group" "this"` fails at plan time with
  "Resource Group ... was not found" — fails closed, no silent fallback.
  `CONTRIBUTING.md` documents the `bootstrap/` step.
- *`terraform validate` / `scripts/check.ps1`* → credential-free, no
  data-source evaluation, no RP registration → unaffected.

---

## Task 1: `bootstrap/` — resource groups, per-RG role assignments, RP registration; drop the subscription grants

**Files:**
- Modify: `bootstrap/variables.tf` (add three group-object-id variables with GUID validation)
- Modify: `bootstrap/versions.tf` (`resource_provider_registrations = "none"` + `resource_providers_to_register` list)
- Modify: `bootstrap/main.tf` (replace the `locals` block; replace the subscription-scoped role assignments with the stack RGs + `for_each` group role assignments + the Key Vault Secrets Officer grant)
- Modify: `bootstrap/outputs.tf` (add `stack_resource_group_names`)
- Modify: `bootstrap/terraform.tfvars.example` (add the three group IDs)

**Interfaces:**
- Consumes: `var.github_repository`, `var.location` (unchanged); `data.azurerm_client_config.current` (unchanged, declared in `versions.tf`); three new string vars `humans_group_object_id`, `ci_plan_group_object_id`, `ci_apply_group_object_id`.
- Produces: unchanged outputs (`tfstate_*`, `ci_plan_client_id`, `ci_plan_principal_id`, `ci_apply_client_id`, `ci_apply_principal_id`, `tenant_id`, `subscription_id`) plus new `stack_resource_group_names` (list of string). Task 2 relies on the resource-group **names** `rg-sap-dev-networking` / `rg-sap-dev-observability` / `rg-sap-dev-key-vault` existing; Task 3 relies on nothing new here.

- [ ] **Step 1: Add the three group-object-id variables to `bootstrap/variables.tf`**

Append to the existing file (which ends after the `github_repository`
variable):

```hcl

variable "humans_group_object_id" {
  description = "Object ID of the admin-precreated sap-dev-humans Entra group. Same value as the HUMANS_GROUP_OBJECT_ID GitHub repo variable used before 2026-09-07; now a bootstrap-only input."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.humans_group_object_id))
    error_message = "humans_group_object_id must be a GUID."
  }
}

variable "ci_plan_group_object_id" {
  description = "Object ID of the admin-precreated sap-dev-ci-plan Entra group."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.ci_plan_group_object_id))
    error_message = "ci_plan_group_object_id must be a GUID."
  }
}

variable "ci_apply_group_object_id" {
  description = "Object ID of the admin-precreated sap-dev-ci-apply Entra group."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.ci_apply_group_object_id))
    error_message = "ci_apply_group_object_id must be a GUID."
  }
}
```

- [ ] **Step 2: Set `resource_provider_registrations` in `bootstrap/versions.tf`**

Replace the `provider "azurerm"` block (currently `provider "azurerm" {
features {} }`) with:

```hcl
provider "azurerm" {
  features {}

  # The stacks run with resource-group-scoped identities that cannot register
  # resource providers (a subscription-scoped action). bootstrap runs as a
  # subscription Owner and registers every provider any stack needs, once.
  # "none" means *only* the list below is registered — Microsoft.Network /
  # Storage / ManagedIdentity are in the provider's "core" set but must still
  # be listed here; KeyVault and OperationalInsights are not in "core".
  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.Storage",
  ]
}
```

Leave `terraform {}` and the `data "azurerm_client_config" "current" {}` line
unchanged.

- [ ] **Step 3: Replace the `locals` block at the top of `bootstrap/main.tf`**

Current lines 1–3 are:

```hcl
locals {
  subscription_scope = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
}
```

Replace with:

```hcl
locals {
  # Resource groups for the three lifecycle-aligned stacks. Created here in
  # bootstrap, not by the stacks themselves: a stack that created its own
  # resource group would force the CI apply identity to hold a
  # subscription-scoped role to make the first one. Creating them here keeps
  # every CI grant resource-group-scoped. See docs/decisions/0002-resource-groups-in-bootstrap.md.
  stack_resource_groups = toset([
    "rg-sap-dev-networking",
    "rg-sap-dev-observability",
    "rg-sap-dev-key-vault",
  ])
}
```

- [ ] **Step 4: Replace the subscription-scoped role assignments in `bootstrap/main.tf`**

Leave everything from `module "naming"` through
`resource "azurerm_role_assignment" "tfstate_ci_apply_write"` (the two
`Storage Blob Data *` grants on the state account) **unchanged**.

Delete the rest of the file — the comment block starting `# Blob access to the
state account only gets CI as far as reading/writing` and the three resources
`subscription_ci_plan_read`, `subscription_ci_apply_contribute`,
`subscription_ci_apply_rbac_admin` — and replace it with:

```hcl
# The three lifecycle-aligned stacks own the resources *inside* one of these
# groups but do not create the group — they read it back with a data source.
# bootstrap creates it so no CI identity ever needs a subscription-scoped role.
resource "azurerm_resource_group" "stack" {
  for_each = local.stack_resource_groups
  name     = each.value
  location = var.location
  tags     = module.naming.tags
}

# Per-resource-group grants to the admin-managed Entra groups, replacing the
# subscription-scoped Reader / Contributor / RBAC Administrator grants this
# file used to make. The CI identities are members of the plan / apply groups
# (see README); a leaked apply token now reaches three named resource groups,
# not the whole subscription, and cannot create role assignments.
resource "azurerm_role_assignment" "stack_humans_contributor" {
  for_each             = azurerm_resource_group.stack
  scope                = each.value.id
  role_definition_name = "Contributor"
  principal_id         = var.humans_group_object_id
  principal_type       = "Group"
}

resource "azurerm_role_assignment" "stack_ci_plan_reader" {
  for_each             = azurerm_resource_group.stack
  scope                = each.value.id
  role_definition_name = "Reader"
  principal_id         = var.ci_plan_group_object_id
  principal_type       = "Group"
}

resource "azurerm_role_assignment" "stack_ci_apply_contributor" {
  for_each             = azurerm_resource_group.stack
  scope                = each.value.id
  role_definition_name = "Contributor"
  principal_id         = var.ci_apply_group_object_id
  principal_type       = "Group"
}

# Data-plane access to the platform Key Vault for human operators. The vault
# is created by the key-vault stack; granting Key Vault Secrets Officer on its
# resource group (which holds only that vault) reaches it without bootstrap
# referencing a resource that does not exist yet, and keeps every role
# assignment in this file. The key-vault module sets
# enable_rbac_authorization = true, so an RG-scoped data-plane role inherits
# to the vault.
resource "azurerm_role_assignment" "key_vault_humans_secrets_officer" {
  scope                = azurerm_resource_group.stack["rg-sap-dev-key-vault"].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.humans_group_object_id
  principal_type       = "Group"
}
```

- [ ] **Step 5: Add the `stack_resource_group_names` output to `bootstrap/outputs.tf`**

Append:

```hcl

output "stack_resource_group_names" {
  description = "Resource groups bootstrap created for the lifecycle-aligned stacks. Each stack reads its own back with a data source."
  value       = sort([for rg in azurerm_resource_group.stack : rg.name])
}
```

- [ ] **Step 6: Update `bootstrap/terraform.tfvars.example`**

Full new content:

```hcl
github_repository        = "jmsalvo/secure-azure-platform"
humans_group_object_id   = "00000000-0000-0000-0000-000000000000"
ci_plan_group_object_id  = "00000000-0000-0000-0000-000000000000"
ci_apply_group_object_id = "00000000-0000-0000-0000-000000000000"
```

- [ ] **Step 7: Verify**

```bash
terraform -chdir=bootstrap fmt
./scripts/check.ps1
```
Expected: `All checks passed.`

```bash
git grep -n 'local.subscription_scope\|subscription_ci_' -- bootstrap
git grep -n 'Role Based Access Control Administrator' -- bootstrap
```
Expected: no matches for either — the subscription-scoped assignments and the
RBAC Administrator role are gone from `bootstrap/`.

```bash
git grep -n 'azurerm_resource_group.stack\|resource_providers_to_register' -- bootstrap
```
Expected: matches in `main.tf` (the `for_each` RG + role assignments) and
`versions.tf` (the provider list).

- [ ] **Step 8: Commit**

```bash
git add bootstrap
git commit -m "feat(bootstrap): own the stack resource groups and all RBAC; drop subscription-scoped CI grants"
```

---

## Task 2: The three stacks — read the resource group as a data source; delete role assignments and group variables

**Files:**
- Modify: `environments/dev/networking/{versions.tf,variables.tf,main.tf}`
- Modify: `environments/dev/observability/{versions.tf,variables.tf,main.tf}`
- Modify: `environments/dev/key-vault/{versions.tf,variables.tf,main.tf,terraform.tfvars.example}`
- Delete: `environments/dev/networking/terraform.tfvars.example`, `environments/dev/observability/terraform.tfvars.example` (nothing left to exemplify — those stacks take no variables)

**Interfaces:**
- Consumes: the resource groups `rg-sap-dev-networking` / `rg-sap-dev-observability` / `rg-sap-dev-key-vault` created in Task 1.
- Produces: unchanged stack outputs (`networking`: `vnet_id`, `platform_subnet_id`; `observability`: `log_analytics_workspace_id`; `key-vault`: `key_vault_id`, `key_vault_uri`). `networking` / `observability` now declare only `variable "location"`; `key-vault` declares `location` + `tfstate_storage_account_name`. No stack declares a group-object-id variable. Task 3 relies on the stacks no longer accepting `humans_group_object_id` / `ci_plan_group_object_id` / `ci_apply_group_object_id`.

- [ ] **Step 1: `resource_provider_registrations = "none"` in all three `versions.tf`**

In each of `environments/dev/networking/versions.tf`,
`environments/dev/observability/versions.tf`,
`environments/dev/key-vault/versions.tf`, replace the
`provider "azurerm" { features {} }` block with:

```hcl
provider "azurerm" {
  features {}

  # Resource providers are registered once by bootstrap (run as a
  # subscription Owner). This stack's CI identity is resource-group-scoped
  # and cannot register them. See docs/decisions/0002-resource-groups-in-bootstrap.md.
  resource_provider_registrations = "none"
}
```

- [ ] **Step 2: Strip `environments/dev/networking/variables.tf` to `location` only**

Full new content:

```hcl
variable "location" {
  description = "Azure region for this stack's resources."
  type        = string
  default     = "eastus2"
}
```

- [ ] **Step 3: Rewire `environments/dev/networking/main.tf`**

Replace the `resource "azurerm_resource_group" "networking"` block with a data
source:

```hcl
data "azurerm_resource_group" "this" {
  name = "rg-sap-dev-networking"
}
```

Change the networking module's `resource_group_name` argument from
`azurerm_resource_group.networking.name` to
`data.azurerm_resource_group.this.name`.

Delete the three `azurerm_role_assignment` resources at the end of the file
(`humans_contributor`, `ci_plan_reader`, `ci_apply_contributor`) and the blank
line before them. The file now ends with the closing `}` of
`module "networking"`.

- [ ] **Step 4: Strip `environments/dev/observability/variables.tf` to `location` only**

Full new content:

```hcl
variable "location" {
  description = "Azure region for this stack's resources."
  type        = string
  default     = "eastus2"
}
```

- [ ] **Step 5: Rewire `environments/dev/observability/main.tf`**

Replace the `resource "azurerm_resource_group" "observability"` block with:

```hcl
data "azurerm_resource_group" "this" {
  name = "rg-sap-dev-observability"
}
```

Change `azurerm_log_analytics_workspace.this`'s `resource_group_name` from
`azurerm_resource_group.observability.name` to
`data.azurerm_resource_group.this.name`.

Delete the three `azurerm_role_assignment` resources (`humans_contributor`,
`ci_plan_reader`, `ci_apply_contributor`) and the blank line before them. The
file now ends with the closing `}` of
`resource "azurerm_log_analytics_workspace" "this"`.

- [ ] **Step 6: Trim `environments/dev/key-vault/variables.tf`**

Full new content (keep `location` and `tfstate_storage_account_name`; drop the
three group vars and their `validation` blocks):

```hcl
variable "location" {
  description = "Azure region for this stack's resources."
  type        = string
  default     = "eastus2"
}

variable "tfstate_storage_account_name" {
  description = "Name of the bootstrap-created storage account holding remote state (bootstrap output tfstate_storage_account_name)."
  type        = string
}
```

- [ ] **Step 7: Rewire `environments/dev/key-vault/main.tf`**

Replace the `resource "azurerm_resource_group" "key_vault"` block with:

```hcl
data "azurerm_resource_group" "this" {
  name = "rg-sap-dev-key-vault"
}
```

Change `module "key_vault"`'s `resource_group_name` from
`azurerm_resource_group.key_vault.name` to
`data.azurerm_resource_group.this.name`.

Delete the four `azurerm_role_assignment` resources at the end of the file
(`humans_contributor`, `ci_plan_reader`, `ci_apply_contributor`, and
`humans_secrets_officer` with its preceding `# RG-level Contributor ...`
comment) and the blank line before them. The file now ends with the closing
`}` of `module "key_vault"`. Leave the `data "terraform_remote_state"` blocks
and `data "azurerm_client_config" "current"` untouched.

- [ ] **Step 8: Update `environments/dev/key-vault/terraform.tfvars.example`**

Full new content:

```hcl
# Copy to terraform.tfvars (gitignored) for local runs. CI passes
# tfstate_storage_account_name as a -var flag, read from backend.hcl. The
# Entra group object IDs are a bootstrap/ input, not a stack input.
tfstate_storage_account_name = "REPLACE_WITH_BOOTSTRAP_OUTPUT"
```

- [ ] **Step 9: Delete the two empty example files**

```bash
git rm environments/dev/networking/terraform.tfvars.example environments/dev/observability/terraform.tfvars.example
```

- [ ] **Step 10: Verify**

```bash
terraform -chdir=environments/dev/networking fmt
terraform -chdir=environments/dev/observability fmt
terraform -chdir=environments/dev/key-vault fmt
./scripts/check.ps1
```
Expected: `All checks passed.` (`terraform validate` fetches the git-sourced
`naming` / `networking` / `key-vault` modules over the network during
`init -backend=false`; it does not touch Azure.)

```bash
git grep -n 'azurerm_resource_group' -- environments
```
Expected: only `data "azurerm_resource_group" "this"` and
`data.azurerm_resource_group.this.*` — no `resource "azurerm_resource_group"`.

```bash
git grep -n 'azurerm_role_assignment\|group_object_id' -- environments
```
Expected: no matches — no stack creates a role assignment or declares a group
variable.

- [ ] **Step 11: Commit**

```bash
git add environments
git commit -m "refactor(stacks): read resource group via data source; drop RBAC and group vars"
```

---

## Task 3: CI — drop the group-ID inputs from the `tf-stack` action and its call sites

**Files:**
- Modify: `.github/actions/tf-stack/action.yml`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the stacks no longer accepting group-object-id variables (Task 2).
- Produces: a `tf-stack` action whose only stack input beyond `stack` / `mode` / `terraform-version` is the optional `needs-tfstate-storage-account`. No behaviour change to `fmt` / `validate` / `tflint` / `trivy` / `changes` or to the job graph.

- [ ] **Step 1: Rewrite `.github/actions/tf-stack/action.yml`**

Full new content:

```yaml
name: tf-stack
description: >-
  terraform init + plan/apply for one environments/dev/<stack>, with the
  shared wiring used by every plan-* / apply_* job in ci.yml. As of
  2026-09-07 the stacks take no group-object-id variables (bootstrap/ makes
  all role assignments); the only per-stack -var is tfstate_storage_account_name
  for the stack that reads another stack's remote state.

inputs:
  stack:
    description: Stack directory name under environments/dev/ (networking, observability, key-vault).
    required: true
  mode:
    description: '"plan" or "apply".'
    required: true
  terraform-version:
    description: Terraform version for hashicorp/setup-terraform.
    required: true
  needs-tfstate-storage-account:
    description: >-
      "true" for a stack that reads another stack's remote state (key-vault)
      and therefore declares the tfstate_storage_account_name variable. The
      value is read from the stack's backend.hcl so it lives in exactly one
      place.
    required: false
    default: "false"

runs:
  using: composite
  steps:
    - uses: hashicorp/setup-terraform@v3
      with:
        terraform_version: ${{ inputs.terraform-version }}
    # Azure auth (ARM_CLIENT_ID / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID /
    # ARM_USE_OIDC) is read by terraform from the process environment, which
    # the calling job supplies via its own env: block — job-level env is
    # inherited by composite-action run steps. OIDC token vars are runner-
    # injected per step wherever id-token: write is granted.
    - shell: bash
      working-directory: environments/dev/${{ inputs.stack }}
      env:
        MODE: ${{ inputs.mode }}
        NEEDS_TFSTATE_SA: ${{ inputs.needs-tfstate-storage-account }}
      run: |
        set -euo pipefail

        terraform init -backend-config=backend.hcl -lockfile=readonly

        var_args=()
        if [ "${NEEDS_TFSTATE_SA}" = "true" ]; then
          storage_account="$(grep -m1 storage_account_name backend.hcl | cut -d'"' -f2)"
          var_args+=(-var="tfstate_storage_account_name=${storage_account}")
        fi

        case "${MODE}" in
          plan)  terraform plan  -input=false -no-color "${var_args[@]}" ;;
          apply) terraform apply -input=false -auto-approve -no-color "${var_args[@]}" ;;
          *) echo "tf-stack: unknown mode '${MODE}' (want plan|apply)" >&2; exit 1 ;;
        esac
```

(GitHub `ubuntu-latest` runs bash 5.2, where `"${var_args[@]}"` on an empty
array is safe under `set -u`.)

- [ ] **Step 2: Remove the group-ID inputs from the six `tf-stack` calls in `.github/workflows/ci.yml`**

In each of `plan-networking`, `plan-observability`, `plan-key-vault`,
`apply_networking`, `apply_observability`, `apply_key_vault`, delete these
three lines from the `with:` block of the `uses: ./.github/actions/tf-stack`
step:

```yaml
          humans-group-object-id: ${{ vars.HUMANS_GROUP_OBJECT_ID }}
          ci-plan-group-object-id: ${{ vars.CI_PLAN_GROUP_OBJECT_ID }}
          ci-apply-group-object-id: ${{ vars.CI_APPLY_GROUP_OBJECT_ID }}
```

Leave every other `with:` key (`stack`, `mode`, `terraform-version`, and
`needs-tfstate-storage-account: "true"` on the two `key-vault` jobs) as is.

- [ ] **Step 3: Update the comment above `plan-networking` in `.github/workflows/ci.yml`**

Replace:

```yaml
  # plan-* / apply_* all share the same terraform wiring — see
  # .github/actions/tf-stack. Repo-variable values are passed as action inputs,
  # not interpolated into shell command text.
```

with:

```yaml
  # plan-* / apply_* all share the same terraform wiring — see
  # .github/actions/tf-stack. The stacks take no group-object-id variables
  # (bootstrap/ makes every role assignment); the only per-stack -var is
  # tfstate_storage_account_name, read from backend.hcl inside the action.
```

- [ ] **Step 4: Verify**

```bash
./scripts/check.ps1
```
Expected: `All checks passed.` (unchanged — CI files don't affect it).

```bash
python -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); yaml.safe_load(open('.github/actions/tf-stack/action.yml')); print('YAML OK')"
```
Expected: `YAML OK`. If PyYAML is unavailable, note it and rely on GitHub's
validation on first push.

```bash
git grep -n 'GROUP_OBJECT_ID\|group-object-id' -- .github
```
Expected: no matches.

- [ ] **Step 5: Commit**

```bash
git add .github
git commit -m "ci: stop passing group object IDs to stacks; bootstrap owns all RBAC"
```

---

## Task 4: Docs — ADR 0002, spec amendment, README, bootstrap runbook, CHANGELOG, CONTRIBUTING

**Files:**
- Create: `docs/decisions/0002-resource-groups-in-bootstrap.md`
- Modify: `docs/decisions/0001-lifecycle-aligned-stacks.md`
- Modify: `docs/superpowers/specs/2026-09-02-v0.1-landing-zone-design.md`
- Modify: `README.md`
- Modify: `bootstrap/README.md`
- Modify: `CHANGELOG.md`
- Modify: `CONTRIBUTING.md`

**Interfaces:**
- Consumes: nothing — records Tasks 1–3.
- Produces: nothing consumed by later work.

- [ ] **Step 1: Create `docs/decisions/0002-resource-groups-in-bootstrap.md`**

Full content:

```markdown
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
```

- [ ] **Step 2: Amend `docs/decisions/0001-lifecycle-aligned-stacks.md`**

Change the status line from:

```markdown
- **Status:** Accepted (amended 2026-09-06)
```

to:

```markdown
- **Status:** Accepted (amended 2026-09-06, 2026-09-07)
```

At the end of the `## Amendment — 2026-09-06` section (immediately before
`## Revisit when`), append:

```markdown

**Further amended 2026-09-07 ([ADR 0002](0002-resource-groups-in-bootstrap.md)):**
resource-group *creation* and the per-group role assignments moved from the
stacks into `bootstrap/`. The stacks read their resource group via a data
source and make no role assignments. The lifecycle-aligned **state** split —
one state file and one resource group per stack, the stack's state owning
everything in that group — is unchanged.
```

- [ ] **Step 3: Amend the spec — header + new amendment section**

In `docs/superpowers/specs/2026-09-02-v0.1-landing-zone-design.md`, change:

```markdown
- **Amended:** 2026-09-06 — see "Amendment" below.
```

to:

```markdown
- **Amended:** 2026-09-06, 2026-09-07 — see "Amendment" sections below.
```

Immediately after the existing `## Amendment — 2026-09-06 (change set A/B/C)`
section (before `## Context`), insert:

```markdown
## Amendment — 2026-09-07 (CI identity blast radius)

Planned in `docs/superpowers/plans/2026-09-07-ci-identity-rg-ownership.md`;
recorded as [ADR 0002](../../decisions/0002-resource-groups-in-bootstrap.md).

The `[Unreleased]` design had each stack create its own
`azurerm_resource_group` and its own per-group `azurerm_role_assignment`
resources, which forced the CI apply identity to hold subscription-scoped
`Contributor` + `Role Based Access Control Administrator`. Resource-group
creation and all role assignments move into `bootstrap/` (run by a
subscription Owner). The stacks read their resource group with
`data "azurerm_resource_group"` and make no role assignments. The CI
identities hold only per-resource-group `Reader` (plan) / `Contributor`
(apply) via their Entra groups — no subscription-scoped role anywhere. The
three group object IDs become a `bootstrap/` input rather than per-stack
GitHub repository variables. `bootstrap/` also registers the resource
providers the stacks need (`resource_providers_to_register`), since its
identities can no longer self-register.
```

- [ ] **Step 4: Amend the spec — inline section markers**

Under `## Resource groups`, immediately after the existing
`> **Amended 2026-09-06:** ...` blockquote, add:

```markdown

> **Further amended 2026-09-07:** the three resource groups are created by
> `bootstrap/`, not by their stacks; each stack reads its own back with a
> data source. See the 2026-09-07 amendment above.
```

Under `## Entra RBAC groups`, immediately after the existing
`> **Amended 2026-09-06:** ...` blockquote, add:

```markdown

> **Further amended 2026-09-07:** the per-group role assignments are made by
> `bootstrap/` against each stack's resource group, not "by each owning
> stack"; the group object IDs are a `bootstrap/` input, not per-stack GitHub
> repository variables; and the CI identities hold no subscription-scoped
> role. See the 2026-09-07 amendment above.
```

- [ ] **Step 5: Update `README.md`**

**5a.** In the `## Stacks` table, drop `, RBAC` from each `Creates` cell:

```markdown
| Stack | Creates | Depends on |
|---|---|---|
| [`networking`](environments/dev/networking) | VNet, subnet | — |
| [`observability`](environments/dev/observability) | Log Analytics workspace | — |
| [`key-vault`](environments/dev/key-vault) | Platform Key Vault | `networking`, `observability` |
```

**5b.** Replace the paragraph that begins "The three Entra RBAC groups
(`sap-dev-humans` = `Contributor` ..." and ends "... see
[`bootstrap/README.md`](bootstrap/README.md)." with:

```markdown
The three Entra RBAC groups (`sap-dev-humans` = `Contributor`,
`sap-dev-ci-plan` = `Reader`, `sap-dev-ci-apply` = `Contributor`) are created
and membership-managed by a directory admin outside this repo, as assigned
cloud-only security groups. `bootstrap/` creates one resource group per stack
and assigns those groups their roles on it — the CI identities hold no
subscription-scoped role. See [`bootstrap/README.md`](bootstrap/README.md)
and [ADR 0002](docs/decisions/0002-resource-groups-in-bootstrap.md).
```

**5c.** Replace the numbered list under `## First-time rollout` with:

```markdown
1. Directory admin creates the three Entra groups and makes the operator an
   owner of each (`bootstrap/README.md`).
2. `bootstrap/` — run once by hand (`bootstrap/README.md`). Creates the state
   storage account, the two CI managed identities, one resource group per
   stack, and every role assignment (the CI groups' per-resource-group roles,
   plus the operators' Key Vault data-plane role).
3. Complete the remaining manual steps in `bootstrap/README.md` — the CI
   identities into their groups, GitHub repository variables, the `dev-apply`
   environment, and the state storage account name into each `backend.hcl`.
4. Merge a PR touching `environments/dev/networking/` and
   `environments/dev/observability/` (together or separately — neither has an
   upstream stack).
5. Merge a PR touching `environments/dev/key-vault/` — needs `networking` and
   `observability` to have real applied state.

After this, ordinary changes to any one stack merge and apply normally; this
sequence only matters once, from an empty subscription.
```

**5d.** In `## Security considerations`, insert this bullet immediately after
the "No Microsoft Graph or directory write access anywhere" bullet:

```markdown
- The CI identities hold no subscription-scoped role. `bootstrap/` (run by a
  human subscription Owner) grants them `Reader` / `Contributor` on each
  stack's resource group only, and neither identity can create role
  assignments — a leaked apply token reaches three named resource groups, not
  the subscription. See [ADR 0002](docs/decisions/0002-resource-groups-in-bootstrap.md).
```

**5e.** In the `## How it's tested` table, change the `terraform apply` row's
Credentials cell from `OIDC, sap-dev-ci-apply (Contributor), gated by the
dev-apply GitHub Environment` to `OIDC, sap-dev-ci-apply (Contributor per
resource group), gated by the dev-apply GitHub Environment`.

- [ ] **Step 6: Rewrite `bootstrap/README.md`**

Full new content:

````markdown
# bootstrap

Real Terraform, **local state**, run **once by hand** — this is the
infrastructure that has to predate "clone and go" for every other stack:

- the remote-state storage account;
- the two managed identities (`id-sap-dev-ci-plan`, `id-sap-dev-ci-apply`)
  CI authenticates as via GitHub OIDC (the `id-` prefix keeps them distinct
  from the same-suffixed Entra groups they belong to);
- **one resource group per stack** (`rg-sap-dev-networking`,
  `rg-sap-dev-observability`, `rg-sap-dev-key-vault`) and **every role
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
resource-provider registration still completing; `Microsoft.KeyVault` and
`Microsoft.OperationalInsights` are not in the provider's "core" set and are
registered here, which can take a minute on a fresh subscription).

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
````

- [ ] **Step 7: Update `CHANGELOG.md`**

In `## [Unreleased]` → `### Changed`, append:

```markdown
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
```

In `### Fixed`, replace the bullet that begins "- bootstrap: grant the CI
identities the subscription-scoped roles the stacks actually need" with:

```markdown
- bootstrap: the CI identities are granted `Reader` / `Contributor` on each
  stack's resource group only, never a subscription-scoped role. An earlier
  iteration of `[Unreleased]` gave the apply identity subscription
  `Contributor` + `Role Based Access Control Administrator` to work around
  resource groups being created by the stacks themselves; moving
  resource-group creation into `bootstrap/` removed the need. See ADR 0002
  (`docs/decisions/0002-resource-groups-in-bootstrap.md`).
```

- [ ] **Step 8: Update `CONTRIBUTING.md`**

**8a.** In `## Adding a stack`, add two bullets after the
`environments/dev/<stack>/ with ...` bullet:

```markdown
- In `bootstrap/main.tf`, add the stack's resource-group name to
  `local.stack_resource_groups`; the `for_each` role-assignment blocks then
  cover it. A human re-runs `bootstrap/` (subscription Owner) before the
  stack's first CI run — CI identities cannot create resource groups or role
  assignments. See [ADR 0002](docs/decisions/0002-resource-groups-in-bootstrap.md).
- The stack reads its resource group with
  `data "azurerm_resource_group" "this"` (name hardcoded, matching
  `bootstrap/`), not `resource "azurerm_resource_group"`, and creates no
  `azurerm_role_assignment`.
```

**8b.** In `## Local runs that touch Azure (`plan` / `apply`)`, replace the
paragraph that begins "CI passes each stack's input variables as `-var`
flags" with:

```markdown
Only `key-vault` takes an input variable for local runs
(`tfstate_storage_account_name` — from the bootstrap output or the stack's
`backend.hcl`); `cp terraform.tfvars.example terraform.tfvars` there and fill
it in (the copy is gitignored). `networking` and `observability` take no
variables. The Entra group object IDs are a `bootstrap/` input, not a stack
input.
```

- [ ] **Step 9: Verify**

```bash
./scripts/check.ps1
```
Expected: `All checks passed.` (docs don't affect it; confirm nothing
regressed).

```bash
git grep -n 'GROUP_OBJECT_ID' -- README.md CONTRIBUTING.md bootstrap/README.md docs
```
Every remaining hit must be describing the *old* mechanism as history (inside
an amendment, ADR "Supersedes" / "Consequences", or a CHANGELOG entry). No
surviving statement may present `*_GROUP_OBJECT_ID` repo variables or
per-stack group inputs as current.

```bash
git grep -n 'subscription-scoped\|Role Based Access Control Administrator' -- README.md docs CHANGELOG.md
```
Each hit must be historical or a "no subscription-scoped role" statement — not
a current claim that a CI identity holds one.

- [ ] **Step 10: Commit**

```bash
git add docs README.md bootstrap/README.md CHANGELOG.md CONTRIBUTING.md
git commit -m "docs: record ADR 0002 — resource groups and RBAC move into bootstrap"
```

---

## Self-Review Notes

- **Spec coverage.** The 2026-09-07 amendment maps to the tasks: RG creation +
  RBAC + RP registration in `bootstrap/` → Task 1; stacks read the RG via data
  source and drop RBAC/vars → Task 2; CI stops passing group IDs → Task 3;
  spec/ADR/README/runbook/CHANGELOG/CONTRIBUTING → Task 4. The spec's
  plan=Reader / apply=Contributor split and the one-RG-per-stack model are
  preserved — only *where* they are expressed changes.
- **Cold-start.** Walked above. The one new ordering constraint (Entra groups
  before `bootstrap/ apply`, because their object IDs are a bootstrap input)
  is reflected in Task 4's README rewrite and rollout list.
- **Duplicate role assignments avoided.** Because `bootstrap/` grants
  `sap-dev-ci-apply` → `Contributor` per RG, the stacks must **not** also
  create that assignment (Azure rejects a second assignment of the same
  principal+role+scope). Task 2 deletes *all* stack role assignments, not
  just some — this is why `key-vault`'s `humans_secrets_officer` moves to
  `bootstrap/` (at RG scope) rather than staying in the stack.
- **No RBAC Administrator anywhere.** With the stacks creating zero role
  assignments, the apply identity never needs
  `Microsoft.Authorization/*/Write`. `bootstrap/` runs as a human Owner, who
  has it inherently. This is the tightest end state and simpler than keeping
  per-RG RBAC Administrator on the CI group.
- **RP registration.** Confirmed during planning: `Microsoft.KeyVault` and
  `Microsoft.OperationalInsights` are in the provider's "extended" set, not
  "core"; `resource_provider_registrations = "none"` registers *only* the
  explicit `resource_providers_to_register` list, so `Microsoft.Network` /
  `Storage` / `ManagedIdentity` must be listed too even though they are
  "core". Provider-level registration runs before any resource operation, so
  `bootstrap/`'s own storage account / identity creation is covered.
- **Credential-free checks unchanged.** `terraform validate` does not evaluate
  data sources or register providers; `scripts/check.ps1` and the CI
  `validate` / `fmt` / `tflint` / `trivy` jobs stay green with no Azure
  access. Stated in each task's verify step.
- **`terraform.tfvars.example` files.** `networking` / `observability` have no
  variables after Task 2, so their example files are deleted (an example with
  nothing to fill in is noise). `key-vault` keeps one, trimmed to
  `tfstate_storage_account_name`. `CONTRIBUTING.md` is updated to match.
- **`principal_type`.** `bootstrap/`'s new group role assignments set
  `principal_type = "Group"` — consistent with the file's existing
  `principal_type = "ServicePrincipal"` on the identity grants, and it skips
  an AAD lookup. The pre-existing groups are not subject to the replication
  race the identities are, so it is a consistency choice, not a correctness
  fix.
- **Placeholder scan.** No `TBD` / "similar to" / "add error handling" — every
  HCL, YAML, and Markdown block is literal final content.
- **Type consistency.** `bootstrap/` gains `humans_group_object_id` /
  `ci_plan_group_object_id` / `ci_apply_group_object_id` (string, GUID
  `validation`) — the same names the stacks used, now defined only in
  `bootstrap/variables.tf` and referenced in `bootstrap/main.tf`. New output
  `stack_resource_group_names` (list(string)). New resource addresses
  `azurerm_resource_group.stack` (map), `azurerm_role_assignment.stack_*`
  (maps), `azurerm_role_assignment.key_vault_humans_secrets_officer`. The
  stacks' `data.azurerm_resource_group.this` is defined once per stack and
  referenced as `.name` (module input) with no `.id` use remaining after the
  role assignments are deleted.
- **Follow-ups outside this plan:** delete the `HUMANS_GROUP_OBJECT_ID` /
  `CI_PLAN_GROUP_OBJECT_ID` / `CI_APPLY_GROUP_OBJECT_ID` GitHub repo variables
  once set (external, like the earlier `IDENTITY_*` ones); update
  `plan/docs/status.md` (different repo) to record this session and add the
  "assumptions we're carrying" list discussed; the live tenant rollout.
- **Out of scope (unchanged):** the "approved apply is not the reviewed plan"
  known limitation; the `bootstrap` trivy suppression; the deny-by-default
  NSG; the `tf-stack` action's `needs-tfstate-storage-account` mechanism
  (still needed for `key-vault`).
```
