# Drift: compare, sync and report

`Compare-iSOCContent` finds what was changed in the workspace and not in
the repository. `Sync-iSOCContent` writes those changes into the
repository, so the next deploy keeps them instead of undoing them, and
`Export-iSOCDriftReport` writes the report the drift pipelines commit.
Together they will replace `Tools/Test-SentinelRuleDrift.ps1` at the
26.11.0 cut-over; until then the drift pipelines run the script by default
(the Azure DevOps one runs the commands with `engine` `module`, see
[The pipeline switch](Pipeline-Switch.md)), and
[Sentinel drift detection](../../Tools/Sentinel-Drift-Detection.md)
describes them.

Analytics rules are the one content type the commands compare so far, as
the script did. Every other type gains Compare and Sync as it is ported
([Content types](Content-Types.md)).

```powershell
Import-Module ./Modules/iSOCDeployments
Connect-AzAccount
Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel

# What drifted, changing nothing.
$drift = Compare-iSOCContent
$drift.Items | Where-Object State -ne InSync | Format-Table Name, State, Reason

# Which files a sync would write, writing none.
$drift | Sync-iSOCContent -WhatIf

# The drift pipeline: compare, absorb, report, and fail when anything drifted.
$drift = Compare-iSOCContent -Severity High, Medium
$drift | Sync-iSOCContent | Export-iSOCDriftReport
exit [int]$drift.HasDrift
```

`Tests/iSOCDeployments/Drift.Tests.ps1` runs the script's own `Invoke-Main`
and the three commands against the same stand-in workspace: every rule in
this repository as deploy sends it, some of them edited in the portal,
with Content Hub rules (clean and customised), portal-only rules, a Fusion
rule and a deprecated one. It requires the same counts, the same drifted
rules and changed fields, and the same files written, with the defaults,
report only, and one solution and two severities. It runs again on what
was absorbed and finds nothing.

## From the script

| `Test-SentinelRuleDrift.ps1` | Command |
| --- | --- |
| `-SubscriptionId`, `-ResourceGroup`, `-Workspace` | `Connect-iSOCWorkspace` first (or `-Context`) |
| `-Region`, `-IsGov` | Not needed: read from the workspace and the Az sign-in |
| `-Solutions` | `Compare-iSOCContent -Solution` |
| `-SeveritiesToInclude` | `Compare-iSOCContent -Severity` |
| `-RepoPath` | `Compare-iSOCContent -RepoPath` |
| `-SkipContentHub`, `-SkipCustom`, `-SkipOrphans` | `Compare-iSOCContent -ExcludeSource ContentHub`, `Custom`, `Orphan` |
| `-ReportOnly` | Leave out `Sync-iSOCContent` |
| `-FailOnDrift` | `exit [int]$drift.HasDrift` |
| `-WhatIf` | `-WhatIf` on `Sync-iSOCContent` and `Export-iSOCDriftReport` |

## What a compare does

1. Reads every analytics rule in the workspace with the preview alert
   rules API, which keeps sub-techniques.
2. Classes each rule by where its source of truth is, in this order:
   - a Fusion, MicrosoftSecurityIncidentCreation, MLBehaviorAnalytics or
     ThreatIntelligence rule is `Managed` by Microsoft and not compared;
   - a rule of a severity not asked for, or one marked `[Deprecated]`, is
     `Skipped`;
   - a rule whose id is a repository rule's id is governed by that file,
     even when it is also linked to a Content Hub template: that is how a
     rule absorbed from the portal stays governed by the repository. The
     file is compared as `Deploy-iSOCContent` would send it; a file that
     does not validate is `Skipped`;
   - a rule linked to a Content Hub template the workspace has is compared
     with the template's rule; `-Solution` limits these to the solutions
     named, and a rule of another solution is `Skipped`;
   - anything else is `PortalOnly`: nothing accounts for it.
   A source left out with `-ExcludeSource` has its rules `Skipped`.
3. Compares each governed rule with its source, field by field, with the
   comparers the analytics rule type names (`Get-iSOCContentType
   AnalyticsRule` lists them): kind and display name exactly, severity in
   any case, the query ignoring whitespace but not case, and for Scheduled
   rules the frequency and period as durations (`PT24H` is `P1D`), the
   trigger operator in any case and the threshold as a number. A field the
   source leaves unset is not compared. Whether a rule is enabled is not
   compared: deploy sends rules disabled for a missing dependency and
   Community rules, and Content Hub deployment can send them all disabled.
4. Logs a summary and returns the result. Nothing is changed in the
   workspace or the repository.

## The result

`Compare-iSOCContent` returns an `iSOCDeployments.DriftResult`:
`GeneratedAt`, `Workspace`, `ResourceGroup`, `RepoPath`, `ContentTypes`,
`Items`, `Summary` and `HasDrift` (anything `PortalEdit`,
`ContentHubCustomised` or `PortalOnly`). Each item is an
`iSOCDeployments.DriftItem`:

| Property | Meaning |
| --- | --- |
| `ContentType`, `Name`, `ResourceName`, `Kind` | The content type, the display name, the workspace's name for it (a rule's id) and its kind |
| `Source` | `Custom`, `ContentHub`, `Orphan` or `Managed`; nothing when it was filtered out first |
| `State` | `InSync`, `PortalEdit` (a repository rule changed in the portal), `ContentHubCustomised` (a Content Hub rule changed from its template), `PortalOnly`, `Managed` or `Skipped` |
| `Reason` | Why, for `Skipped`, `Managed` and `PortalOnly` |
| `SourceRef`, `Solution` | The repository file, relative to the repository, or the Content Hub solution |
| `Enabled` | Whether it is enabled in the workspace |
| `Modifications` | The fields that differ: `Field`, `Deployed` (the workspace's value) and `Expected` (the source's), as they are, not normalised |
| `SyncAction`, `SyncPath` | Filled in by `Sync-iSOCContent` |

`Summary` holds the counts the report shows: `totalDeployed`,
`contentHubClean`, `contentHubDrift`, `customClean`, `customDrift`,
`orphan`, `managed` and `skipped`.

## Sync

`Sync-iSOCContent` takes the result and, for each drifted item:

- `PortalEdit`: rewrites the rule's file in place with the workspace's
  values for the fields that changed, each single-line field on its own
  line and the query block whole with its line breaks, and raises the
  file's patch version so the next deploy sends it. Everything else in the
  file is left byte for byte, its line endings included. A field the file
  has no line for is not added, and the item's `SyncAction` is `NoMatch`:
  that file needs editing by hand.
- `ContentHubCustomised`: writes the rule to a new file under
  `Content/AnalyticalRules/AbsorbedFromPortal/ContentHub/<solution>/`
  (`Unattributed` when the solution is not known) that keeps the rule's
  id, so the next deploy governs it from the repository instead of the
  template.
- `PortalOnly`: writes the rule to a new file under
  `Content/AnalyticalRules/AbsorbedFromPortal/Orphans/`.

A new file holds the rule's name, description, severity, schedule and
trigger, whether it is enabled, tactics and techniques, query, entity
mappings, event grouping and incident configuration, as the script wrote
them, and is tagged with where it came from. Custom details, the alert
details override and suppression are not carried yet, as they were not by
the script; that comes with export. A file whose content would
not change is left alone, so a run that finds the same drift again leaves
the working tree clean. Nothing is deleted, and the workspace is not
touched. Each item records what was done in `SyncAction` (`Updated`,
`Created`, `Unchanged`, `NoMatch` or `Failed`) and the file in
`SyncPath`. With `-WhatIf` nothing is written.

## The report

`Export-iSOCDriftReport` writes `sentinel-drift-<yyyy-MM-ddTHH-mmZ>.json`
and `.md` to `reports/` in the repository, or to `-Path`, the names the
drift pipelines look for. When nothing drifted it writes nothing, so the
pipeline has nothing to commit.

The JSON holds `generatedAt`, `workspace`, `resourceGroup`, `summary`,
`drifted` (each rule changed in the workspace with its changed fields in
full) and `orphans`. After a sync, a drifted rule says whether its file
changed (`yamlUpdated`), and an absorbed one where it went
(`absorbedPath`, `absorbedAction`). Paths are repository-relative, each
rule is named by its display name and its id (`ruleName`), and no full
resource id, so no subscription id, is written. The Markdown is the same for the pull
request, with a line diff of each changed query, and its headings say
what was done: auto-synced or report only.

`MIGRATION.md` edits E22 to E24 list every way the commands differ from
the script: what is compared and how, the query written with its line
breaks, excluded sources skipped rather than exported again, three
commands instead of one, and the report without `ruleId`.
