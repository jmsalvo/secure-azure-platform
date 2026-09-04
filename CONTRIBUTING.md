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
