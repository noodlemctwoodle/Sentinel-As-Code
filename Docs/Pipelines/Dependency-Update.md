# Dependency Update Pipeline

Daily automation that keeps [`dependencies.json`](../../dependencies.json)
in sync with the content tree. It runs
[`Tools/Build-DependencyManifest.ps1`](../../Tools/Build-DependencyManifest.ps1)
`-Mode Update` against `main`, and if the regenerated manifest diverges from
the on-disk copy it pushes the refreshed file to a rolling bot branch and
opens (or refreshes) a pull request for review.

This page documents the CI/CD wiring only. For what the invoked script
actually does (discovery walk, KQL scanning, classification, the `Generate`
/ `Verify` / `Update` modes), see
[Dependency Manifest](../Tools/Dependency-Manifest.md).

There are two implementations that stay behaviourally identical:

| CI system | File |
| --- | --- |
| Azure DevOps | [`Pipelines/Sentinel-Dependency-Update.yml`](../../Pipelines/Sentinel-Dependency-Update.yml) |
| GitHub Actions | [`.github/workflows/sentinel-dependency-update.yml`](../../.github/workflows/sentinel-dependency-update.yml) |

Unlike the deploy and drift-detect pipelines, this one needs **no Azure
authentication**. Discovery is fully offline (it parses YAML on disk only),
so there is no service connection, no OIDC login, and no service-principal
permissions involved. The only credential in play is the CI system's own
repo-write token, used to push the bot branch and open the PR.

## Why daily, not on-merge

The PR-validation gate (job `dependency-manifest` on GitHub,
`Sentinel-PR-Validation.yml` on ADO) already runs
`Build-DependencyManifest.ps1 -Mode Verify` and blocks any PR that forgets
to regenerate the manifest. This pipeline exists for the long tail the gate
can miss: a fork merge pushed straight through the web UI, or a doc-only
commit that adjusted a rule's embedded query inline. A daily run keeps the
manifest fresh against those edge cases.

It is scheduled at **02:00 UTC** deliberately, ahead of the drift-detect run
(06:00 UTC) and the weekly Monday deploy (04:00 UTC), so a fresh manifest is
in place before either of those consumes it.

## Behaviour

| Outcome | Result |
| --- | --- |
| No drift (manifest already current) | No commit, no PR. The run exits `0` quietly. |
| Drift found | The regenerated manifest is pushed to the bot branch and a PR is opened or refreshed. |
| `reportOnly` requested | The manifest is regenerated so the diff shows in the run log, but the commit / push / PR step is skipped. |

The bot branch is `auto/dependency-manifest-sync`, which follows the same
naming convention as the drift-detect workflow's `auto/sentinel-drift-sync`.
It is force-pushed on every drift run and must never be hand-edited.

## Triggers

| Trigger | GitHub | Azure DevOps |
| --- | --- | --- |
| Schedule | `cron: "0 2 * * *"` (daily 02:00 UTC) | `cron: "0 2 * * *"`, `branches.include: main`, `always: true` |
| Manual | `workflow_dispatch` (with the `reportOnly` input) | Queue manually from the pipeline UI (the `reportOnly` parameter is offered at queue time) |
| Push / PR | None | None (`trigger: none`) |

Neither implementation triggers on push or pull request; the manifest is
only refreshed on the schedule or a manual run. The ADO schedule sets
`always: true`, so it runs even when `main` has not changed since the last
scheduled run.

## Parameters and inputs

Both systems expose a single input:

| Name | Type | Default | Effect |
| --- | --- | --- | --- |
| `reportOnly` | boolean | `false` | Regenerate the manifest and show the drift in the run log, but do not commit, push, or open a PR. |

- **GitHub** declares it as a `workflow_dispatch` input and gates the
  commit step directly with `if: ${{ inputs.reportOnly != true }}`.
- **ADO** declares it as a pipeline `parameter` and, because a template
  parameter cannot be read inside a runtime bash step directly, resolves it
  at compile time into a `flagReportOnly` variable
  (`"true"` / `"false"`) that the bash step then checks
  (`if [ "$(flagReportOnly)" = "true" ]`).

## Variables and configuration

The branch and target names are held in workflow-level variables (no
variable group, no library, no secrets beyond the built-in token):

| Purpose | GitHub (`env:`) | ADO (`variables:`) |
| --- | --- | --- |
| Bot branch | `SYNC_BRANCH: auto/dependency-manifest-sync` | `syncBranch: auto/dependency-manifest-sync` |
| Target branch | `TARGET_BRANCH: main` | `targetBranch: main` |
| `powershell-yaml` pin | `YAML_VERSION: 0.4.12` | Pinned inline in the install step (`0.4.12`) |
| Report-only flag | `inputs.reportOnly` (read directly) | `flagReportOnly` (compile-time from `parameters.reportOnly`) |

## Jobs and steps

Both implementations are a single job on `ubuntu-latest` with a
**10-minute** timeout. GitHub names the job `refresh-manifest`; ADO wraps a
single job `RunUpdate` in a stage `RefreshDependencyManifest`.

The steps run in this order:

```
1. Checkout main (full history)
2. Install PowerShell modules (powershell-yaml only)
3. Run Build-DependencyManifest.ps1 -Mode Update
4. Commit, push, and open / refresh PR  (skipped on reportOnly or clean tree)
```

### 1. Checkout

- **GitHub**: `actions/checkout@v5` with `token: ${{ secrets.GITHUB_TOKEN }}`
  and `fetch-depth: 0`. Full history is required so the branch reset
  (`git rebase` / `checkout -B` from the target tip) works cleanly.
- **ADO**: `checkout: self` with `persistCredentials: true`, which exposes
  `System.AccessToken` to git so the same checkout can push back to the repo.

### 2. Install PowerShell modules

Only `powershell-yaml` is needed; Pester is not installed here (no tests
run).

- **GitHub** uses the shared composite action
  [`.github/actions/setup-pwsh-modules`](../../.github/actions/setup-pwsh-modules/action.yml)
  with `yaml-version: 0.4.12` and `install-pester: 'false'`. The composite
  caches and pin-installs the module, and fails fast on cache drift.
- **ADO** inlines the equivalent logic in a `PowerShell@2` task: it installs
  `powershell-yaml` at `RequiredVersion 0.4.12` only when a matching version
  is not already available. (Composite actions are a GitHub-only construct,
  so the ADO pipeline cannot reuse the composite and duplicates the install
  step instead.)

### 3. Run the manifest update

Invokes the script in `Update` mode:

- **GitHub**: `./Tools/Build-DependencyManifest.ps1 -Mode Update`
  (repo root is the working directory).
- **ADO**: `Build-DependencyManifest.ps1 -Mode Update -RepoPath "$(Build.SourcesDirectory)"`
  (the repo root is passed explicitly).

`Update` mode rewrites `dependencies.json` on disk when it detects drift and
exits `0`; on no drift it leaves the file untouched and also exits `0`. The
pipeline, not the script, owns the commit / push / PR. See
[Dependency Manifest](../Tools/Dependency-Manifest.md) for the discovery
detail.

### 4. Commit, push, and open / refresh PR

This step is skipped when `reportOnly` is set, and short-circuits with a
clean exit when `git status --porcelain dependencies.json` shows no change
(no drift). When drift is present it:

1. Sets the bot commit identity (`Sentinel Dependency Sync`,
   `noreply@sentinel-as-code.local`).
2. Resets the rolling sync branch from the current target tip
   (`stash --include-untracked` -> `fetch origin main` ->
   `checkout -B auto/dependency-manifest-sync origin/main` -> `stash pop`),
   so the branch always descends from the latest `main`. This is the same
   stash / reset / pop pattern the drift-detect pipeline uses.
3. Stages **only** `dependencies.json` (`git add dependencies.json`), so a
   stray local file cannot sneak into the commit.
4. Computes `ENTRY_COUNT` (the number of entries in the regenerated
   manifest) for the commit message and PR body.
5. Commits with a `chore(deps): refresh dependency manifest <timestamp>`
   subject and a body that names the generating pipeline and points at
   `-Mode Generate` for local reproduction.
6. Force-pushes the bot branch with `--force-with-lease` (it is a bot
   branch, never hand-edited).
7. Opens a new PR, or refreshes the description of the existing open PR from
   the same branch.

The PR-tooling and auth differ between systems:

| Concern | GitHub | Azure DevOps |
| --- | --- | --- |
| PR CLI | `gh pr list` / `gh pr edit` / `gh pr create` | `az repos pr list` / `az repos pr update` / `az repos pr create` |
| Auth for the step | `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` | `az devops login` fed `$(System.AccessToken)`; `AZURE_DEVOPS_EXT_PAT` set to the same token |
| PR create extras | Title + body-file | `--auto-complete false`, `--delete-source-branch false` |

The PR title is `chore(deps): refresh dependency manifest <date>` and the
body is a generated Markdown block covering the discovered entry count, why
drift accumulates, and a reviewer checklist (does the diff make sense, has
any rule lost its dependency entry, has a function been mis-classified). The
guidance is to squash and merge, after which the PR-validation
`dependency-manifest` gate revalidates against the merged commit.

## Authentication

No Azure identity is used. Each system authenticates only to its own git
host to push the branch and open the PR:

- **GitHub**: the built-in `GITHUB_TOKEN`, scoped by the workflow-level
  `permissions` block to `contents: write` (push the bot branch) and
  `pull-requests: write` (`gh pr create` / `edit`).
- **ADO**: the pipeline's `System.AccessToken`, exposed to git by
  `persistCredentials: true` and to `az` via `az devops login` /
  `AZURE_DEVOPS_EXT_PAT`. This requires the
  **`Project Collection Build Service ($org)`** identity to hold
  **Contribute**, **Create branch**, and **Contribute to pull requests** on
  the repo (the same identity already configured for the drift-detect
  pipeline's auto-PR mechanism).

## Outputs and artefacts

There are no published pipeline artefacts. The only outputs are side
effects on the repository:

- On drift: a force-pushed `auto/dependency-manifest-sync` branch and an
  open (or refreshed) PR into `main`.
- On no drift: nothing; the run exits `0` with a "Manifest already current"
  log line.

## GitHub and ADO differences at a glance

Both are behaviourally equivalent (same schedule, same branch, same PR
title, same guards). The mechanical differences are:

| Aspect | GitHub | Azure DevOps |
| --- | --- | --- |
| Module install | Shared `setup-pwsh-modules` composite | Inline `PowerShell@2` install |
| Repo path to the script | Implicit (working directory) | Explicit `-RepoPath $(Build.SourcesDirectory)` |
| `reportOnly` gating | Step-level `if: inputs.reportOnly != true` | Compile-time `flagReportOnly`, checked in bash |
| Repo-write credential | `GITHUB_TOKEN` + `permissions` block | `System.AccessToken` + build-service repo permissions |
| PR tooling | `gh` CLI | `az repos` / `az devops` CLI |

---

## Related documentation

- [Dependency Manifest](../Tools/Dependency-Manifest.md) - what the
  invoked script does (discovery, classification, the `Generate` / `Verify`
  / `Update` modes).
- [Pipelines](README.md) - the full pipeline set and the ADO / GitHub
  parity overview.
- [Sentinel Drift Detection](../Tools/Sentinel-Drift-Detection.md) - the
  sibling auto-PR pipeline that shares the branch-reset pattern.
