# Sentinel-As-Code maturity assessment

The Documenter scores a workspace from 0 to 5 across eleven capability areas
and writes the result to `_raw/maturity.json`. The renderer turns it into
`91-maturity-assessment.md`, the SharePoint site shows it on the dashboard
and keeps a history of the scores, and the pipelines take the target level
as a parameter.

This page explains what the assessment is, how a score is computed, what
each criterion reads, and how to add one.

## What it is, and what it is not

It is a **capability reference point** computed from the workspace's
deployed configuration and the last 30 days of activity: which rules are
enabled, which tables have data, whether playbooks failed, whether
incidents are classified when they close. It exists to rank the work, give
a before-and-after for changes, and show a trend across the daily runs.

It is not an audit, a certification or a risk rating. It cannot see people,
skills, runbooks that live outside Sentinel or how well an analyst
investigates. Those are listed under `outOfScope` in the output so nobody
reads the number as more than it is.

The methodology is this project's own. It borrows nothing from any
commercial or trademarked maturity model: the areas, the criteria, the
scale and the scoring are defined in
[`Private/Resources/maturity-criteria.json`](../../../Tools/Documenter/Private/Resources/maturity-criteria.json)
and computed by
[`Private/Get-SentinelMaturity.ps1`](../../../Tools/Documenter/Private/Get-SentinelMaturity.ps1).
The criterion set, the estate-flow view and the detection-headroom idea
come from the Sentinel health-check script written by Lasitha R, who gave
it to the project.

## The areas

| Id | Area | What it covers |
|---|---|---|
| DET | Detection engineering | Rules exist, are maintained, map entities and produce incidents worth having |
| PLT | Platform and collection | The workspace and its collection pipeline are current, governed and resilient |
| COV | Telemetry coverage | The sources an investigation needs are connected and producing data |
| AUT | Automation and response | Triage, enrichment and response run without an analyst at the keyboard |
| MON | Monitoring coverage | What is ingested is watched, across the kill chain and the platform itself |
| INC | Incident management | Incidents are acknowledged, worked, classified and closed in time |
| INV | Investigation and evidence | Evidence is complete, retained and recoverable when an investigation needs it |
| TI | Threat intelligence | Indicators arrive from more than one source and detections read the current schema |
| HNT | Threat hunting | Hunting is recorded, resourced with content and feeds detection engineering |
| LOG | Log management and cost | Retention, tiers and caps are set deliberately rather than left at defaults |
| GOV | Governance and access | Access follows least privilege and the workspace is protected from accidents |

Sixty criteria sit under those areas, between three and eight each. Every
criterion has an id of the form `SAC-<AREA>-NN`, a `kind` (`practice` for
something the team does, `coverage` for something the workspace has), a
`weight` (1, or 1.5 for the ones that matter most), an `effort` (Low,
Medium, High), an `impact` sentence, a `guidance` sentence, one or more
NIST CSF 2.0 subcategory references and a `source`.

## Levels

| Level | Name |
|---|---|
| 0 | Not in place |
| 1 | Initial |
| 2 | Developing |
| 3 | Established |
| 4 | Measured |
| 5 | Optimised |

The level is the whole-number part of the score. The default target is 3;
the collector's `-TargetMaturityLevel` and the pipelines' target-level
parameter change it.

## How a criterion resolves

Each criterion's `source` resolves to **Met**, **Gap** or **Unknown**:

| Source kind | Resolves from | Met | Gap | Unknown |
|---|---|---|---|---|
| `gapRule` | the SENT rule's outcome in `gap-checks.json` | `Passed` | `Fired` | `Errored`, `Undefined` or not evaluated |
| `metric` | a value computed from the `_raw` captures, compared with `op` and `value` | comparison holds | comparison fails | the metric is null because its file was not captured |
| `allOf` | its sources | all Met | any Gap | otherwise |
| `anyOf` | its sources | any Met | all Gap | otherwise |

A `gapRule` criterion that resolves to Gap quotes the finding's evidence
from `gap-analysis.json`. A `metric` criterion fills the `{metric}` token
in its `evidence.met` or `evidence.gap` template with the value.

**Unknown never counts against a workspace.** A capture that failed (an
RBAC gap, a throttled query, a region that does not support a feature)
leaves its criteria Unknown and out of the denominator, rather than scoring
as a Gap. The confidence label says how much of an area could be evaluated.

## How a score is computed

For each area:

```
score      = round(5 * weight(Met) / weight(Met + Gap), 2)
level      = floor(score)
confidence = Good      when 6 or more criteria were evaluated
             Moderate  when 4 or 5
             Indicative otherwise
             Not assessed when none could be evaluated (score is null)
```

The overall score is the mean of the area scores that exist. The target is
met when every assessed area is at or above the target level;
`areasBelowTarget` lists the ones that are not, with the gap to close.

## The roadmap

Every Gap criterion goes on the roadmap with:

- `areaLift`: how much its area's score would rise if it were Met,
  `5 * weight / weight(Met + Gap in the area)`;
- `overallLift`: that lift divided by the number of assessed areas;
- `projectedScore`: the overall score after this and every entry above it.

The order is `overallLift` descending, then effort (Low first), then id.
**Quick wins** are the first five Low-effort entries in that order.

## The NIST CSF 2.0 rollup

Each criterion references one or two subcategories of the NIST
Cybersecurity Framework 2.0 (NIST CSWP 29, February 2024). The output
counts Met, Gap and Unknown criteria per function (Govern, Identify,
Protect, Detect, Respond, Recover) and per referenced subcategory, so a
reader who works in CSF terms can see which outcomes the workspace
evidence supports.

The identifiers are NIST's; the one-line outcome text in the criteria
file is a short paraphrase for display, not the official wording. NIST
publications are US Government work and not subject to copyright in the
United States.

## Metrics catalogue

`New-MaturityMetrics` computes every metric the criteria can reference. A
metric is `null` when its source file is absent (the criterion is then
Unknown), and `0` or `false` when the file exists but holds nothing.

| Metric | Source file | Meaning |
|---|---|---|
| `enabledRules` | `alert-rules.json` | enabled rules of any kind |
| `customRules` | `alert-rules.json` | enabled Scheduled/NRT rules with no `alertRuleTemplateName` |
| `tacticsCovered` | `alert-rules.json`, `mitre-attack.json` | MITRE tactics with at least one enabled rule |
| `dcrCount` | `dcrs.json` | data collection rules in scope |
| `laQueryLogs7d` | `la-query-logs.json` | audited queries in 7 days |
| `connectorFailures7d` | `sentinel-health-summary.json` | failed data-fetcher runs in 7 days |
| `sentinelHealthRows7d` | `sentinel-health-summary.json` | SentinelHealth rows in 7 days |
| `billableGb30d` | `tables-with-data.json` | billable GB in 30 days |
| `entraTablesPresent` | `tables-with-data.json` | Entra ID tables ingesting in 7 days |
| `xdrTablesPresent` | `xdr-table-presence.json` | Defender XDR tables with rows |
| `mdcConnector` | `data-connectors-classic.json` | an `AzureSecurityCenter` connector exists |
| `mdtiConnector` | `data-connectors-classic.json` | a Microsoft Defender Threat Intelligence connector exists |
| `entityAnalyticsEnabled` | `settings.json` | `EntityAnalytics` has at least one entity provider |
| `playbooks` | `playbooks.json` | Logic App playbooks |
| `watchlists` | `watchlists.json` | watchlists |
| `incidents30d`, `closedIncidents30d` | `incidents-summary.json` | incidents and closures in 30 days |
| `mttaMinutes` | `incidents-mttr.json` | mean time to acknowledge |
| `searchOrRestoreJobs` | `search-jobs.json`, `restore-logs.json` | search jobs plus restores |
| `lakeExtendedTables` | `workspace-tables.json` | tables on the DataLake or Auxiliary plan, or with total retention beyond interactive |
| `tablesWithCustomRetention` | `workspace-tables.json`, `workspace.json` | tables whose retention differs from the workspace default |
| `summaryRules` | `summary-rules.json` | summary rules |
| `tiIndicators30d`, `mdtiRows30d` | `threat-intel-counts.json` | indicators in 30 days, all sources and Microsoft sources |
| `tiObjects30d` | `threat-intel-objects.json` | STIX objects in 30 days |
| `bookmarks` | `bookmarks.json`, else `bookmarks-count.json` | bookmarks; the list API refuses a workspace with many bookmarks, and the collector then keeps the count the service reported |
| `huntingQueries` | `hunting-queries.json` | hunting queries |
| `highPrivilegeAssignments` | `rbac-workspace.json` | Owner and Contributor assignments at workspace scope |
| `sentinelRoleAssignments` | `rbac-workspace.json` | assignments of any `Microsoft Sentinel *` role |

The computed values are written to `maturity.json` under `metrics`, so a
surprising score can be traced to its inputs without re-running anything.

## Reading `maturity.json`

```
methodology        name, version, criteriaVersion, scaleNote
generatedAtUtc
targetLevel        the -TargetMaturityLevel the run used
targetLevelName
targetMet          true when every assessed area is at or above the target
areasBelowTarget   [{id, name, score, level, gapToTarget}]
overall            {score, level, levelName}
levels             the six level names
areas              [{id, name, description, score, level, levelName, met, gap, unknown,
                     evaluated, confidence, criteria[{id, kind, name, status, evidence,
                     weight, effort, impact, guidance, csf[], source}]}]
roadmap            [{priority, criterionId, area, areaName, name, kind, evidence, impact,
                     guidance, effort, csf[], areaLift, overallLift, projectedScore}]
quickWins          the first five Low-effort roadmap entries
csf                {source, functions[{id, name, criteria, met, gap, unknown}],
                    subcategories[{id, function, outcome, met, gap, unknown, criteriaIds[]}]}
outOfScope         [{area, reason}]
totals             {criteria, met, gap, unknown}
metrics            every computed metric, null where not captured
```

## Adding a criterion

1. Decide what decides it. If a SENT rule already checks the condition,
   use `{"kind": "gapRule", "rule": "SENT-0NN"}`. If a number from the
   captures decides it, add the metric to `New-MaturityMetrics` (null when
   the file is absent) and use `{"kind": "metric", "path": "...", "op":
   "gt|ge|eq|lt|le", "value": ...}`. Combine with `allOf` or `anyOf`.
2. Add the criterion under its area in `maturity-criteria.json` with the
   next free `SAC-<AREA>-NN` id, a weight, an effort, impact and guidance
   sentences, and one or two CSF subcategory ids that exist in the
   reference block (add the subcategory there if it is new).
3. Add an assertion to
   [`Tests/Documenter/Get-SentinelMaturity.Tests.ps1`](../../../Tests/Documenter/Get-SentinelMaturity.Tests.ps1)
   and regenerate the fixture's `maturity.json`:

   ```powershell
   . ./Tools/Documenter/Private/Get-SentinelGap.ps1
   . ./Tools/Documenter/Private/Get-SentinelMaturity.ps1
   $raw = './Tests/Documenter/Fixtures/sample/_raw'
   $res = './Tools/Documenter/Private/Resources'
   $out = [System.Collections.Generic.List[object]]::new()
   $null = Get-SentinelGap -InputRoot $raw -ResourcesRoot $res -RulesPath "$res/best-practices.json" -GapChecksPath './Tools/Documenter/Private/GapChecks.ps1' -OutcomeCollector $out
   Get-SentinelMaturity -InputRoot $raw -ResourcesRoot $res -CriteriaPath "$res/maturity-criteria.json" -GapOutcomes $out.ToArray() |
       ConvertTo-Json -Depth 16 | Set-Content "$raw/maturity.json" -Encoding UTF8
   ```

The schema guards in the test suite reject an unknown metric, area, rule
or CSF id, a duplicate or misnamed criterion id, and an em-dash in the
text, so a mistake fails the PR gate rather than the nightly run.

## Related

- [Sentinel Documenter](Sentinel-Documenter.md): the collector, the gap
  engine and the output tree.
- [Renderer design](Documenter-Renderer-Design.md): how
  `91-maturity-assessment.md` is drawn.
- [SharePoint site](Sentinel-SharePoint-Site.md): the Maturity tab and
  the score history.
