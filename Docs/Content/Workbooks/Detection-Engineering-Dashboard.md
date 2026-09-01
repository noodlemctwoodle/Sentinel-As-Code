# Detection Engineering Dashboard

A ten-tab workbook giving a detection-engineering team a single pane over the
health, coverage, fidelity, efficiency and lifecycle of a Microsoft Sentinel
detection portfolio. It ships as a gallery notebook at
[`Content/Workbooks/DetectionEngineering/`](../../../Content/Workbooks/DetectionEngineering)
and deploys like any other custom workbook, see
[Workbooks](../Workbooks.md) for the format and deploy mechanics.

Most Sentinel workbooks answer "what is attacking us". This one answers "is our
detection estate actually working", which is a different question and one the
built-in content largely leaves alone. It is built for the recurring detection
review rather than for incident response.

## Contents

- [Where to run it](#where-to-run-it)
- [Prerequisites](#prerequisites)
- [Parameters](#parameters)
- [The tabs](#the-tabs)
  - [Overview](#overview)
  - [Detection Coverage](#detection-coverage)
  - [Defender & Custom Detections](#defender--custom-detections)
  - [Rule Inventory & Health](#rule-inventory--health)
  - [Efficacy & Fidelity](#efficacy--fidelity)
  - [Incident Metrics](#incident-metrics)
  - [Data & Ingestion](#data--ingestion)
  - [Lifecycle & Deprecations](#lifecycle--deprecations)
  - [Engineering Velocity](#engineering-velocity)
- [A worked weekly review](#a-worked-weekly-review)
- [Data sources](#data-sources)
- [Query patterns worth knowing](#query-patterns-worth-knowing)
- [Deploying it](#deploying-it)
- [Troubleshooting](#troubleshooting)
- [Extending it](#extending-it)
- [Notes and limitations](#notes-and-limitations)

## Where to run it

**The Microsoft Defender portal is required**: *Microsoft Sentinel > Threat
management > Workbooks*. This is not a preference, and the workbook is not
supported in the Azure portal.

Two reasons it is a hard requirement:

- The **Defender & Custom Detections** tab queries `AlertInfo`, which exists only
  in the Defender advanced-hunting data plane. Run elsewhere, that entire tab
  returns nothing, and with it the only view of Defender custom detections.
- Microsoft Sentinel in the Azure portal **retires on 31 March 2027**. Building a
  detection-review habit around a portal with a published end date is wasted
  effort.

The remaining tabs will render in the Azure portal Sentinel Workbooks gallery,
but that is an unsupported configuration rather than a fallback: you get an
incomplete workbook and a silently empty tab.

## Prerequisites

| Requirement | Needed by | If missing |
| --- | --- | --- |
| Reader on the selected workspaces | Every KQL panel | Panels error |
| **The Microsoft Defender portal** | The workbook as a whole; `AlertInfo` in particular | Defender & Custom Detections is empty. Unsupported configuration |
| Sentinel **auditing and health monitoring** enabled | Rule Inventory & Health, Engineering Velocity | Those two tabs are empty; the Defender tab still shows live detection signal |
| Reader on the Lifecycle tab's **Audit workspace** | Classic vs DCR-based custom tables | That one panel errors |
| `Heartbeat` data | Reporting agents (AMA vs legacy) | Empty, which is normal for a workspace with no VM or agent heartbeats |

Health and audit diagnostics are enabled under Microsoft Sentinel **Settings >
Auditing and health monitoring**; they populate `SentinelHealth` and
`SentinelAudit` respectively. **Neither is on by default**, and neither
backfills, so a freshly enabled workspace shows an empty Rule Inventory tab
until rules have run for a while. That is the single most common reason for a
blank tab.

## Parameters

Three global parameters sit at the top and cross-filter every applicable panel.

| Parameter | Type | Default | Scope |
| --- | --- | --- | --- |
| **Time range** | Time picker (1d, 7d, 14d, 30d, 60d, 90d, custom allowed) | Last 90 days | Every panel |
| **Workspaces (log data)** | Multi-select workspace picker | All accessible | Every KQL panel, fanned out via `crossComponentResources` and unioned |
| **Severity** | Multi-select (High / Medium / Low / Informational) | All | Overview, Coverage, Defender, Efficacy, Incidents |

Severity deliberately does **not** filter the rule-health, ingestion, lifecycle
or velocity tabs. A rule failing to execute is a failure regardless of the
severity it would have raised, and ingestion volume has no severity at all.

Two hidden parameters drive behaviour rather than filtering:

- `selectedTab` backs the tab strip and every group's `conditionalVisibility`.
  It is seeded to `overview` so the workbook renders on first load. Without a
  seeded value the whole area below the tab strip is blank until you click a tab.
- `selectedRule` carries the row clicked in *Per-rule execution health* into the
  drill-down panel beneath it, defaulting to `""` (meaning "show all rules").

The Lifecycle tab adds a local **Audit workspace** picker. The ARM Tables API
targets one workspace at a time, so that panel cannot fan out like the KQL ones.
Switch it to audit each workspace's custom tables in turn.

## The tabs

### Overview

Portfolio health at a glance, intended as the thing you screenshot for a
stand-up.

| Panel | Notes |
| --- | --- |
| Key indicators | Six tiles: incidents, false-positive incidents, alerts fired, active detections, rules failing, rules executing |
| Incidents per day by severity | Binned on `CreatedTime`, not ingestion time |
| Alerts per day by severity | Binned on `TimeGenerated` |
| Analytics rule execution health (range) | Runs, failures and a computed failure rate, banded into a colour-coded verdict |

The health banding is:

| Failure rate | Verdict |
| --- | --- |
| >= 20% | Unhealthy (red) |
| >= 5% | Degraded (orange) |
| otherwise | Healthy (green) |

Those thresholds are hard-coded in the panel's `case` expression. Edit them in
the Advanced Editor if your tolerance differs.

### Detection Coverage

Coverage derived from **firing** detections in `SecurityAlert`, with technique
IDs resolved to MITRE names via an in-query `datatable` of roughly 200 technique
mappings (sub-techniques inherit their parent's name through a split on `.`).

| Panel | Notes |
| --- | --- |
| Alerts by MITRE tactic (mapped only) | Bar chart, unmapped alerts excluded |
| Tactic coverage status | All 14 tactics, left-joined against firing alerts, **gaps sorted first** so absence is visible rather than implied |
| Technique activity (top 100) | With resolved names and a highest-severity column |
| Unmapped detections | The hygiene backlog: alerts with no tactic or technique |
| Detection to tactic / technique mapping | Raw per-detection mapping, top 200 |

The unmapped panel exists because an alert with no MITRE mapping is invisible in
every other coverage view. Treated as coverage it inflates your numbers; treated
as a backlog it becomes a work item. This workbook does the latter.

### Defender & Custom Detections

Built on `AlertInfo`, so it spans Defender for Endpoint, Office 365, Identity and
Cloud Apps plus onboarded Sentinel alerts. `DetectionSource has "Custom"`
isolates custom-detection rules, the Defender equivalent of analytics-rule
authoring.

Panels: Defender detection indicators (tiles), alerts by detection source, alerts
by service source, custom detections with volume and severity, MITRE technique
coverage (Defender-native), custom-detection alerts per day, and alerts by
category.

This tab is the fallback when `SentinelHealth` and `SentinelAudit` are not
enabled, since it needs neither.

### Rule Inventory & Health

Sourced from `SentinelHealth` analytics-rule run events, the source of truth for
rule execution.

| Panel | Notes |
| --- | --- |
| Rule portfolio indicators | Rules executing, rules with failures, silent rules, run failure rate % |
| Per-rule execution health | Runs, failures, failure rate, alerts generated, last run and status. **Click a row to drill down** |
| Run history, selected rule | Driven by `selectedRule`; shows all rules until one is clicked |
| Silent rules | Executing but zero alerts generated across the range |
| Recent failed rule runs | With `Reason` and `Description` |
| Rule execution failures per day | Trend |

**Silent rules** are the quiet value here. `ExtendedProperties.AlertsGeneratedAmount`
lets the query find rules that run cleanly and never fire, with no join required.
A silent rule is not necessarily broken (some detections genuinely should be
rare), but a rule silent for 90 days usually means broken logic, a renamed
field, or a dead log source. Cross-reference it against the **stale tables**
panel on the ingestion tab.

Clicking a row sets `selectedRule` via `exportFieldName`. Click the same row
again, or clear the selection, to reset to all rules.

### Efficacy & Fidelity

Signal-to-noise and analyst outcomes. Noise is ranked by raw alert volume plus an
alerts-per-active-day rate, so a detection that fired 500 times in one day is
distinguishable from one that fires five times every day.

Fidelity uses closed-incident `Classification` (`TruePositive`, `FalsePositive`,
`BenignPositive`, `Undetermined`). The **tuning candidates** panel applies a
deliberate threshold: at least 5 closed incidents and 100% of them false
positive. One false positive is noise in the statistical sense; five out of five
is a pattern worth acting on.

### Incident Metrics

The SOC feedback loop. MTTA and MTTR are medians (50th percentile), not means, so
one abandoned incident does not distort the figure.

- MTTA approximates triage as `FirstModifiedTime - CreatedTime` in minutes.
- MTTR approximates resolution as `ClosedTime - CreatedTime` in hours.

Both filter out negative values defensively. Also here: created versus closed
flow (the backlog trend), classification split, load by owner with unassigned
incidents grouped explicitly, and ageing open incidents.

### Data & Ingestion

Detections are only as good as their data. Volume per table, billable GB per day,
top tables by volume, and **stale tables** that have not ingested for three or
more days.

Stale tables are a silent killer of coverage: the rule keeps running, keeps
succeeding, and quietly matches nothing. That combination looks healthy on every
other panel, which is exactly why this one exists.

### Lifecycle & Deprecations

A live countdown against three dates, banded PASSED / IMMINENT (30 days) / SOON
(120 days) / Planned:

| Milestone | Date |
| --- | --- |
| HTTP Data Collector API support ends | 14 September 2026 |
| Log Analytics agent (MMA/OMS) cloud upload can stop | 2 March 2026 |
| Microsoft Sentinel in the Azure portal retires | 31 March 2027 |

The **Classic vs DCR-based custom tables** panel is the authoritative answer to
"which of my `_CL` tables are on the legacy ingestion path". That flag is table
*metadata* (`schema.tableSubType`), not present in `Usage` or in the log rows,
which is why this single panel is an ARM call (`queryType 12`) against the Log
Analytics Tables API rather than KQL. Rows showing `Classic` are the ones to
migrate first.

For the full migration workflow see the
[Classic-to-DCR toolkit](../../Tools/ClassicToDcr/Classic-to-DCR-Toolkit.md),
which assesses blast radius before you change anything.

### Engineering Velocity

Detection-as-code throughput and change governance from `SentinelAudit`: changes
per day, operation mix, top rule editors, and a change audit trail.

Useful for sprint reporting, and for spotting out-of-process changes. If this
repo is deploying your rules, the caller on most rows should be the deployment
service principal. Rows attributed to a human are worth a look.

## A worked weekly review

One way to use the tabs in sequence:

1. **Overview** for the headline: is the failure rate banded Healthy, and did
   incident volume move?
2. **Rule Inventory & Health**, sort by failure rate descending. Anything above
   zero gets triaged from *Recent failed rule runs*, where `Reason` usually names
   the cause directly (missing table, semantic error, timeout).
3. Same tab, **silent rules**. Anything silent for the whole range gets checked
   against **Data & Ingestion > stale tables**. A silent rule plus a stale table
   is a broken pipeline, not a quiet detection.
4. **Efficacy & Fidelity > tuning candidates**. These are your tuning backlog for
   the sprint, ordered by how much analyst time they are consuming.
5. **Detection Coverage > tactic coverage status**, gaps first. Compare against
   the portal MITRE ATT&CK page to separate "no rule exists" from "rule exists
   but has not fired".
6. **Lifecycle** once a month rather than weekly, to keep the migration
   countdown honest.

## Data sources

| Table | Used for |
| --- | --- |
| `SecurityAlert` | Detection output, MITRE tactic and technique coverage, noise |
| `SecurityIncident` | Fidelity by classification, MTTA/MTTR, ageing, ownership |
| `AlertInfo` | Defender-native alerts including custom detections, service source, techniques |
| `SentinelHealth` | Rule execution health, silent and failing rules |
| `SentinelAudit` | Detection-as-code velocity and change audit |
| `Usage` | Ingestion volume, cost drivers, stale log sources |
| `Heartbeat` | AMA versus legacy agent inventory on the Lifecycle tab |

Every one of these is reachable through the unified advanced-hunting data plane
in the Defender portal, so all queries are advanced-hunting-native.

The template ships every step on the standard **Logs (Analytics)** source so it
imports cleanly. Individual high-volume steps can be flipped to the **Sentinel
data lake** source in-portal for long-retention trend analysis, via the step's
data-source dropdown. Note that *Set by query* visualisation is not supported on
the data-lake source, and results should be time-filtered and column-projected
for performance.

## Query patterns worth knowing

If you are editing panels, these recur throughout and are worth understanding
before you change one.

**Incident deduplication.** `SecurityIncident` appends a row per update, so a
raw `count()` counts edits, not incidents. Every incident panel starts with:

```kusto
| summarize arg_max(TimeGenerated, *) by IncidentNumber
```

Remove that line and your numbers inflate silently.

**The tile pattern.** Most KPI tiles are a `union isfuzzy=true` of single-row
subqueries, each tagged with a `Metric` name and an ordinal `o` used only to
force display order before being projected away:

```kusto
union isfuzzy=true
 (incidents | summarize Value = todouble(count()) | extend Metric = "Incidents", o = 1),
 ...
| sort by o asc
| project Metric, Value
```

`isfuzzy=true` means a missing table degrades that tile rather than failing the
whole panel.

**The Defender tiles differ.** That tab pivots a single-row `summarize` instead,
which avoids repeating the source table five times:

```kusto
| project packed = pack_all()
| mv-expand kind=array packed
| project Metric = tostring(packed[0]), Value = todouble(packed[1])
```

**Tactics and techniques parsing.** Those columns are sometimes a JSON array and
sometimes a comma-separated string, depending on the alert provider, so every
coverage query normalises first:

```kusto
| extend TechArr = iff(Techniques startswith "[", todynamic(Techniques), split(Techniques, ","))
| mv-expand T = TechArr to typeof(string)
```

**Severity ranking.** `AlertSeverity` and `Severity` are strings, so `max()` on
them is lexicographical and would rank "Medium" above "High". Panels that need a
top severity map to an integer `SevRank` first, then map back for display.

**Explicit time filtering on incident charts.** Panels binning `CreatedTime` or
`ClosedTime` add their own `between ({TimeRange:start} .. {TimeRange:end})`,
because the workbook's implicit filter applies to `TimeGenerated`. Without it, an
incident created last year but updated today lands in today's bin.

## Deploying it

The workbook deploys with the rest of the custom content, no special handling:

```powershell
./Deploy/content/Deploy-CustomContent.ps1 `
    -ResourceGroupName 'rg-sentinel' `
    -WorkspaceName     'law-sentinel'
```

`metadata.json` carries the display name, description and `category`
(`Sentinel`). It deliberately omits `workbookId`, matching the other
hand-authored workbooks in the repo, so `Deploy-CustomWorkbooks` derives a
deterministic GUID by hashing `<WorkspaceResourceId>-DetectionEngineering`. That
keeps repeat deploys idempotent per workspace. If you need the same workbook
resource ID across workspaces, add a `workbookId` as described in
[Workbooks](../Workbooks.md#why-use-a-stable-guid).

To import it by hand instead: Defender or Azure portal > Sentinel > **Workbooks
> Add workbook > Edit**, open the **Advanced Editor** (`</>`), replace the
contents with `workbook.json`, **Apply**, then **Save**.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Everything below the tab strip is blank | `selectedTab` has no value | Should not happen (it is seeded to `overview`); if you have edited the parameter block, restore the default |
| Rule Inventory & Health entirely empty | `SentinelHealth` not streaming | Enable Sentinel **Settings > Auditing and health monitoring**. No backfill, so allow time for rules to run |
| Engineering Velocity entirely empty | `SentinelAudit` not streaming | Same setting as above |
| Defender & Custom Detections empty | Not running in the Defender portal | Open the workbook from the Defender portal. The Azure portal cannot reach `AlertInfo` |
| Classic vs DCR panel errors or is empty | Audit workspace unset, or no Reader on it | Set the **Audit workspace** picker on that tab. If your environment's JSONPath rejects the `CustomLog` filter, drop the `[?(...)]` clause and sort by *Table type* instead |
| Reporting agents grid empty | No `Heartbeat` data | Normal for a workspace with no VMs or agents |
| Incident counts look too high | A panel is missing the `arg_max` dedup | See [Query patterns](#query-patterns-worth-knowing) |
| A tile shows blank rather than zero | Source table absent in every selected workspace | Expected; `isfuzzy=true` degrades that tile only |

## Extending it

The workbook is a plain gallery notebook, so editing is portal-first: change it
in the Advanced Editor, then paste the JSON back over `workbook.json` and commit.

Adding a tab means two coordinated edits:

1. A new entry in the `LinkItem` tab strip (`type: 11`) with a unique
   `subTarget` value.
2. A new group (`type: 12`) whose `conditionalVisibility` compares `selectedTab`
   to that same `subTarget`.

New KQL panels need `queryType: 0`, `resourceType:
microsoft.operationalinsights/workspaces`, `crossComponentResources: ["{Workspaces}"]`
and `timeContextFromParameter: "TimeRange"` to inherit the global parameters.
Omitting `crossComponentResources` silently scopes the panel to a single default
workspace instead of the user's selection, which is easy to miss because the
panel still returns data.

After editing, run the workbook Pester suite:

```powershell
Invoke-Pester -Path Tests/Test-WorkbookJson.Tests.ps1
```

## Notes and limitations

- Coverage reflects **firing** detections only. Pair it with the portal
  **MITRE ATT&CK** page for *designed* coverage, meaning rules that exist but
  have not fired in the selected range.
- MTTA and MTTR are approximations derived from incident timestamps. They are not
  SLA-grade timers, and `FirstModifiedTime` counts any modification as triage,
  including automation-rule edits.
- The MITRE technique-name `datatable` is a point-in-time snapshot embedded in
  the query. New technique IDs appear as bare IDs with no name until it is
  refreshed; they are never dropped.
- `Failure rate %` counts `Status == "Failure"` only. If Microsoft emits a
  `Warning` status for analytics-rule runs in your tenant (their own
  `AnalyticsHealthAudit` workbook filters for it, though the health-table
  reference documents only Success and Failure), those runs sit in the
  denominator but not the numerator and the rate reads slightly optimistic.
- Row limits are applied per panel (200 on per-rule health and audit trails, 100
  on most detail grids, 50 on the efficacy tables). Large estates will truncate;
  the ordering is chosen so the truncated tail is the least interesting part.
- Workbook KQL is **not** covered by the `kql-validate` CI job, which scans
  analytical rules, hunting queries, parsers, summary rules and Defender
  detections only. [`Test-WorkbookJson.Tests.ps1`](../../../Tests/Test-WorkbookJson.Tests.ps1)
  validates JSON structure, not the queries inside it, so a query change can pass
  CI and still fail in the portal.
