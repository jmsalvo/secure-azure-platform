# Contributing

This is a single-operator portfolio repo, but the workflow mirrors a real
team's: PR-based, CI-gated, Conventional Commits.

## Workflow

1. Branch from `main`.
2. Make the change. Stack changes need `terraform validate` (and `terraform
   plan` once Azure credentials exist) passing before merge.
3. Run the local checks below.
4. Open a PR. CI must be green to merge; merging to `main` triggers `apply`
   for any stack whose files changed (see root `README.md` for the CI shape).
5. Commits follow [Conventional Commits](https://www.conventionalcommits.org/)
   (`feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `refactor:`).

## Tooling

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.6 required; CI and local use 1.16.x | `fmt`, `validate`, `plan`, `apply` |
| tflint | latest | lint + azurerm ruleset |
| trivy | latest | IaC misconfiguration scan |
| Azure CLI | latest | `az login` for local runs against the real tenant |
| pre-commit | optional | runs fmt/validate/tflint/trivy on `git commit` (macOS/Linux, or Windows + Git Bash) |

Windows contributors: `scripts\check.ps1` runs the credential-free checks
natively — see below.

Provider versions live in each config's committed `.terraform.lock.hcl`
(deliberately not gitignored, same pinning discipline as the `?ref=v0.1.0`
module pins). CI runs `terraform init -lockfile=readonly`, so a lock file
that doesn't already satisfy the constraints fails the build instead of
silently re-resolving. To bump a provider, run `terraform providers lock
-platform=linux_amd64 -platform=windows_amd64` in the affected directory
(both platforms — CI is Linux) and commit the result.

## Repo layout notes

- `docs/decisions/` — Architecture Decision Records.
- `docs/evidence/` — CI-run and release evidence artifacts (plan output,
  scan results, screenshots) kept alongside the code they attest to, the
  same convention as the sibling
  [`terraform-azure-modules`](https://github.com/jmsalvo/terraform-azure-modules)
  repo. Empty at `v0.1` (nothing has been applied against a real tenant
  yet), hence the `.gitkeep`.

## Local checks

**Windows** (no bash needed):

```powershell
.\scripts\check.ps1          # check everything (fmt, validate, tflint, trivy)
.\scripts\check.ps1 -Fix     # also auto-run `terraform fmt`
```

**macOS / Linux** — either the pre-commit hooks:

```bash
pipx install pre-commit   # or: pip install pre-commit
pre-commit install
pre-commit run --all-files
```

or by hand:

```bash
terraform fmt -check -recursive
for d in bootstrap environments/*/*/; do
  terraform -chdir="$d" init -backend=false && terraform -chdir="$d" validate
done
tflint --init && tflint --recursive
trivy config --config trivy.yaml .
```

## Local runs that touch Azure (`plan` / `apply`)

`az login` alone isn't enough: the `azurerm` v4 provider no longer infers a
subscription from the CLI's default context, so an explicit subscription ID
is required or `init`/`plan` fails with *"subscription ID could not be
determined"*.

```bash
az login
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
```

```powershell
az login
$env:ARM_SUBSCRIPTION_ID = (az account show --query id -o tsv)
```

CI sets the same variable from the `ARM_SUBSCRIPTION_ID` repo variable
(see `bootstrap/README.md`).

## CI on pull requests from forks

Once this repo is public, PRs opened from a fork get no `id-token: write`
permission — GitHub withholds it from fork workflows by design, so no OIDC
token can be minted and the `plan-*` jobs **fail rather than skip**. That is
intentional and correct: fail-closed. There is no supported way to give an
untrusted fork a token for this subscription, and `pull_request_target`
(which would run with the base repo's permissions against fork-controlled
code) is deliberately not used. A maintainer re-runs the change from a
branch in this repo to get a `plan`.

## Adding a stack

- `environments/dev/<stack>/` with `versions.tf`, `main.tf`, `variables.tf`,
  `outputs.tf`, `backend.hcl`, `README.md`.
- Add the stack's `plan`/`apply` jobs to `.github/workflows/ci.yml`, wired
  into the `needs:` graph at the correct dependency tier (see root
  `README.md`'s stack dependency diagram).
- Note the change in `CHANGELOG.md` under `## [Unreleased]`.

## Making changes to an existing stack

Same as adding one, minus the CI wiring. If the change adds a new
cross-stack dependency, update the `needs:` graph and the root README's
dependency diagram together — they must not drift.
