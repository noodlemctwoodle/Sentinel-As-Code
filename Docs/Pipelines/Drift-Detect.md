# Drift-Detect Pipeline

CI/CD wiring for portal-drift detection and the auto-PR that absorbs it
back into the repo. This page documents the **pipeline mechanics** on both
CI systems: triggers, inputs, jobs, steps, the identities and secrets they
consume, and the GitHub <-> ADO mapping.

For what the invoked script actually does (the drift buckets, the absorb
logic, the YAML it writes, the report format), see
[Sentinel Analytics Rule Drift Detection](../Tools/Sentinel-Drift-Detection.md).
This page does not repeat that; it stays on the CI wiring around it.

| Item | Where |
| --- | --- |
| GitHub Actions workflow | [`.github/workflows/sentinel-drift-detect.yml`](../../.github/workflows/sentinel-drift-detect.yml) |
| Azure DevOps pipeline | [`Pipelines/Sentinel-Drift-Detect.yml`](../../Pipelines/Sentinel-Drift-Detect.yml) |
| Invoked script | [`Tools/Test-SentinelRuleDrift.ps1`](../../Tools/Test-SentinelRuleDrift.ps1) |
| Schedule | Daily at 06:00 UTC (both CI systems) |
| Auto-sync branch | `auto/sentinel-drift-sync` (rolling, force-pushed each run) |
| PR target | `main` |

Both CI systems run the same detection script on the same daily schedule,
reset the rolling `auto/sentinel-drift-sync` branch from `origin/main`,
force-push, and open or refresh a PR into `main`. They differ only in
authentication, module install, PR mechanics, and report-artefact handling.
Those differences are called out under
[GitHub <-> ADO mapping](#github---ado-mapping).

## Purpose

The pipeline detects analytics rules that were edited directly in the
Microsoft Sentinel portal (bypassing the deploy pipelines), absorbs the
deployed state back into `Content/AnalyticalRules/` as YAML, and opens a PR
so a human reviews the change before it lands on `main`. When there is no
drift, nothing is committed and no PR is opened.

## Triggers and schedule

### GitHub (`sentinel-drift-detect.yml`)

Two triggers, no `push` or `pull_request`:

- **`schedule`** - cron `0 6 * * *` (daily 06:00 UTC), independent of the
  deploy workflow's schedule.
- **`workflow_dispatch`** - manual run from the Actions tab, exposing the
  five inputs listed below.

### ADO (`Sentinel-Drift-Detect.yml`)

- **`trigger: none`** - no CI (branch/PR) trigger. The pipeline never runs
  on a push.
- **`schedules`** - cron `0 6 * * *`, `displayName: "Daily 06:00 UTC"`,
  scoped to `branches: include: main`, with `always: true` so it runs even
  when `main` has no new commits since the last scheduled run.
- **Manual** - queued on demand from the ADO **Run pipeline** panel, which
  surfaces the five parameters below.

## Inputs and parameters

Both systems expose the same five boolean toggles with identical defaults.
On GitHub they are `workflow_dispatch` inputs; on ADO they are pipeline
`parameters`. Each maps to a switch on `Test-SentinelRuleDrift.ps1`.

| Input / parameter | Default | Script switch | Effect |
| --- | --- | --- | --- |
| `failOnDrift` | `false` | `-FailOnDrift` | Fail the run when drift is detected (rather than just reporting and PR-ing) |
| `reportOnly` | `false` | `-ReportOnly` | Write the report artefact only; do **not** write YAML edits, commit, push, or open a PR |
| `skipContentHub` | `false` | `-SkipContentHub` | Skip the Content Hub drift bucket |
| `skipCustom` | `false` | `-SkipCustom` | Skip the Custom (repo YAML) drift bucket |
| `skipOrphans` | `false` | `-SkipOrphans` | Skip the Orphan (ungoverned) drift bucket |

Solution-name filtering is deliberately **not** exposed as a pipeline
input. ADO `values:` lists are evaluated at compile time and cannot be
populated from the live workspace catalogue, and hardcoding solution names
would couple the pipeline to one workspace. The script always scans every
Content Hub rule it finds and groups the report per-solution. For an ad-hoc
per-solution run, invoke the script directly with `-Solutions` (see the
[tool doc](../Tools/Sentinel-Drift-Detection.md)).

### Compile-time flag mapping (ADO only)

ADO cannot pass a boolean straight to a PowerShell switch, so each
parameter is mapped to a flag string at compile time via `${{ if ... }}`
expressions (mirroring the convention in `Sentinel-Deploy.yml`):

```
flagFailOnDrift    -> "-FailOnDrift"   or ""
flagReportOnly     -> "-ReportOnly"    or ""
flagSkipContentHub -> "-SkipContentHub" or ""
flagSkipCustom     -> "-SkipCustom"    or ""
flagSkipOrphans    -> "-SkipOrphans"   or ""
```

The inline script then splats the non-empty flags into a `$scriptParams`
hashtable. The GitHub workflow does the equivalent at runtime, testing
each `inputs.*` value and adding the matching key to `$scriptParams` only
when it is `'true'`.

## Variables, secrets, and repo configuration

### GitHub

Consumed from repository **Secrets** and **Variables** (Settings ->
Secrets and variables):

| Kind | Name | Purpose |
| --- | --- | --- |
| Secret | `AZURE_CLIENT_ID` | Service Principal application (client) ID for OIDC |
| Secret | `AZURE_TENANT_ID` | Entra ID tenant ID |
| Secret | `AZURE_SUBSCRIPTION_ID` | Azure subscription ID (also passed to the script) |
| Secret | `GITHUB_TOKEN` | Built-in token, used to checkout, push the sync branch, and drive `gh pr` |
| Variable | `SENTINEL_RESOURCE_GROUP` | Resource group name |
| Variable | `SENTINEL_WORKSPACE_NAME` | Log Analytics workspace name |
| Variable | `SENTINEL_REGION` | Azure region (e.g. `uksouth`) |

Workflow-level `env`:

- `SYNC_BRANCH: "auto/sentinel-drift-sync"`
- `TARGET_BRANCH: "main"`
- `YAML_VERSION: "0.4.12"` - pins `powershell-yaml` so a PSGallery release
  cannot break a scheduled run.

### ADO

Consumed from the `sentinel-deployment` variable group (shared with
`Sentinel-Deploy.yml`):

| Variable | Source | Purpose |
| --- | --- | --- |
| `azureSubscriptionId` | variable group | Subscription ID passed to the script |
| `sentinelResourceGroup` | variable group | Resource group name |
| `sentinelWorkspaceName` | variable group | Workspace name |
| `sentinelRegion` | variable group | Azure region |
| `serviceConnection` | pipeline var (`sc-sentinel-as-code`) | Azure service connection used for auth |
| `SuppressAzurePowerShellBreakingChangeWarnings` | pipeline var (`true`) | Quietens Az module deprecation warnings |
| `syncBranch` | pipeline var (`auto/sentinel-drift-sync`) | Rolling sync branch |
| `targetBranch` | pipeline var (`main`) | PR target branch |

`syncBranch` and `targetBranch` are variables (not parameters) on purpose,
so the **Run pipeline** panel stays minimal - the bot-managed branch names
should not be tweaked per-run.

## Authentication

### GitHub - OIDC federated credential

Auth is a single step using the repo's composite action
[`./.github/actions/azure-login-oidc`](../../.github/actions/azure-login-oidc/action.yml),
which wraps `Azure/login@v3` with `enable-AzPSSession` on by default (the
drift step runs under `Azure/powershell@v3`, so it needs the Az PowerShell
session, not just `az` CLI):

```yaml
- name: Azure login (OIDC)
  uses: ./.github/actions/azure-login-oidc
  with:
    client-id:       ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id:       ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

No client secret is stored. The federated credential trusts GitHub's token
issuer for this repo, and the job requests an OIDC token via the
`id-token: write` permission below. This is the same SP the deploy workflow
uses; it needs at least **Microsoft Sentinel Reader** on the workspace.

Job `permissions` (least privilege for what the job actually does):

```yaml
permissions:
  id-token: write       # OIDC against Azure
  contents: write       # push the auto-sync branch
  pull-requests: write  # gh pr create / update
```

### ADO - service connection + build-service identity

Two distinct identities are in play:

- **Azure auth** uses the `sc-sentinel-as-code` service connection (workload
  identity federation, matching the GitHub OIDC setup - see
  [ADO OIDC Setup](../Deploy/ADO-OIDC-Setup.md)). The connection needs **Microsoft
  Sentinel Reader** on the workspace.
- **Git push + PR** uses `System.AccessToken`, exposed to the git CLI via
  `checkout: self` with `persistCredentials: true`. The
  `Project Collection Build Service ($org)` identity must be granted
  **Contribute**, **Create branch**, and **Contribute to pull requests** on
  the repo, otherwise the push and `az repos pr` calls fail.

## Jobs and steps

### GitHub - job `detect-drift`

`runs-on: ubuntu-latest`, `timeout-minutes: 30`. Steps in order:

1. **Checkout main** (`actions/checkout@v5`) - `token: GITHUB_TOKEN`,
   `fetch-depth: 0` so `git fetch origin main` / rebase work cleanly when
   the sync branch is reset.
2. **Azure login (OIDC)** - the `azure-login-oidc` composite action above.
3. **Set up PowerShell modules** - the
   [`setup-pwsh-modules`](../../.github/actions/setup-pwsh-modules/action.yml)
   composite action with `yaml-version: ${{ env.YAML_VERSION }}` and
   `install-pester: 'false'` (drift detection needs `powershell-yaml` but
   no Pester). Installs the pinned version from cache and fails fast on
   cache drift.
4. **Run Sentinel drift detection** (`Azure/powershell@v3`,
   `azPSVersion: latest`) - builds `$scriptParams` (subscription, resource
   group, workspace, region, repo path, plus any `-Skip*` / `-ReportOnly` /
   `-FailOnDrift` flags from the inputs) and invokes
   `Tools/Test-SentinelRuleDrift.ps1`.
5. **Commit, push, and open / refresh PR** - `shell: bash`,
   `GH_TOKEN: GITHUB_TOKEN`, guarded by `if: ${{ inputs.reportOnly != true }}`.
   See [Commit / push / PR step](#commit--push--pr-step) below.
6. **Upload drift report artefact** (`actions/upload-artifact@v6`,
   `if: always()`) - uploads `reports/` as
   `sentinel-drift-report-${{ github.run_id }}`, `retention-days: 30`,
   `if-no-files-found: ignore`.

### ADO - stage `DetectAndSyncDrift`, job `RunDriftDetection`

`pool: ubuntu-latest`, `timeoutInMinutes: 30`. Steps in order:

1. **`checkout: self`** with `persistCredentials: true` so
   `System.AccessToken` is available to git.
2. **Install powershell-yaml Module** (`PowerShell@2`, inline) - a plain
   `Install-Module -Name powershell-yaml -Force -Scope CurrentUser
   -AllowClobber`. Note this installs the **latest** version, not a pinned
   one (see the [mapping](#github---ado-mapping)).
3. **Detect Sentinel Rule Drift** (`AzurePowerShell@5`) -
   `azureSubscription: $(serviceConnection)`, `ScriptType: InlineScript`,
   `azurePowerShellVersion: LatestVersion`, `errorActionPreference:
   Continue`. Builds the same `$scriptParams` hashtable from the variable
   group values plus the compile-time flag strings, then invokes
   `Test-SentinelRuleDrift.ps1`.
4. **Commit, Push, and Open PR (when drift detected)** (`bash`) - guarded
   by `condition: and(succeeded(), ${{ ne(parameters.reportOnly, true) }})`
   and `env: AZURE_DEVOPS_EXT_PAT: $(System.AccessToken)`. See below.

### Commit / push / PR step

This is the heart of both pipelines and is functionally identical across
them:

1. Bail out early (`exit 0`) if `git status --porcelain` is empty - no
   drift means a clean working tree, so nothing is committed and no PR is
   opened.
2. Configure a bot git identity (`Sentinel Drift Sync`
   `<noreply@sentinel-as-code.local>`).
3. **Reset the rolling sync branch from the latest target tip**: stash the
   script's working-tree changes, `git fetch origin main`,
   `git checkout -B auto/sentinel-drift-sync origin/main`, `git stash pop`.
   This guarantees the branch always descends from current `main` and
   avoids "Added in both" merge conflicts when a previous drift PR has
   already merged.
4. `git add Content/AnalyticalRules reports` - only the paths the script may
   legitimately have touched.
5. Commit with a timestamped `chore(sentinel): sync drift from portal ...`
   message, then `git push --force-with-lease` the bot branch.
6. Build a **concise PR body** from the newest
   `reports/sentinel-drift-*.md` (the Summary section plus a bullet list of
   drifted rule headings), because the full report embeds full KQL bodies
   and would exceed the PR-description limits.
7. Look for an existing open PR from the sync branch into `main`; **edit**
   its description if found, otherwise **create** a new PR.

## Artefacts and outputs

- **Report file** - `Test-SentinelRuleDrift.ps1` writes
  `reports/sentinel-drift-{UTC-timestamp}.{md,json}`. Both pipelines commit
  the report into the sync branch alongside the absorbed YAML (via
  `git add ... reports`), so it appears in the PR's Files Changed tab.
- **Workflow artefact (GitHub only)** - GitHub additionally uploads
  `reports/` as a run artefact (`sentinel-drift-report-<run_id>`, 30-day
  retention) so a **`-ReportOnly`** run still produces a downloadable
  report even though it commits nothing. ADO has no equivalent
  upload-artefact step; a `-ReportOnly` ADO run leaves the report only in
  the runner workspace.
- **Pull request** - on drift, a PR from `auto/sentinel-drift-sync` into
  `main`, refreshed in place on subsequent runs.

## GitHub <-> ADO mapping

The two implementations are functional mirrors on the same daily schedule.
The asymmetries to be aware of:

| Aspect | GitHub (`sentinel-drift-detect.yml`) | ADO (`Sentinel-Drift-Detect.yml`) |
| --- | --- | --- |
| Structure | Single job, six steps | One stage, one job, four steps |
| Azure auth | OIDC via `azure-login-oidc` composite action | `sc-sentinel-as-code` service connection |
| Git / PR auth | `GITHUB_TOKEN` (job `permissions` block) | `System.AccessToken` via `persistCredentials`, plus build-service repo grants |
| Module install | `setup-pwsh-modules` composite, `powershell-yaml` **pinned** to `0.4.12` | Inline `Install-Module`, **latest** (unpinned) |
| PR CLI | `gh pr list` / `create` / `edit`, body via `--body-file` | `az repos pr list` / `create` / `update`, body via `--description` |
| ReportOnly guard | `if: inputs.reportOnly != true` on the commit/PR step | `condition: and(succeeded(), ne(parameters.reportOnly, true))` on the commit/PR step |
| Report artefact | Uploaded as a run artefact (`actions/upload-artifact@v6`) | Not uploaded; committed to the sync branch only |

The **`-ReportOnly` guard now applies on both CI systems**: a report-only
run writes the report artefact and never commits, pushes, or opens a PR.
Previously the ADO commit step ran unconditionally and the report file it
left in `reports/` made the working tree dirty, triggering an unwanted
commit; the step is now guarded to match GitHub.

Everything else - the daily 06:00 UTC cron, the five toggles and their
defaults, the branch-reset-from-`origin/main` strategy, the concise PR body
built from the report, and the create-or-refresh PR logic - is identical.

## Related documentation

- [Sentinel Analytics Rule Drift Detection](../Tools/Sentinel-Drift-Detection.md)
  - what the invoked script does (drift buckets, absorb logic, report format).
- [Pipelines](README.md) - the full set of seven ADO pipelines and
  their GitHub mirrors.
- [ADO OIDC Setup](../Deploy/ADO-OIDC-Setup.md) - wiring the `sc-sentinel-as-code`
  service connection with workload identity federation.
