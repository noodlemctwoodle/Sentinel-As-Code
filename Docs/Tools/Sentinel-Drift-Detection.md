# Sentinel Analytics Rule Drift Detection

Detects rules that have been edited directly in the Microsoft Sentinel portal,
bypassing the DevOps deployment pipelines. Every drift bucket is absorbed back
into the repo as YAML under `Content/AnalyticalRules/`, then committed onto a rolling
auto-sync branch and surfaced via an auto-generated pull request for human
review.

| What | Where |
| --- | --- |
| Detection script | [`Tools/Test-SentinelRuleDrift.ps1`](../../Tools/Test-SentinelRuleDrift.ps1) |
| GitHub Actions workflow | [`.github/workflows/sentinel-drift-detect.yml`](../../.github/workflows/sentinel-drift-detect.yml) |
| Azure DevOps pipeline | [`Pipelines/Sentinel-Drift-Detect.yml`](../../Pipelines/Sentinel-Drift-Detect.yml) |
| Generated reports | `reports/sentinel-drift-{UTC-timestamp}.{md,json}` |
| Auto-sync branch | `auto/sentinel-drift-sync` (rolling, force-pushed each run) |
| Schedule | Daily at 06:00 UTC (both CI systems) |

The same detection script drives two CI implementations. GitHub Actions is the
repo's primary CI; the Azure DevOps pipeline is a functional mirror. Both invoke
`Test-SentinelRuleDrift.ps1` on an identical daily schedule, reset the rolling
`auto/sentinel-drift-sync` branch from `origin/main`, force-push, and open or
refresh a PR into `main`. They differ only in authentication and PR mechanics
(see [GitHub Actions workflow](#github-actions-workflow) and
[Azure DevOps pipeline](#azure-devops-pipeline)).

## Why this exists

Three governance gaps the existing deploy pipelines don't close:

1. **Portal edits to Custom rules silently overwrite the repo.** When the
   next deploy runs, the YAML in the repo wins, and the portal change is lost
   without anyone realising.
2. **Portal edits to Content Hub (OoB) rules drift away from upstream.**
   `Deploy-SentinelContentHub.ps1` already protects modified OoB rules from
   being overwritten on update via `-ProtectCustomisedRules`, but the rule
   keeps drifting without becoming a tracked, version-controlled artefact.
3. **Rules created entirely in the portal are ungoverned.** With no template
   link and no repo YAML, an "orphan" rule has no source of truth at all.

This script runs daily and absorbs every drift bucket back into the repo as
a Custom YAML, then opens a PR so the change can be reviewed and merged.

## How a rule maps to a bucket

Each deployed Analytics Rule resolves to exactly one bucket. Resolution checks
the YAML id lookup first, so a rule that has already been absorbed into
`Content/AnalyticalRules/AbsorbedFromPortal/` is governed via the Custom branch on
every subsequent run, even if it still carries an `alertRuleTemplateName` link
on the workspace side.

| Bucket | Match logic | Action on drift |
| --- | --- | --- |
| **Custom** | The rule's resource-name GUID matches a YAML `id:` under `Content/AnalyticalRules/**` | Existing YAML rewritten in place; patch version bumped |
| **ContentHub** | `properties.alertRuleTemplateName` matches a Content Hub `contentTemplate.contentId` | New YAML written to `Content/AnalyticalRules/AbsorbedFromPortal/ContentHub/{Solution}/{Slug}.yaml`; reuses the rule's resource GUID as `id:` so the next deploy run takes over governance from the template |
| **Orphan** | Neither of the above matches | New YAML written to `Content/AnalyticalRules/AbsorbedFromPortal/Orphans/{Slug}.yaml` so the rule becomes a governed Custom rule |
| **Managed** | `kind` is `Fusion`, `MicrosoftSecurityIncidentCreation`, `MLBehaviorAnalytics`, or `ThreatIntelligence` | Excluded entirely |

Managed rules are Microsoft-built and not user-editable, so drift detection
doesn't apply to them. They're counted in the summary as `managed (excluded)`
but skipped from all three buckets.

After a ContentHub or Orphan rule has been absorbed, its YAML lives alongside
the rest of the Custom rules. Reviewers can keep the file under
`AbsorbedFromPortal/` (the auto-generated location) or move it into a more
descriptive category folder during PR review. Future drift on the same rule
flows through the in-place Custom-rule update path.

## What "drift" means

Compared fields:

| Field | Scheduled | NRT |
| --- | :---: | :---: |
| `query` (whitespace-collapsed) | ✓ | ✓ |
| `severity` (case-insensitive) | ✓ | ✓ |
| `displayName` | ✓ | ✓ |
| `queryFrequency` | ✓ | — |
| `queryPeriod` | ✓ | — |
| `triggerOperator` (short / long form normalised) | ✓ | — |
| `triggerThreshold` | ✓ | — |

Deliberately **not** compared:

- `entityMappings`, `tactics`, `techniques`, `customDetails`,
  `alertDetailsOverride`, `incidentConfiguration` — JSON shapes differ
  between API responses, ARM templates, and YAML, producing false positives
  on every rule. Mirrors the reasoning in the `Test-RuleIsCustomised` function
  of [`Deploy-SentinelContentHub.ps1`](../../Deploy/content/Deploy-SentinelContentHub.ps1)
  (see its `entityMappings are NOT compared` comment block).
- `enabled` — `Deploy-CustomContent.ps1` legitimately deploys rules as
  `enabled=false` when dependencies are missing or KQL validation fails;
  `Deploy-SentinelContentHub.ps1`'s `-DisableRules` switch does the same for
  OoB content. Comparing this field would flag every rule deployed via either
  path. Drift detection focuses on intentional content edits.
- `[Deprecated]` rules — skipped by display-name match, mirroring the
  `[Deprecated]` skip guard inside the deploy loop of
  [`Deploy-SentinelContentHub.ps1`](../../Deploy/content/Deploy-SentinelContentHub.ps1).

## What each run does

The steps below are identical across both CI systems; only step 1 (auth) and
step 5 (commit/PR mechanics) differ, as noted in the per-CI sections.

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Daily 06:00 UTC                                                         │
│                                                                          │
│  1. Auth (GitHub OIDC login / ADO sc-sentinel-as-code, Sentinel Reader)  │
│  2. Fetch deployed rules + Content Hub templates + repo YAML index       │
│  3. For each deployed rule:                                              │
│       • Resolve source → Custom (YAML wins) / ContentHub / Orphan /      │
│         Managed                                                          │
│       • Compare fields (above)                                           │
│       • Custom drift   → rewrite the matched YAML in place, bump patch   │
│       • ContentHub drift → write a new YAML to                           │
│         Content/AnalyticalRules/AbsorbedFromPortal/ContentHub/{Solution}/│
│       • Orphan drift   → write a new YAML to                             │
│         Content/AnalyticalRules/AbsorbedFromPortal/Orphans/              │
│  4. If any drift detected:                                               │
│       • Write reports/sentinel-drift-{timestamp}.md  (full diffs)        │
│       • Write reports/sentinel-drift-{timestamp}.json (machine-readable) │
│  5. If git working tree dirty:                                           │
│       • Reset rolling branch from origin/main (avoids stale-base merge   │
│         conflicts)                                                       │
│       • Commit + force-push to auto/sentinel-drift-sync                  │
│       • Open or refresh PR to main                                       │
└──────────────────────────────────────────────────────────────────────────┘
```

If no drift is detected the script writes nothing — the working tree stays
clean, the bash step exits early, no PR is opened.

## Reports

Two files are written per run, both timestamped (`yyyy-MM-ddTHH-mmZ`) so
multiple runs accumulate without filename collisions.

### `reports/sentinel-drift-{timestamp}.md`

Human-readable. For each drifted rule, includes:

- A summary block (file/template/GUID/kind/yamlUpdated)
- Per-field diff:
  - **Short scalars** (severity, queryFrequency, etc) → inline
    `Deployed: \`X\` / Template: \`Y\``
  - **Multi-line** (query) → fenced unified-diff block (LCS-based, ordered
    like `git diff`) plus full deployed and template KQL bodies in
    fenced ` ```kql ` blocks for copy-paste.
- An orphan table at the bottom listing rules with no source-of-truth.

### `reports/sentinel-drift-{timestamp}.json`

Same data as the markdown, structured for downstream tooling. Full text of
deployed/expected values is included (no truncation).

### PR description

Both CI systems build a **deliberately short** PR description rather than
dumping the whole report body: a header, a link to the full report file, the
report's `## Summary` block (extracted with `sed`), and a bullet list of every
drifted rule (the report's `### ` headings). The Files Changed tab carries the
full report with diff blocks and complete KQL bodies.

The concise body matters more on Azure DevOps, where `az repos pr` truncates
`--description` at roughly 4000 characters (a full report with embedded KQL
would silently lose the second-onwards drifted rule). GitHub's PR body limit is
65,536 characters, so truncation is not a concern there, but the same focused
description is used for readability. On refresh, ADO rebuilds the body via
`az repos pr update` and GitHub via `gh pr edit --body-file`.

## GitHub Actions workflow

[`.github/workflows/sentinel-drift-detect.yml`](../../.github/workflows/sentinel-drift-detect.yml)
is the repo's primary CI implementation. The single `detect-drift` job runs on
`ubuntu-latest` with a 30-minute timeout.

### Authentication (OIDC)

The workflow authenticates to Azure with OpenID Connect via the composite action
[`.github/actions/azure-login-oidc`](../../.github/actions/azure-login-oidc),
the same service principal used by `sentinel-deploy.yml`. No client secret is
stored; the action federates a short-lived token from the three secrets below.
The SP needs at least **Microsoft Sentinel Reader** on the workspace.

### Secrets and variables

| Kind | Name | Purpose |
| --- | --- | --- |
| Secret | `AZURE_CLIENT_ID` | Service principal application (client) ID for OIDC |
| Secret | `AZURE_TENANT_ID` | Entra ID tenant ID |
| Secret | `AZURE_SUBSCRIPTION_ID` | Azure subscription ID (also passed to the script as `-SubscriptionId`) |
| Variable | `SENTINEL_RESOURCE_GROUP` | Resource group holding the workspace (`-ResourceGroup`) |
| Variable | `SENTINEL_WORKSPACE_NAME` | Log Analytics workspace name (`-Workspace`) |
| Variable | `SENTINEL_REGION` | Azure region, e.g. `uksouth` (`-Region`) |

Secrets and variables live under **Settings -> Secrets and variables ->
Actions**. `RepoPath` is set to `${{ github.workspace }}` so the script writes
YAML and reports into the checked-out tree.

### Permissions block

The workflow declares a least-privilege token at the top level:

| Scope | Value | Why |
| --- | --- | --- |
| `id-token` | `write` | Federate the OIDC token for Azure login |
| `contents` | `write` | `git push` the rolling `auto/sentinel-drift-sync` branch |
| `pull-requests` | `write` | `gh pr create` / `gh pr edit` |

The commit and PR steps authenticate with the default `GITHUB_TOKEN` (exposed
to `gh` as `GH_TOKEN`); no PAT is required.

### Pinned `powershell-yaml`

The workflow pins `powershell-yaml` to `0.4.12` via the `YAML_VERSION` env var,
installed through the composite action
[`.github/actions/setup-pwsh-modules`](../../.github/actions/setup-pwsh-modules)
with `install-pester: 'false'`. Pinning stops a PSGallery release that tightens
parser behaviour from silently breaking a scheduled drift run; bumping the
version is a one-line PR that re-runs the gate against the new release.

### Commit and PR flow

The `Commit, push, and open / refresh PR` step is guarded by
`if: ${{ inputs.reportOnly != true }}`, so a Report Only run never reaches it
(see [Report Only](#running-it)). When it does run it: checks the working tree
with `git status --porcelain` (exits early and cleanly if empty), stashes the
script's changes, resets `auto/sentinel-drift-sync` from `origin/main`, pops the
stash, stages only `Content/AnalyticalRules` and `reports`, commits, and
`git push --force-with-lease`. It then uses `gh pr list` to find an existing
open PR from the sync branch: if found it refreshes the body with
`gh pr edit --body-file`, otherwise it opens one with `gh pr create`.

### Report artefact upload

A final `Upload drift report artefact` step runs with `if: always()` and uploads
the whole `reports/` folder via `actions/upload-artifact@v6` as
`sentinel-drift-report-{run_id}`, with **30-day** retention and
`if-no-files-found: ignore`. This means a Report Only run still surfaces its
timestamped report as a downloadable artefact even though nothing is committed.

## Azure DevOps pipeline

[`Pipelines/Sentinel-Drift-Detect.yml`](../../Pipelines/Sentinel-Drift-Detect.yml)
is the functional mirror for teams running on Azure DevOps. It authenticates via
a service connection instead of OIDC and drives PRs with `az repos pr` instead
of `gh`.

### Required ADO assets

| Asset | Purpose | Notes |
| --- | --- | --- |
| Variable group `sentinel-deployment` | Provides `azureSubscriptionId`, `sentinelResourceGroup`, `sentinelWorkspaceName`, `sentinelRegion` | Shared with `Sentinel-Deploy.yml` |
| Service connection `sc-sentinel-as-code` | Sentinel API access | `Microsoft Sentinel Reader` is sufficient (no write needed) |
| Build identity Git permissions | `git push` and `az repos pr create` | See below |

### Granting Git permissions to the build identity

The pipeline uses `persistCredentials: true` to expose `$(System.AccessToken)`
to git, which authenticates as the project's **Build Service** identity.
ADO's default for that identity is read-only. Grant it three permissions
once, on the target repo:

**Project Settings → Repos → Repositories → `<repo>` → Security**

Pick the identity (typically `<repo> Build Service (<org>)` or
`Project Collection Build Service (<org>)`) and set:

| Permission | Setting |
| --- | --- |
| Contribute | Allow |
| Create branch | Allow |
| Contribute to pull requests | Allow |

This is the single most common cause of pipeline failure — symptoms include
`TF401027: You need the Git 'GenericContribute' permission` on push.

## Running it

### Scheduled

Both CI systems run automatically every day at 06:00 UTC. No action needed.

### Manual (with toggles)

On GitHub, **Actions -> Sentinel Drift Detection -> Run workflow** exposes the
same five toggles as ADO's **Pipelines -> Sentinel-Drift-Detect -> Run
pipeline**. The GitHub inputs map straight onto script switches; the ADO
parameters map to `-Flag` strings at compile time and then onto the switches:

| Toggle | Script switch | Default | Effect |
| --- | --- | :---: | --- |
| Fail (Pipeline / Workflow) When Drift Detected | `-FailOnDrift` | off | Exits non-zero if anything drifted (use to gate downstream jobs) |
| Report Only | `-ReportOnly` | off | Suppresses drift absorption (no YAML edits, no new YAMLs) and opens **no PR** on either CI system. The timestamped report is still written to `reports/` and, on GitHub, uploaded as the run artefact |
| Drift › Skip Content Hub Bucket | `-SkipContentHub` | off | Suppresses ContentHub comparison and absorption entirely |
| Drift › Skip Custom (Repo YAML) Bucket | `-SkipCustom` | off | Suppresses Custom comparison and absorption entirely |
| Drift › Skip Orphan (Ungoverned) Bucket | `-SkipOrphans` | off | Suppresses orphan reporting and absorption entirely |

The Content Hub solution catalogue is **not** exposed as a parameter — every
solution in the workspace is scanned every run. The report groups results by
solution so per-solution filtering on input is unnecessary. For ad-hoc
single-solution runs, invoke the script locally (next section).

> **Report Only still writes to disk.** `-ReportOnly` only skips the YAML
> mutations; the script still writes `reports/sentinel-drift-{timestamp}.{md,json}`
> whenever drift exists (the report gate is `$hasDrift -and -not $WhatIf`, not
> `-ReportOnly`). The working tree is therefore **not** clean after a Report Only
> run with drift. Both CI systems guard their commit/push/PR step so this report
> is never committed or turned into a PR: GitHub via `if: inputs.reportOnly != true`,
> and the ADO pipeline via the matching guard on its commit step. To suppress the
> report write itself as well, use `-WhatIf`.

### Local invocation

```powershell
./Tools/Test-SentinelRuleDrift.ps1 `
    -SubscriptionId "00000000-0000-0000-0000-000000000000" `
    -ResourceGroup  "rg-sentinel-prod" `
    -Workspace      "law-sentinel-prod" `
    -Region         "uksouth" `
    -ReportOnly                            # don't edit YAML (report still written)

# Filter to one solution (script only, not exposed in either CI toggle set)
./Tools/Test-SentinelRuleDrift.ps1 `
    -ResourceGroup "rg-sentinel-prod" `
    -Workspace     "law-sentinel-prod" `
    -Region        "uksouth" `
    -Solutions     "Microsoft Defender XDR" `
    -ReportOnly

# Fail the run if anything drifted (CI gating)
./Tools/Test-SentinelRuleDrift.ps1 ... -FailOnDrift
```

`-SubscriptionId` is optional locally; when omitted the script falls back to the
current Azure context (and both CI systems pass it explicitly). `-RepoPath`
defaults to the parent of the `Tools/` folder the script lives in, so a checkout
resolves `Content/AnalyticalRules/` and `reports/` automatically; the CI runs set
it explicitly to the workspace root. Az authentication falls back to
`Connect-AzAccount` when no current context exists.

### All script parameters

| Parameter | Type | Default | Purpose |
| --- | --- | --- | --- |
| `-SubscriptionId` | string | current Az context | Subscription holding the workspace |
| `-ResourceGroup` | string | (required) | Resource group of the workspace |
| `-Workspace` | string | (required) | Log Analytics workspace name |
| `-Region` | string | (required) | Azure region, e.g. `uksouth` |
| `-Solutions` | string[] | all | Scope OoB (ContentHub) drift to named solutions; does not affect Custom/Orphan |
| `-SeveritiesToInclude` | string[] | High, Medium, Low, Informational | Severity filter applied across all three buckets |
| `-RepoPath` | string | parent of `Tools/` | Repository root containing `Content/AnalyticalRules/` |
| `-SkipContentHub` | switch | off | Skip the ContentHub bucket |
| `-SkipCustom` | switch | off | Skip the Custom bucket |
| `-SkipOrphans` | switch | off | Skip the Orphan bucket |
| `-ReportOnly` | switch | off | Skip YAML mutations; still writes the report |
| `-FailOnDrift` | switch | off | Exit 1 when any drift or orphan is detected |
| `-IsGov` | switch | off | Target Azure Government (`AzureUSGovernment` in `Connect-AzureEnvironment`) |
| `-WhatIf` | switch | off | Skip report/artefact writes entirely; summary is still emitted |

The script auto-installs `powershell-yaml` if missing (the CI runs pin it to
`0.4.12`).

## How drift gets absorbed

### Custom drift (in-place YAML rewrite)

When a Custom rule is detected as drifted, the matching YAML file under
`Content/AnalyticalRules/**` is rewritten in place using surgical regex replacements:

| Field | Edit strategy |
| --- | --- |
| `severity`, `queryFrequency`, `queryPeriod`, `triggerThreshold`, `displayName` | Single-line `(?m)^field: ...` regex replace |
| `triggerOperator` | Replace + map API form back to YAML short form (`GreaterThan` → `gt`) |
| `query` | Replace the entire `query: \|` block scalar up to the next top-level YAML key, preserving 2-space indent |
| `version` | Patch component bumped (`1.0.0` → `1.0.1`) so smart-deploy picks up the change |

Everything else (`description`, `requiredDataConnectors`, `entityMappings`,
`tags`, comments, etc.) is preserved byte-for-byte. The PR's Files Changed
tab shows a clean, surgical YAML diff.

If the regex doesn't match (e.g. a YAML uses non-standard formatting), the
script logs `No-op on YAML: ... (regex did not match — manual edit required)`
and the JSON report records `yamlUpdated: false`. The reviewer can then make
the edit by hand based on the full deployed/expected values in the report.

### ContentHub drift (template promoted to Custom YAML)

When a Content-Hub-deployed rule has been edited in the portal, the script
serialises the deployed state into a fresh Custom YAML at:

```
Content/AnalyticalRules/AbsorbedFromPortal/ContentHub/{SolutionSlug}/{RuleSlug}.yaml
```

The serialiser emits the same field set the rest of the repo's Custom rules
use: `id`, `name`, `description`, `severity`, scheduling fields (Scheduled
only), `enabled`, `tactics`, `relevantTechniques`, `query` (block scalar),
`entityMappings`, `eventGroupingSettings`, `incidentConfiguration`,
`version: 1.0.0`, `kind`, and `tags`. The rule's existing resource GUID is
reused as the YAML's `id:` value, and the YAML is tagged with
`AbsorbedFromPortal-ContentHub` plus the originating solution name for audit.

Because the YAML now exists, the next deploy run treats the rule as Custom
(governance handed off from `Deploy-SentinelContentHub.ps1` to
`Deploy-CustomContent.ps1`). The Custom deployer's PUT request to the same
resource URI overwrites the template-tracked rule with the absorbed YAML's
contents, completing the promotion.

### Orphan drift (export to a governed Custom YAML)

A rule with neither a template link nor a matching repo YAML is exported to:

```
Content/AnalyticalRules/AbsorbedFromPortal/Orphans/{RuleSlug}.yaml
```

Same serialisation as the ContentHub case, but tagged
`AbsorbedFromPortal-Orphan`. After the PR merges, the next deploy treats the
rule as a normal Custom rule.

### Reviewer workflow for absorbed YAMLs

The auto-generated `AbsorbedFromPortal/` location is intentionally separated
from the curated category folders. Reviewers can:

1. Approve the PR as-is and let the file live under `AbsorbedFromPortal/`.
2. Move the file into the appropriate category folder (e.g.
   `Content/AnalyticalRules/MicrosoftEntraID/`) during PR review. The `id:` GUID stays
   the same, so the next drift run still resolves the rule to the new path.
3. Delete the file in the PR if the rule should not be governed (e.g. it was
   a one-off test in the portal). The Custom branch will fail to find a YAML
   on the next run and the rule is re-exported as an orphan; that is the
   signal to delete the rule from the portal as well.

The slug used in the filename comes from the rule's `displayName` via
`ConvertTo-FileSlug`: every run of non-alphanumeric characters (the regex
`[^A-Za-z0-9]+`, which also collapses underscores) is replaced with a single
hyphen, the result is trimmed of leading/trailing hyphens, and it is capped at
80 characters. The solution slug uses the same function with a 60-character cap.
An empty slug falls back to `rule`, and when no solution attribution is
available the rule lands under `ContentHub/Unattributed/`.

## Limitations

- **YAML formatting requirements.** The query block must use `query: |`
  block-scalar style with 2-space body indent (the repo style produced by
  `.development/normalise_sentinel_rules.py`). Non-standard layouts may cause
  the query rewrite to be skipped — the report flags this.
- **Single-select solution filter at the pipeline level was deliberately
  removed.** ADO parameter `values:` lists are evaluated at compile time and
  hardcoding solution names couples the pipeline to one workspace. Local
  invocation supports `-Solutions`.
- **Report accumulation.** At one report per drift-detected day, the
  `reports/` folder grows by ~365 entries per year. If volume becomes
  noisy, add a cleanup step before the commit:
  `find reports/sentinel-drift-*.md -mtime +90 -delete`.
- **Rolling auto-branch is force-pushed.** If a previous drift PR is open
  and unmerged, the next run rewrites its commits. The PR refreshes to show
  the latest run's drift only — historical run data is preserved on `main`
  when PRs merge, not on the rolling branch.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `TF401027: You need the Git 'GenericContribute' permission` (ADO) | Build identity not granted Contribute on the repo | [Grant the permission](#granting-git-permissions-to-the-build-identity) |
| `remote: Permission ... denied` on push or `gh pr create` fails 403 (GitHub) | Workflow token lacks scope, or the repo/org blocks Actions from creating PRs | Confirm the `permissions:` block grants `contents: write` and `pull-requests: write`, and that **Settings -> Actions -> General -> Allow GitHub Actions to create and approve pull requests** is enabled |
| PR description shows only the first drifted rule | Pre-fix: full report was being passed as `--description` and ADO truncated at ~4000 chars | Already fixed — description is now built deliberately from summary + rule list |
| `Added in both` merge conflict on second PR | Pre-fix: report filename was `sentinel-drift-latest.md` and the auto-branch was based on stale local HEAD | Already fixed — filenames are timestamped and the branch is reset from `origin/main` |
| 20+ Custom drifts all on `enabled` only | Pre-fix: `enabled` was compared, but `Deploy-CustomContent.ps1` legitimately deploys disabled when deps missing | Already fixed — `enabled` excluded from comparison |
| Orphan reports include `BuiltInFusion` etc. | Pre-fix: managed rule kinds were being treated as Custom-or-Orphan | Already fixed — `Fusion`, `MicrosoftSecurityIncidentCreation`, `MLBehaviorAnalytics`, `ThreatIntelligence` are excluded |
| `No-op on YAML: ... (regex did not match)` | YAML uses non-standard formatting (e.g. `query: >` folded scalar instead of `query: \|` literal) | Open the YAML, hand-apply the change shown in the report, run the deploy pipeline |
| Pipeline runs but no PR opens | Working tree clean → no drift detected | Confirmed by the `No drift detected — working tree clean` log line. Not a failure. |

## Field-by-field comparison reference

For each comparison field, the table below shows what the YAML, ARM template,
and deployed-rule shapes look like, and how the script normalises them
before comparing.

| Field | YAML form | ARM template form | Deployed (API) form | Normalisation |
| --- | --- | --- | --- | --- |
| `query` | `query: \|` block scalar | `properties.query` string | `properties.query` string | Whitespace collapsed via `'\s+' → ' '` then trimmed |
| `severity` | Title case (`Medium`) | Title case | Title case | Case-insensitive equality |
| `displayName` | `name:` field (sentence case) | `properties.displayName` | `properties.displayName` | Verbatim |
| `queryFrequency`/`queryPeriod` | ISO 8601 (`PT30M`) | Same | Same | Verbatim string equality |
| `triggerOperator` | Short form (`gt`/`lt`/`eq`/`ne`) | Long form (`GreaterThan`/...) | Long form | YAML mapped to long form before compare; written back to YAML in short form |
| `triggerThreshold` | Integer | Integer | Integer | Cast to `[int]` |

## Tests

Pester 5 tests covering the four substantive pure functions
(`Compare-SentinelRule`, `Update-RuleYamlFile`, `Get-LineDiff`,
`Resolve-RuleSource`) live at
[`Tests/Test-SentinelRuleDrift.Tests.ps1`](../../Tests/Test-SentinelRuleDrift.Tests.ps1).
See [Pester Tests](../Tests/Pester-Tests.md) for prerequisites, the AST-extraction
pattern this repo uses, and how to add new test files.

```powershell
# Run the suite
Invoke-Pester -Path Tests/Test-SentinelRuleDrift.Tests.ps1 -CI

# Detailed output (per-test pass/fail)
Invoke-Pester -Path Tests/Test-SentinelRuleDrift.Tests.ps1 -Output Detailed

# One Describe block
Invoke-Pester -Path Tests/Test-SentinelRuleDrift.Tests.ps1 -FullName '*Update-RuleYamlFile*'
```

Manual integration smoke test against a live workspace (read-only):

```powershell
./Tools/Test-SentinelRuleDrift.ps1 -ResourceGroup ... -Workspace ... -Region uksouth -ReportOnly
```

## Related scripts

- [`Deploy/content/Deploy-SentinelContentHub.ps1`](../../Deploy/content/Deploy-SentinelContentHub.ps1) —
  deploys OoB content. Its `Test-RuleIsCustomised` function is the
  comparison-logic ancestor of `Compare-SentinelRule`. The deploy script
  uses it at deploy-time to skip overwriting customised rules; the drift
  script uses an extended version of it at detection-time to surface them.
- [`Deploy/content/Deploy-CustomContent.ps1`](../../Deploy/content/Deploy-CustomContent.ps1) —
  deploys Custom YAML rules. Its `Deploy-CustomDetections` function holds the
  `operatorMap` (`gt` -> `GreaterThan`, etc.) that the drift script's
  `triggerOperator` normalisation mirrors.

## Authoring with GitHub Copilot

Copilot tooling for the drift sub-system:

- Agent `Sentinel-As-Code: Drift Engineer` — owns the whole drift
  flow: triaging the daily 06:00 UTC auto-PR, adjusting diff
  sensitivity in `Test-SentinelRuleDrift.ps1`, deciding what to
  absorb / reject / promote across the Custom / ContentHub /
  Orphan buckets.
- Agent `Sentinel-As-Code: Test Engineer` — for changes to
  `Tests/Test-SentinelRuleDrift.Tests.ps1`.
- Agent `Sentinel-As-Code: Pipeline Engineer` — for changes to
  the workflow / pipeline YAML.

See [GitHub Copilot setup](../GitHub/GitHub-Copilot.md) for the full layout.

## TODO

- Optional report cleanup step in the pipeline once `reports/` exceeds a
  practical size.

The module-extraction work shipped: `Sentinel.Common.psm1` is
now the single source of truth for `Write-PipelineMessage`,
`Invoke-SentinelApi`, and `Connect-AzureEnvironment`. The Pester
suite for `Update-RuleYamlFile`, `Compare-SentinelRule`,
`Get-LineDiff`, and `Resolve-RuleSource` is at
[`Tests/Test-SentinelRuleDrift.Tests.ps1`](../../Tests/Test-SentinelRuleDrift.Tests.ps1)
(58 assertions).
