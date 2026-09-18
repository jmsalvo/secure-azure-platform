# Working with Claude in this repo

This file is guidance for Claude Code (or any AI agent) working in this repo.
Human-contributor mechanics — workflow, tooling, local checks — are in
`CONTRIBUTING.md`; don't duplicate that here. This file covers the things
specific to an AI agent's operating boundaries and the gotchas this repo has
already taught us the hard way.

## What this repo is

`secure-azure-platform` is the flagship of a multi-repo portfolio (Lead/Staff
Platform Engineer + security positioning). Root `README.md` has the
architecture; `docs/decisions/` has the ADRs. **Cross-repo project status
lives in a sibling repo**, not here: `../plan/docs/status.md` (milestone
tracker) and `../plan/docs/next-session-prompt.md` (session-to-session
handoff) — read those first when picking up work, especially after a gap.

## Permission boundary — ask before these, every time

- **Merging a PR, or anything else that triggers a live `terraform apply`.**
  There's no required-reviewers gate on this repo (blocked on the free
  private-repo tier), so a merge to `main` is an immediate, unattended live
  apply for any stack whose files changed. Always ask first, even if a
  similar merge was approved earlier in the same session — approval doesn't
  carry forward automatically.
- **`az`/`gh` commands that change live state** (deleting a resource,
  registering a provider, running `apply`/`destroy`) — the operator runs
  these themselves in their own shell and pastes output back, *except*
  `gh`-CLI-based PR/branch/commit operations, which the agent does directly.
  `bootstrap/` is the one Terraform config that's never CI-applied — it's
  always run by hand, since it needs subscription-Owner credentials no CI
  identity holds.

## The pattern this project follows for real milestones

Brainstorm → design spec (`docs/superpowers/specs/`) → implementation plan
(`docs/superpowers/plans/`) → execution, usually via **Subagent-Driven
Development** (fresh implementer + reviewer subagent per task, tracked in a
per-plan SDD ledger). The ledger lives at
`.superpowers/sdd/<plan-name>/progress.md` inside whichever worktree is doing
the work — **git-ignored, and deleted once a milestone ships**, after its
findings are fully distilled into `docs/evidence/<version>.md` (this repo)
and `../plan/docs/learnings/<topic>.md` (the sibling repo). Once a milestone
is tagged and released, treat its `next-session-prompt.md` section as a
closed historical record, not something to resume from.

## Hard-won operational gotchas

- **Live-only gaps are real and recur.** `terraform plan`/`validate` passing
  proves the config's *shape* is correct, not that the subscription can
  satisfy it right now. Two categories have bitten this project multiple
  times on brand-new resource types: a **resource-provider registration**
  missing from `bootstrap/versions.tf`'s `resource_providers_to_register`
  list (every stack runs with `resource_provider_registrations = "none"`,
  so only `bootstrap/` can register a namespace — check the actual resource
  being added, including auxiliary features like monitoring/policy add-ons,
  not just the top-level resource type), and a **VM SKU not allowed or not
  quota'd** on this specific subscription (`az vm list-usage --location
  <region>` — a family's `Limit` can be a hard `0`, not just "temporarily
  consumed"). When a live apply fails with an ARM error neither `fmt` nor
  `validate` would have caught, check these two categories before assuming
  it's a code bug. Once the *same* category (e.g. missing RP registration)
  hits twice in one session, stop fixing reactively — read the actual
  resource's/module's source to find every other likely dependency and
  register proactively, rather than waiting for a third live failure.
- **An Azure resource can exist with no matching Terraform state.** If a
  `CreateOrUpdate` call succeeds but the subsequent operation-polling step
  fails (e.g. on a missing provider registration for a secondary feature),
  Terraform never writes state — but the resource is real in Azure, possibly
  stuck in a `Failed` provisioning state. The next `apply` then fails with
  "already exists... needs to be imported," which reads like a naming
  collision. Check the resource's actual `provisioningState` directly
  (`az <resource> show`) before assuming an import is the fix — deleting and
  recreating is usually cheaper for a `Failed`-state resource.
- **`gh pr merge --delete-branch` fails from inside a git worktree** with
  `fatal: 'main' is already checked out at '<primary repo path>'` — this is
  expected whenever the primary checkout has `main` checked out (it does, by
  default). The merge itself still succeeds; verify with `gh pr view <n>
  --json state,mergedAt,mergeCommit`, then delete the remote branch manually
  (`git push origin --delete <branch>`).
- **Git Bash chokes on Windows-style backslash paths** inside heredocs/quoted
  strings (`"C:\Users\...\file"` → `unexpected EOF while looking for matching`).
  Use forward-slash paths (`/c/Users/.../file`) in any Bash-tool command that
  touches a path with spaces or gets quoted.
- **`az aks install-cli` doesn't put `kubectl`/`kubelogin` on PATH** for a
  Bash-tool session — they land in `~/.azure-kubectl` and
  `~/.azure-kubelogin` respectively. Export both onto `PATH` explicitly each
  session before using either. For a cluster with `local_account_disabled =
  true` + Azure RBAC for Kubernetes, `kubelogin convert-kubeconfig -l
  azurecli` reuses the operator's existing `az login` session — no separate
  interactive device-code prompt needed, as long as they're already logged
  in via `az`.
- **A reviewer's claim that a CI gate "won't fire" is a prediction to
  verify, not a finding to trust** — check it against the actual gate config
  (e.g. `trivy.yaml`'s `severity:` line) when the stakes are "blocks CI or
  not." This project has been burned by trusting the prediction once
  already.
