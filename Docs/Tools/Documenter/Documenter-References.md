# Sentinel Documenter: References & Conventions

A durable record of the API versions, modules, KQL queries and Microsoft Learn pages the
documenter depends on. When something in Microsoft's surface area changes, this page is
the first thing to update; the change then ripples through `Documenter.psd1`, the inline
api-version table in `Export-SentinelInventory.ps1`, `Private/Invoke-SentinelRest.ps1`,
and the gap-rule resources.

> **Where the api-versions actually live** The `ApiVersions` block in `Documenter.psd1`
> is a reference copy only, it is **not** read at runtime. `Export-SentinelInventory.ps1`
> hardcodes its own copy of the same five versions in the `$apiVersions` hashtable near
> the top of the script. Reading the manifest at script start was failing silently on the
> ADO Linux agent (the collector's child scopes received an empty `$apiVersions`, so every
> REST call fired without an api-version and Azure returned `400 MissingApiVersionParameter`).
> The two copies must be kept in sync by hand; updating only `Documenter.psd1` has no effect
> on a run.

> **Banner** Microsoft Sentinel in the Azure portal **retires 2027-03-31** in favour of
> the unified Defender XDR experience. Track the migration timeline at
> <https://learn.microsoft.com/azure/sentinel/move-to-defender>.

## API versions in use

### Centrally-pinned versions

These five are the `$apiVersions` hashtable keys (`Sentinel`, `SentinelPreview`,
`OperationalInsights`, `Tables`, `DataCollection`), mirrored in the `ApiVersions` block of
`Documenter.psd1`. Most `Invoke-SentinelRest` calls reference them by key rather than a
literal string.

| Surface | Version | `$apiVersions` key | Why |
|---|---|---|---|
| `Microsoft.SecurityInsights/*` | `2024-09-01` | `Sentinel` | GA. Covers connectors, alert rules, alert-rule templates, automation rules, watchlists, bookmarks, metadata, content packages, settings, threat-intelligence metrics. |
| `Microsoft.SecurityInsights/*` (preview) | `2024-10-01-preview` | `SentinelPreview` | Content Hub product packages, SOC-optimisation recommendations, `pricings` resource. |
| `Microsoft.OperationalInsights/workspaces` | `2025-02-01` | `OperationalInsights` | Required for `replication`, `publicNetworkAccessForIngestion/Query`, full feature flags. Also used for `savedSearches`, `linkedServices` and `dataExports`. |
| `Microsoft.OperationalInsights/workspaces/tables` | `2023-09-01` | `Tables` | `plan` (Analytics/Basic/Auxiliary/DataLake), `retentionInDays`, `totalRetentionInDays`, `archiveRetentionInDays`. |
| `Microsoft.Insights/dataCollectionRules` (full JSON) | `2023-03-11` | `DataCollection` | Cmdlet output flattens transforms; REST returns `streamDeclarations` and `dataFlows.transformKql`. Also used for data collection endpoints. |

### Ad-hoc one-off versions

Beyond the five keyed versions above, the collector hardcodes several literal api-versions
inline where a resource provider is published on its own cadence. These are **not** in the
`$apiVersions` table, so grep `Export-SentinelInventory.ps1` for the literal string when one
needs bumping.

| Surface | Version | Capture (`Try-Capture` label) |
|---|---|---|
| `.../workspaces/<ws>/summaryLogs` (summary rules) | `2023-01-01-preview` | `summary-rules` |
| `Microsoft.Insights/workbooks?category=sentinel` | `2023-06-01` | `workbooks-saved` |
| `Microsoft.Logic/workflows` (playbooks list) | `2016-06-01` | `playbooks` |
| `Microsoft.Insights/diagnosticSettings` | `2021-05-01-preview` | `diagnostic-settings` |
| Dedicated cluster resource + `Microsoft.ResourceGraph/resources` | `2022-10-01` | `dedicated-cluster` |
| `Microsoft.OperationsManagement/solutions` | `2015-11-01-preview` | `solutions-installed` |
| `Microsoft.Authorization/locks` (workspace scope) | `2016-09-01` | `workspace-locks` |
| `.../availableServiceTiers` | `2020-08-01` | `available-service-tiers` |

`sourceControls` (the `repositories` capture) is a special case: it is published on a
different cadence than the rest of Sentinel and the GA Sentinel pin returns
`UnsupportedApiVersion` against ARM. The collector tries a fallback chain in order,
`2024-09-01` (the `Sentinel` pin) → `2023-11-01` → `2023-06-01-preview` → `2022-12-01-preview`,
and treats any 4xx as "feature not present" rather than a failure.

## Modules

Pinned in the `Modules` block of `Documenter.psd1`: `Az.Accounts`, `Az.SecurityInsights`,
`Az.OperationalInsights`, `Az.Monitor`, `Az.Resources`, `Az.LogicApp` and `powershell-yaml`.

The collector is **REST-first end to end**. Every Sentinel and Log Analytics artefact
(alert rules, alert-rule templates, automation rules, watchlists, bookmarks, metadata,
content packages, settings, threat-intelligence metrics, workspace, tables, saved searches,
DCRs, playbooks, and so on) is fetched through `Invoke-SentinelRest`
(`Private/Invoke-SentinelRest.ps1`, a thin wrapper over `Invoke-AzRestMethod`). No
`Az.SecurityInsights`, `Az.OperationalInsights` or `Az.Monitor` inventory cmdlet is called
anywhere in `Export-SentinelInventory.ps1`. The only Az cmdlets it actually invokes are:

- `Get-AzContext` / `Set-AzContext` / `Get-AzSubscription` (context and subscription resolution)
- `Get-AzResourceProvider`, `Get-AzResourceLock`, `Get-AzPolicyAssignment`, `Get-AzRoleAssignment` (from `Az.Resources`)
- `Invoke-AzOperationalInsightsQuery` (from `Az.OperationalInsights`, used **only** to run the KQL queries below, not for inventory reads)
- `Get-AzureRetailPrice` (repo-local helper in `Private/Get-AzureRetailPrice.ps1`)

The `Az.SecurityInsights` / `Az.OperationalInsights` / `Az.Monitor` pins therefore exist for
a possible future cmdlet migration rather than current runtime use. Note `Az.LogicApp` is
pinned but not exercised for the playbook LIST: see [REST-only gaps](#rest-only-gaps) for why
that call deliberately uses REST instead of `Get-AzLogicApp`.

## Authentication pattern

GitHub Actions OIDC → Entra federated credential → service principal
`AZURE_DOCUMENTER_CLIENT_ID` (separate from the deploy SP). Read-only roles:

- **Microsoft Sentinel Reader** at workspace scope
- **Log Analytics Reader** at workspace scope
- **Reader** at the resource group(s) hosting playbooks/DCRs
- **Monitoring Reader** at subscription scope
- **Reader** at subscription scope (clusters, policy assignments, locks, RP registration)

Reference: <https://learn.microsoft.com/azure/sentinel/roles>,
<https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect>.

## REST-only gaps

As noted above, essentially the whole Sentinel/OperationalInsights surface is read via
`Invoke-SentinelRest` in this codebase, not just the items below. The following are the
cases where REST is not merely the house convention but the **only** option, or where the
call shape is non-obvious enough to be worth pinning down here:

- Codeless Connector Framework (CCF): `dataConnectors` (kind `RestApiPoller`/`GCP` etc.)
  and `dataConnectorDefinitions`.
- Content Hub: `contentPackages`, `contentTemplates`, `contentProductPackages`.
- Repositories: `sourceControls` (via the api-version fallback chain documented above).
- Summary rules: `.../workspaces/<ws>/summaryLogs` on the **OperationalInsights** provider
  at api-version `2023-01-01-preview`. This is deliberately **not** the Content Hub
  `contentTemplates?$filter=contentKind eq 'SummaryRule'` endpoint, which returns installable
  templates rather than deployed rule instances; the earlier implementation also gated that
  call on `-IncludePreview`, so production runs without the switch returned nothing regardless
  of how many summary rules the workspace actually had.
- Sentinel settings: `Microsoft.SecurityInsights/settings/{Ueba,EntityAnalytics,EyesOn,Anomalies}`,
  bundled into a single `settings.json` with one property per setting. A `null` property means
  no explicit settings resource exists (the toggle can live in the portal without one), not
  that the feature is off, so the collector also infers UEBA state from data presence (see the
  `ueba-data-presence` KQL capture below).
- Playbooks: `Microsoft.Logic/workflows` at api-version `2016-06-01`. This uses REST rather
  than `Get-AzLogicApp` on purpose: the cmdlet's list-style call returns `PSWorkflow` objects
  with the `identity` property unpopulated even when a managed identity is attached, so REST is
  the only path that reliably surfaces `identity.principalId` for the per-playbook MI RBAC
  resolution (`rbac-playbook-mi.json`).
- DCR full JSON (transforms): `Microsoft.Insights/dataCollectionRules/{name}`.
- Pricings resource: `Microsoft.SecurityInsights/pricings`.
- Sentinel Data Lake: workspace lake feature + organisational lake resource.

## Recurring KQL queries

The collector runs **23 targeted KQL queries** through `Invoke-AzOperationalInsightsQuery`,
each inside its own `Try-Capture` block that writes one `_raw/<name>.json` file. They are
**not** all cheap billing-metadata reads: a good half of them query raw operational and
security tables directly (`CommonSecurityLog`, `Syslog`, `SecurityEvent`, `SecurityAlert`,
`AzureActivity`, `AzureDiagnostics`, XDR `Device*`/`Email*`/`Identity*` tables, and `Event`
via `find`). To enumerate them at any time, grep the script for `Try-Capture` blocks that
set `$kql`.

Grouped by purpose:

**Usage, cost and ingestion health**

- `tables-with-data` - which schema'd tables actually receive data, with 90d/30d/7d/24h
  billable-GB breakdowns (`Usage`).
- `ingestion-latency` - broken-pipeline detector over ingestion/schema operations (`Operation`).
- `workspace-usage` - workspace-level ingestion volume trend.
- `la-query-logs` - Log Analytics query-audit activity.

**Sentinel health and posture**

- `sentinel-health` and `sentinel-health-summary` - `SentinelHealth`-based connector/rule health.
- `ueba-data-presence` - infers whether UEBA is producing data (row presence in
  `BehaviorAnalytics` / `IdentityInfo` / `UserPeerAnalytics`), the operational counterpart to
  the `settings/Ueba` configuration signal.

(SOC-optimisation recommendations, `soc-optimization`, are captured separately over REST from
`.../recommendations`, not via KQL.)

**Incidents**

- `incidents-summary`, `incidents-mttr`, `incidents-daily-metrics`,
  `incidents-detail-by-provider`, `incidents-by-rule` - incident counts, mean-time-to-respond,
  daily trend, per-provider detail and per-rule breakdown.

**Analytics and threat intelligence**

- `analytics-rule-volumes` - per-rule alert volume from `SecurityAlert` (grouped by
  `AlertName`, `ProductName`, `AlertSeverity`).
- `threat-intel-counts` - threat-intelligence indicator counts from KQL. (The related
  `threat-intel-metrics` capture is REST, from `.../threatIntelligence/main/metrics`.)

**Table hygiene, agent migration and connector misrouting**

- `cef-devices` - top CEF device vendor/product pairs (`CommonSecurityLog`).
- `cef-in-syslog` - CEF records that landed in `Syslog`, a forwarder misconfiguration that
  should be split into a dedicated `CommonSecurityLog` stream.
- `security-event-duplicates` - duplicate `SecurityEvent` records, typically MMA + AMA
  dual-collection.
- `ama-agents` and `ama-mma-migration` - Azure Monitor Agent inventory and MMA→AMA migration
  status.
- `top-event-ids` - top billable Windows event IDs across `Event`/`SecurityEvent` (via `find`),
  drives table-noise tuning.
- `azure-activity-coverage` - per-subscription `AzureActivity` volume, surfaces subscriptions
  not shipping Activity Logs.
- `azure-diagnostics-providers` - `AzureDiagnostics` volume by resource provider.
- `xdr-table-presence` - record counts across the known Defender XDR table list, a quick
  "is XDR connected and producing data?" check.

Two representative queries, the cheap `Usage`/`Operation` pair that most of the cost section
is built on:

1. **`tables-with-data.json`** - which schema'd tables actually receive data

   ```kql
   Usage
   | where TimeGenerated > ago(90d)
   | summarize
       BillableLast90d = sumif(Quantity, IsBillable == true) / 1024.0,
       IngestedLast90d = sum(Quantity) / 1024.0,
       BillableLast30d = sumif(Quantity, IsBillable == true and TimeGenerated > ago(30d)) / 1024.0,
       BillableLast7d  = sumif(Quantity, IsBillable == true and TimeGenerated > ago(7d))  / 1024.0,
       BillableLast24h = sumif(Quantity, IsBillable == true and TimeGenerated > ago(1d))  / 1024.0,
       FirstSeen       = min(TimeGenerated),
       LastIngested    = max(TimeGenerated),
       DayCount        = dcount(bin(TimeGenerated, 1d))
       by DataType, Solution
   ```

2. **`ingestion-latency.json`** - broken-pipeline detector

   ```kql
   Operation
   | where TimeGenerated > ago(7d)
   | where OperationCategory in ("Ingestion", "Schema")
   | summarize Failures = countif(OperationStatus != "Succeeded"), Last = max(TimeGenerated)
       by OperationKey = tostring(Detail), Resource = tostring(OperationCategory)
   | where Failures > 0
   ```

## Best-practice Microsoft Learn pages

Linked from `90-gap-analysis.md` and individual section pages.

- Sentinel best practices: <https://learn.microsoft.com/azure/sentinel/best-practices>
- Deployment guide: <https://learn.microsoft.com/azure/sentinel/deploy-overview>
- Skill-up training: <https://learn.microsoft.com/azure/sentinel/skill-up-resources>
- Workspace design: <https://learn.microsoft.com/azure/azure-monitor/logs/workspace-design>
- Sample workspace designs: <https://learn.microsoft.com/azure/sentinel/sample-workspace-designs>
- MITRE coverage: <https://learn.microsoft.com/azure/sentinel/mitre-coverage>
- Connector reference: <https://learn.microsoft.com/azure/sentinel/data-connectors-reference>
- Connector prioritisation: <https://learn.microsoft.com/azure/sentinel/prioritize-data-connectors>
- Tables ↔ connectors map: <https://learn.microsoft.com/azure/sentinel/sentinel-tables-connectors-reference>
- Cost optimisation: <https://learn.microsoft.com/azure/azure-monitor/fundamentals/best-practices-cost>
- Cost logs: <https://learn.microsoft.com/azure/azure-monitor/logs/cost-logs>
- Daily cap: <https://learn.microsoft.com/azure/azure-monitor/logs/daily-cap>
- Table plans: <https://learn.microsoft.com/azure/azure-monitor/logs/logs-table-plans>
- Basic logs configuration: <https://learn.microsoft.com/azure/azure-monitor/logs/basic-logs-configure>
- Retention & archive: <https://learn.microsoft.com/azure/azure-monitor/logs/data-retention-archive>
- Sentinel Data Lake overview: <https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-overview>
- Sentinel billing: <https://learn.microsoft.com/azure/sentinel/billing>
- Sentinel reduce costs: <https://learn.microsoft.com/azure/sentinel/billing-reduce-costs>
- Sentinel monitor costs: <https://learn.microsoft.com/azure/sentinel/billing-monitor-costs>
- Roles & permissions: <https://learn.microsoft.com/azure/sentinel/roles>
- Content Hub: <https://learn.microsoft.com/azure/sentinel/sentinel-solutions>
- CCF authoring: <https://learn.microsoft.com/azure/sentinel/create-codeless-connector>
- CI/CD: <https://learn.microsoft.com/azure/sentinel/ci-cd>
- Custom content CI/CD: <https://learn.microsoft.com/azure/sentinel/ci-cd-custom-content>
- Connector health monitoring: <https://learn.microsoft.com/azure/sentinel/monitor-data-connectors-health>
- Workspace replication: <https://learn.microsoft.com/azure/azure-monitor/logs/workspace-replication>
- Dedicated clusters: <https://learn.microsoft.com/azure/azure-monitor/logs/logs-dedicated-clusters>
- Customer-managed keys: <https://learn.microsoft.com/azure/azure-monitor/logs/customer-managed-keys>
- Private Link Scope (AMPLS): <https://learn.microsoft.com/azure/azure-monitor/logs/private-link-security>
- Manage data overview: <https://learn.microsoft.com/azure/sentinel/manage-data-overview>
- Manage table tiers & retention: <https://learn.microsoft.com/azure/sentinel/manage-table-tiers-retention>
- Defender migration: <https://learn.microsoft.com/azure/sentinel/move-to-defender>

## Azure Retail Prices API

Anonymous, no auth required. Used by `Private/Get-AzureRetailPrice.ps1`.

- Endpoint: <https://prices.azure.com/api/retail/prices>
- Filter syntax: `$filter=serviceName eq '<name>' and armRegionName eq '<region>' and priceType eq 'Consumption'`
- Pagination: follow `NextPageLink` in the response.
- Documentation: <https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices>

## Sentinel free benefit

Confirms which tables are eligible for the Sentinel ingestion benefit. List maintained
in `Private/Resources/sentinel-benefit-tables.json` and reviewed against
<https://learn.microsoft.com/azure/sentinel/billing-reduce-costs> on every release.
