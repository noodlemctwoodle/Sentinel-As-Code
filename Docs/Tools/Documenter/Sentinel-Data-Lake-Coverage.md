# Sentinel Data Lake, Documenter coverage

What the Sentinel Documenter captures and renders for Microsoft Sentinel Data
Lake. Scope reference for anyone asking *"what does this tool tell me about
Lake?"* without needing to read the renderer source.

For Lake itself, start with the
[Microsoft Sentinel Data Lake overview](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-overview)
on Microsoft Learn.

---

## The Lake API

Sentinel Data Lake is **tenant-wide** but provisioned as a single Azure
resource pinned to one subscription / resource group / region. The relevant
ARM surface is **not** under `Microsoft.SecurityInsights`, it lives on a
separate resource provider:

| Property | Value |
|---|---|
| Resource provider | `Microsoft.SentinelPlatformServices` |
| Resource type | `sentinelPlatformServices` |
| API version | `2025-04-01-preview` |
| Cardinality | One per tenant |
| Scope of resource | Subscription / RG (chosen at onboarding) |
| Region | Same as the primary Sentinel workspace |
| Resource name | `msg-resources-<guid>` (system-generated) |

Probing `Microsoft.SecurityInsights/dataLake` against a workspace returns
**400 NoRegisteredProviderFound**, this was the path most operators reach
for first, but it does not exist. Workspace-level `/settings`,
`/onboardingStates`, etc. carry no Lake-related fields either.

### Documenter capture method

The exporter ([`Tools/Documenter/Export-SentinelInventory.ps1`](../../../Tools/Documenter/Export-SentinelInventory.ps1),
`Try-Capture 'sentinel-data-lake'`) does a single Resource Graph query
across every subscription the executing identity can read:

```kql
Resources
| where type =~ "microsoft.sentinelplatformservices/sentinelplatformservices"
| project id, name, location, resourceGroup, subscriptionId,
          properties, identity, systemData
```

This handles the cross-subscription case (Lake billed to a different sub
than the workspace's). Result is saved to `_raw/sentinel-data-lake.json`, 
non-empty array means Lake is onboarded, empty array means it isn't.

---

## Detection signals (in priority order)

The renderer ORs three signals to decide whether to surface Lake content.
Each is captured separately so a reviewer can audit the decision.

| # | Signal | Source | Strength |
|---|---|---|---|
| 1 | `Microsoft.SentinelPlatformServices/sentinelPlatformServices` exists | Resource Graph capture | **Authoritative** |
| 2 | `workspace.properties.features.unifiedSentinelBillingOnly = true` | `workspace.json` | Necessary but not sufficient |
| 3 | At least one workspace table has `plan = 'DataLake'` | `workspace-tables.json` | Confirms active routing |

A workspace can be on `unifiedSentinelBillingOnly` without the tenant being
onboarded to Lake (the billing flag is set independently). Conversely, a
Lake-onboarded tenant may have no tables on `plan = DataLake`, every
workspace table is auto-mirrored to Lake at the same retention by default.

---

## What section 88 renders

[`88-sentinel-data-lake.md`](../../../Tools/Documenter/Convert-SentinelInventoryToMarkdown.ps1)
(emitted by the renderer at line ~3825) is the user-facing surface. It
composes the following blocks; each is rendered conditionally on captured
state.

### 1. Headline (4-state)

One of four narrative variants based on `(Lake enrolled?) × (any Lake-only tables?)`:

- Enrolled + Lake-only tables → "active with Lake GB / month"
- Enrolled + no Lake-only tables → "enrolled but unused, here are migration candidates"
- Not enrolled + >30 GB/month → "consider enrolling, here's why"
- Not enrolled + low volume → "Lake not cost-relevant yet"

### 2. Enrollment signals table

Three rows mapping the captured signals to current values and a one-line
interpretation. The platform-services resource is row 1 (primary).

### 3. Lake resource detail (conditional on signal 1)

Full audit panel from the captured ARM resource: resource ID, region,
billing subscription/RG, provisioning state, system-assigned managed
identity, **onboarded-by** / **onboarded-at** timestamps. Answers
"when was Lake onboarded and by whom?" from the doc.

### 4. Lake architecture (Mermaid flowchart, static)

Visualises the data flow: Source → Analytics tier ↔ Mirror ↔ Lake tier ↔
KQL jobs / notebooks / graph / MCP tools. Renders only when Lake is
enrolled.

### 5. Tier distribution (pie, conditional)

Every operational table grouped into one of:
- Analytics only (Lake not enrolled)
- Analytics + Lake mirror (default for Lake-enrolled tenants)
- Analytics + Lake extended (`totalRetentionDays > retentionDays`)
- Lake only (`plan = DataLake`)

Suppressed when fewer than 2 buckets are populated (single-slice pies are
visually meaningless).

### 6. Retention split (xychart-beta bar, conditional)

Top 10 tables by Lake-only retention days (the portion of total retention
that bills against the Lake-storage meter). Renders only when at least
one table has `totalRetentionInDays > retentionInDays`.

### 7. Lake-only tables

Explicit `plan = DataLake` table list with retention columns. When empty,
the prose explains how to switch a table's tier in the Defender portal.

### 8. Auto-ingested asset data

Detects asset-family system tables that Lake auto-creates on tenant
onboarding:

| Pattern | Family |
|---|---|
| `IdentityInfo` | Microsoft Entra (identity) |
| `BehaviorAnalytics` | Microsoft Sentinel UEBA (asset enrichment) |
| `OfficeSharePoint` / `Exchange` / `Teams` | Microsoft 365 (activity) |
| `EntityGraph*` | Microsoft Sentinel graph (entities) |
| `Asset*` | Azure Resource Graph (assets) |

Each row carries the table name + ingest-state (*Receiving data* / *Defined,
no data*).

### 9. Cost split (Analytics vs Lake)

Two-row table comparing GB / 30d and estimated monthly cost between the
Analytics-tier and DataLake-plan buckets, sourced from `cost-estimate.json`.

### 10. Lake billing meters (reference, static)

All five Lake-specific meters documented in one table:

| Meter | Charged per | Applies to |
|---|---|---|
| Data lake ingestion | GB | Lake-only ingest (mirrored ingest is free) |
| Data processing | GB | Transformations on Lake-only ingest |
| Data lake storage | GB · month | Lake retention beyond Analytics period (6:1 compression) |
| Data lake query | GB scanned | KQL queries and KQL jobs |
| Advanced data insights | compute hour | Notebook sessions, graph build/query (12/32/80 vCore pools) |

Plus three reader-orienting notes (mirroring-is-free, 6:1 compression,
auxiliary-logs / search / archive meters fold into Lake meters).

### 11. Lake-derived capabilities (reference, static)

9 features mapped to (Defender portal surface, billing meter):

- KQL exploration over Lake → Data lake query
- KQL jobs (promote Lake → Analytics) → Data lake query
- Jupyter notebooks → Advanced data insights
- Sentinel graph (embedded) → no charge
- Custom graphs → Advanced data insights
- MCP server (data exploration) → Lake query
- MCP entity analyzer → SCU + Lake query
- Auto-ingested asset data → ingestion + storage
- 12-year affordable retention → Lake storage

### 12. Migration candidates

Top 10 Analytics-plan tables ≥0.5 GB / 30d (typical Lake-tier candidates:
verbose Defender XDR advanced hunting, raw firewall, EDR telemetry). Each
row carries a "Consider DataLake plan if rule queries are infrequent"
recommendation.

### 13. When to enroll / 14. When to stay on legacy

Prose bullets. The "stay on legacy" block calls out the **CMK gotcha**:
Sentinel Data Lake does not support Customer-Managed Keys, so workspaces
using CMK cannot use Lake experiences.

### 15. References (8 Microsoft Learn links)

Overview, onboarding, billing#data-lake-tier, manage-data-overview, KQL
overview, KQL jobs, notebooks-overview, sentinel-graph-overview.

---

## Topology + cost integration

Section 88 is the deep-dive, but Lake state also flows into two other
sections:

### `83-data-collection.md`, topology flowchart

The workspace topology emits a `DL[(Sentinel Data Lake)]` cylinder when any
of the three detection signals fires. The cylinder is wired into the
workspace subgraph alongside the Log Analytics cylinder, Analytics rules,
and (conditionally) Basic / Auxiliary plan nodes and the Long-term archive
node.

### `84-cost-estimate.md`, Sankey + cost split

The cost calculator ([`Tools/Documenter/Private/Get-SentinelCostEstimate.ps1`](../../../Tools/Documenter/Private/Get-SentinelCostEstimate.ps1))
recognises the `DataLake` plan as one of the four ingestion buckets
(Analytics / Basic / Auxiliary / DataLake). Unit prices come from the
`cost-meters.json` catalogue ([`Tools/Documenter/Private/Resources/cost-meters.json`](../../../Tools/Documenter/Private/Resources/cost-meters.json)),
which maps Azure Retail Prices meter names to plan categories:

```json
{
  "id": "DataLakeIngestion",
  "description": "Sentinel Data Lake per-GB ingestion.",
  "meterContains": ["Data Lake", "Ingestion"]
}
```

DataLake-plan tables surface in the cost Sankey's right column as
*"LA-rate billing"* (Lake-rate is grouped with the LA-rate family for the
purposes of the Sentinel-rate vs LA-rate split).

---

## Captures consumed

| Capture file | Used for |
|---|---|
| `_raw/sentinel-data-lake.json` | Primary detection signal + resource detail panel |
| `_raw/workspace.json` | `features.unifiedSentinelBillingOnly` + region context |
| `_raw/workspace-tables.json` | Per-table plan + retention split for tier distribution / retention chart |
| `_raw/tables-with-data.json` | Operational-table classification (90-day billable filter) |
| `_raw/cost-estimate.json` | Cost split table + migration-candidate rows |

No new captures were required to add Section 88, it composes from existing
inventory.

---

## Known gaps and forward work

- **Per-Lake-meter cost attribution.** The Documenter currently shows
  Analytics vs DataLake plan-level cost. It does not break out the 5
  individual Lake meters (ingestion / processing / storage / query /
  advanced data insights) because the Retail Prices API names them at the
  catalogue level, not per-workspace-usage. Reading Microsoft Cost
  Management's per-meter usage detail would require a separate exporter
  capture against the Cost Management API.
- **Lake-resident asset detection breadth.** The asset-data block detects
  five known families. As Lake expands its auto-ingested system tables
  (Defender threat intelligence, Microsoft Purview signals, etc.) the
  pattern list in [`Convert-SentinelInventoryToMarkdown.ps1`](../../../Tools/Documenter/Convert-SentinelInventoryToMarkdown.ps1)
  (search `_TopologyBucketFor` / asset table detection) should be
  extended.
- **CMK incompatibility surface.** "Lake doesn't support CMK" is currently
  prose in *When to stay on legacy*. A gap rule (`SENT-xxx`) flagging a
  workspace that has both CMK configured AND `unifiedSentinelBillingOnly`
  set would be a useful sanity check, Microsoft's docs say these states
  are mutually exclusive in practice.
- **Lake-tier ingest history.** The cost split shows the current month's
  Lake ingest in GB but not a per-day trend. A `lake-ingest-daily.json`
  capture (KQL against the new Lake-specific Usage rows when those become
  queryable) would unlock a line chart.
- **Pester coverage for Section 88.** The renderer test suite currently
  asserts that 88 renders against the fixture set but doesn't deeply
  exercise the four headline-narrative branches or the conditional charts.
  Adding fixture variants (Lake-onboarded vs not, with and without
  extended-retention tables) would catch regressions.

---

## Source map

| File | Role |
|---|---|
| [`Tools/Documenter/Export-SentinelInventory.ps1`](../../../Tools/Documenter/Export-SentinelInventory.ps1) | `Try-Capture 'sentinel-data-lake'` (Resource Graph query) |
| [`Tools/Documenter/Convert-SentinelInventoryToMarkdown.ps1`](../../../Tools/Documenter/Convert-SentinelInventoryToMarkdown.ps1) | Section 88 emit block (`Write-Section '88-sentinel-data-lake.md'`) |
| [`Tools/Documenter/Private/Get-SentinelCostEstimate.ps1`](../../../Tools/Documenter/Private/Get-SentinelCostEstimate.ps1) | DataLake plan handling in the cost split |
| [`Tools/Documenter/Private/Resources/cost-meters.json`](../../../Tools/Documenter/Private/Resources/cost-meters.json) | Lake meter → category mapping |
| [`Tools/Documenter/Private/Get-EffectiveConnectors.ps1`](../../../Tools/Documenter/Private/Get-EffectiveConnectors.ps1) | Asset-table family inference (`_ActiveTableFamily`) |

---

## References

- [Microsoft Sentinel Data Lake overview](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-overview)
- [Onboard to Microsoft Sentinel data lake](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-onboarding)
- [Data lake tier billing](https://learn.microsoft.com/azure/sentinel/billing#data-lake-tier)
- [Manage data tiers and retention in Microsoft Sentinel](https://learn.microsoft.com/azure/sentinel/manage-data-overview)
- [KQL and the Microsoft Sentinel data lake](https://learn.microsoft.com/azure/sentinel/datalake/kql-overview)
- [KQL jobs in the Microsoft Sentinel data lake](https://learn.microsoft.com/azure/sentinel/datalake/kql-jobs)
- [Jupyter notebooks in the Microsoft Sentinel data lake](https://learn.microsoft.com/azure/sentinel/datalake/notebooks-overview)
- [Microsoft Sentinel graph](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-graph-overview)
- [Microsoft Sentinel MCP server billing](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-mcp-billing)
- [Geographical availability for Microsoft Sentinel data lake](https://learn.microsoft.com/azure/sentinel/geographical-availability-data-residency)
