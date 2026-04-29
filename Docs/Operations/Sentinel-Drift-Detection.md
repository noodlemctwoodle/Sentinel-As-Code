# Sentinel Analytics Rule Drift Detection

Detects rules that have been edited directly in the Microsoft Sentinel portal,
bypassing the DevOps deployment pipelines. Every drift bucket is absorbed back
into the repo as YAML under `AnalyticalRules/`, then committed onto a rolling
auto-sync branch and surfaced via an auto-generated pull request for human
review.

| What | Where |
| --- | --- |
| Detection script | [`Scripts/Test-SentinelRuleDrift.ps1`](../../Scripts/Test-SentinelRuleDrift.ps1) |
| ADO pipeline | [`Pipelines/Sentinel-Drift-Detect.yml`](../../Pipelines/Sentinel-Drift-Detect.yml) |
| Generated reports | `reports/sentinel-drift-{UTC-timestamp}.{md,json}` |
| Auto-sync branch | `auto/sentinel-drift-sync` (rolling, force-pushed each run) |
| Schedule | Daily at 06:00 UTC |

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
`AnalyticalRules/AbsorbedFromPortal/` is governed via the Custom branch on
every subsequent run, even if it still carries an `alertRuleTemplateName` link
on the workspace side.

| Bucket | Match logic | Action on drift |
| --- | --- | --- |
| **Custom** | The rule's resource-name GUID matches a YAML `id:` under `AnalyticalRules/**` | Existing YAML rewritten in place; patch version bumped |
| **ContentHub** | `properties.alertRuleTemplateName` matches a Content Hub `contentTemplate.contentId` | New YAML written to `AnalyticalRules/AbsorbedFromPortal/ContentHub/{Solution}/{Slug}.yaml`; reuses the rule's resource GUID as `id:` so the next deploy run takes over governance from the template |
| **Orphan** | Neither of the above matches | New YAML written to `AnalyticalRules/AbsorbedFromPortal/Orphans/{Slug}.yaml` so the rule becomes a governed Custom rule |
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
  on every rule. Mirrors the comment block at
  [`Deploy-SentinelContentHub.ps1:904-907`](../../Scripts/Deploy-SentinelContentHub.ps1).
- `enabled` — `Deploy-CustomContent.ps1` legitimately deploys rules as
  `enabled=false` when dependencies are missing or KQL validation fails;
  `Deploy-SentinelContentHub.ps1`'s `-DisableRules` switch does the same for
  OoB content. Comparing this field would flag every rule deployed via either
  path. Drift detection focuses on intentional content edits.
- `[Deprecated]` rules — skipped by display-name match, mirroring
  [`Deploy-SentinelContentHub.ps1:1153-1157`](../../Scripts/Deploy-SentinelContentHub.ps1).

## What the pipeline does

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Daily 06:00 UTC                                                         │
│                                                                          │
│  1. Auth (sc-sentinel-as-code service connection — Sentinel Reader)      │
│  2. Fetch deployed rules + Content Hub templates + repo YAML index       │
│  3. For each deployed rule:                                              │
│       • Resolve source → Custom (YAML wins) / ContentHub / Orphan /      │
│         Managed                                                          │
│       • Compare fields (above)                                           │
│       • Custom drift   → rewrite the matched YAML in place, bump patch  │
│       • ContentHub drift → write a new YAML to                          │
│         AnalyticalRules/AbsorbedFromPortal/ContentHub/{Solution}/        │
│       • Orphan drift   → write a new YAML to                            │
│         AnalyticalRules/AbsorbedFromPortal/Orphans/                      │
│  4. If any drift detected:                                               │
│       • Write reports/sentinel-drift-{timestamp}.md  (full diffs)        │
│       • Write reports/sentinel-drift-{timestamp}.json (machine-readable) │
│  5. If git working tree dirty:                                           │
│       • Reset rolling branch from origin/main (avoids stale-base merge   │
│         conflicts)                                                       │
│       • Commit + force-push to auto/sentinel-drift-sync                  │
│       • Open or refresh PR to main                                       │
└─────────────────────────────────────────────────────────────────────────┘
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

ADO truncates `--description` at ~4000 chars, so the PR description is
**deliberately short**: header + link to the full report file + summary
table + bullet list of every drifted rule. The Files Changed tab carries the
full report. The PR description is rebuilt and refreshed on every run via
`az repos pr update`.

## Configuration

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

### Pipeline (scheduled)

Runs automatically every day at 06:00 UTC. No action needed.

### Pipeline (manual)

**Pipelines → Sentinel-Drift-Detect → Run pipeline** exposes five toggles:

| Toggle | Default | Effect |
| --- | --- | --- |
| Fail Pipeline When Drift Detected | off | Exits non-zero if anything drifted (use to gate downstream pipelines) |
| Report Only | off | Writes the report but does not absorb drift (no YAML edits, no new YAMLs, no PR) |
| Drift › Skip Content Hub Bucket | off | Suppresses ContentHub comparison and absorption entirely |
| Drift › Skip Custom (Repo YAML) Bucket | off | Suppresses Custom comparison and absorption entirely |
| Drift › Skip Orphan (Ungoverned) Bucket | off | Suppresses orphan reporting and absorption entirely |

The Content Hub solution catalogue is **not** exposed as a parameter — every
solution in the workspace is scanned every run. The report groups results by
solution so per-solution filtering on input is unnecessary. For ad-hoc
single-solution runs, invoke the script locally (next section).

### Local invocation

```powershell
./Scripts/Test-SentinelRuleDrift.ps1 `
    -ResourceGroup "rg-sentinel-prod" `
    -Workspace    "law-sentinel-prod" `
    -Region       "uksouth" `
    -ReportOnly                            # don't edit YAML

# Filter to one solution (script only — not exposed in the pipeline)
./Scripts/Test-SentinelRuleDrift.ps1 `
    -ResourceGroup "rg-sentinel-prod" `
    -Workspace    "law-sentinel-prod" `
    -Region       "uksouth" `
    -Solutions    "Microsoft Defender XDR" `
    -ReportOnly

# Fail the pipeline if anything drifted (CI gating)
./Scripts/Test-SentinelRuleDrift.ps1 ... -FailOnDrift
```

The script auto-installs `powershell-yaml` if missing. Az authentication
falls back to `Connect-AzAccount` when no current Azure context exists.

## How drift gets absorbed

### Custom drift (in-place YAML rewrite)

When a Custom rule is detected as drifted, the matching YAML file under
`AnalyticalRules/**` is rewritten in place using surgical regex replacements:

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
AnalyticalRules/AbsorbedFromPortal/ContentHub/{SolutionSlug}/{RuleSlug}.yaml
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
AnalyticalRules/AbsorbedFromPortal/Orphans/{RuleSlug}.yaml
```

Same serialisation as the ContentHub case, but tagged
`AbsorbedFromPortal-Orphan`. After the PR merges, the next deploy treats the
rule as a normal Custom rule.

### Reviewer workflow for absorbed YAMLs

The auto-generated `AbsorbedFromPortal/` location is intentionally separated
from the curated category folders. Reviewers can:

1. Approve the PR as-is and let the file live under `AbsorbedFromPortal/`.
2. Move the file into the appropriate category folder (e.g.
   `AnalyticalRules/MicrosoftEntraID/`) during PR review. The `id:` GUID stays
   the same, so the next drift run still resolves the rule to the new path.
3. Delete the file in the PR if the rule should not be governed (e.g. it was
   a one-off test in the portal). The Custom branch will fail to find a YAML
   on the next run and the rule is re-exported as an orphan; that is the
   signal to delete the rule from the portal as well.

The slug used in the filename comes from the rule's `displayName` (non-word
characters collapsed to single hyphens, capped at 80 characters). The
solution slug uses the same rules with a 60-character cap. When no solution
attribution is available the rule lands under `ContentHub/Unattributed/`.

## Limitations

- **YAML formatting requirements.** The query block must use `query: |`
  block-scalar style with 2-space body indent (the repo style enforced by
  `Scripts/normalise_sentinel_rules.py`). Non-standard layouts may cause
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
| `TF401027: You need the Git 'GenericContribute' permission` | Build identity not granted Contribute on the repo | [Grant the permission](#granting-git-permissions-to-the-build-identity) |
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
See [Pester Tests](../Development/Pester-Tests.md) for prerequisites, the AST-extraction
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
./Scripts/Test-SentinelRuleDrift.ps1 -ResourceGroup ... -Workspace ... -Region uksouth -ReportOnly
```

## Related scripts

- [`Scripts/Deploy-SentinelContentHub.ps1`](../../Scripts/Deploy-SentinelContentHub.ps1) —
  deploys OoB content. Function `Test-RuleIsCustomised` (line 826) is the
  comparison-logic ancestor of `Compare-SentinelRule`. The deploy script
  uses it at deploy-time to skip overwriting customised rules; the drift
  script uses an extended version of it at detection-time to surface them.
- [`Scripts/Deploy-CustomContent.ps1`](../../Scripts/Deploy-CustomContent.ps1) —
  deploys Custom YAML rules. Function `Deploy-CustomDetections` (line 1077)
  is the source of the `triggerOperator` mapping table the drift script
  reuses.

## TODO

- Extract `Write-PipelineMessage`, `Invoke-SentinelApi`, and
  `Connect-AzureEnvironment` into a shared `Sentinel.Common.psm1` module.
  They're currently duplicated across this script,
  `Deploy-SentinelContentHub.ps1`, and `Deploy-CustomContent.ps1`. The
  drift script carries `# TODO: extract to Sentinel.Common.psm1` breadcrumbs
  on each duplicated function.
- Optional report cleanup step in the pipeline once `reports/` exceeds a
  practical size.
- Pester tests for `Update-RuleYamlFile`, `Compare-SentinelRule`,
  `Get-LineDiff`, and `Resolve-RuleSource`.
