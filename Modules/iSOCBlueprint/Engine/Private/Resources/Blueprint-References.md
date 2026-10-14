# Conventions

A durable record of the API versions, services, modules and KQL queries the Blueprint
depends on. When something in Microsoft's surface area changes, this page is
the first thing to update; the change then ripples through `Blueprint.psd1`, the inline
api-version table in `Export-SentinelInventory.ps1`, `Private/Invoke-SentinelRest.ps1`,
and the gap-rule resources.

> **Where the api-versions actually live** The `ApiVersions` block in `Blueprint.psd1`
> is a reference copy only, it is **not** read at runtime. `Export-SentinelInventory.ps1`
> hardcodes its own copy of the same five versions in the `$apiVersions` hashtable near
> the top of the script. Reading the manifest at script start was failing silently on the
> ADO Linux agent (the collector's child scopes received an empty `$apiVersions`, so every
> REST call fired without an api-version and Azure returned `400 MissingApiVersionParameter`).
> The two copies must be kept in sync by hand; updating only `Blueprint.psd1` has no effect
> on a run.

> **Banner** Microsoft Sentinel in the Azure portal **retires 2027-03-31** in favour of
> the unified Defender XDR experience. Track the migration timeline at
> <https://learn.microsoft.com/azure/sentinel/move-to-defender>.

## API versions in use

### Centrally-pinned versions

These five are the `$apiVersions` hashtable keys (`Sentinel`, `SentinelPreview`,
`OperationalInsights`, `Tables`, `DataCollection`), mirrored in the `ApiVersions` block of
`Blueprint.psd1`. Most `Invoke-SentinelRest` calls reference them by key rather than a
literal string.

| Surface | Version | `$apiVersions` key | Why |
|---|---|---|---|
| `Microsoft.SecurityInsights/*` | `2024-09-01` | `Sentinel` | GA. Covers onboarding state, data connectors and connector definitions, alert-rule templates, automation rules, watchlists, bookmarks, metadata, content packages, workbook content templates, settings and threat-intelligence metrics, and is the first version tried for `pricings`, `sourceControls` and `taxiiClients`. |
| `Microsoft.SecurityInsights/*` (preview) | `2024-10-01-preview` | `SentinelPreview` | Alert rules: every GA version leaves out `subTechniques`, which the MITRE page reads (falls back to `2024-09-01`, without sub-techniques, when the preview call is refused). Content Hub product packages, SOC-optimisation recommendations, `hunts`, and the `pricings` resource when the GA version refuses it. |
| `Microsoft.OperationalInsights/workspaces` | `2025-02-01` | `OperationalInsights` | Required for `replication`, `publicNetworkAccessForIngestion/Query`, full feature flags. Also used for `savedSearches`, `linkedServices` and `dataExports`. |
| `Microsoft.OperationalInsights/workspaces/tables` | `2025-02-01` (falls back to `2023-09-01`) | `Tables` | `plan` (Analytics/Basic/Auxiliary/DataLake), `retentionInDays`, `totalRetentionInDays`, `archiveRetentionInDays`, and on the newer version `schema.tableSubType` (Classic or DCR-based), `lastPlanModifiedDate` and the `*AsDefault` retention flags. A region that does not serve the newer version gets the older one, with a warning in the run log. |
| `Microsoft.Insights/dataCollectionRules` (full JSON) | `2023-03-11` | `DataCollection` | Cmdlet output flattens transforms; REST returns `streamDeclarations` and `dataFlows.transformKql`. Also used for data collection endpoints. |

### Ad-hoc one-off versions

Beyond the five keyed versions above, the collector hardcodes several literal api-versions
inline where a resource provider is published on its own cadence. These are **not** in the
`$apiVersions` table, so grep `Export-SentinelInventory.ps1` for the literal string when one
needs bumping.

| Surface | Version | Capture (`Try-Capture` label) |
|---|---|---|
| `.../workspaces/<ws>/summaryLogs` (summary rules) | `2023-01-01-preview` | `summary-rules` |
| `Microsoft.SecurityInsights/bookmarks` (list) | `Sentinel` pin | `bookmarks`: the list is refused over about 8 MB with no paging; the collector then keeps the item count the error reports in `bookmarks-count.json` |
| `Microsoft.Insights/workbooks?category=sentinel` | `2023-06-01` | `workbooks-saved` |
| `Microsoft.Logic/workflows` (playbooks list) | `2016-06-01` | `playbooks` |
| `Microsoft.Logic/workflows/{name}/runs` (7-day run history, `$filter=startTime ge ...`) | `2016-06-01` | `playbook-runs` |
| `Microsoft.Insights/diagnosticSettings` | `2021-05-01-preview` | `diagnostic-settings` |
| `Microsoft.OperationalInsights/clusters` (the linked dedicated cluster) | `2022-10-01` | `dedicated-cluster` |
| `Microsoft.ResourceGraph/resources` (POST, Sentinel data lake resources across the visible subscriptions) | `2022-10-01` | `sentinel-data-lake` |
| `Microsoft.OperationsManagement/solutions` | `2015-11-01-preview` | `solutions-installed` |
| `Microsoft.Authorization/locks` (workspace scope) | `2016-09-01` | `workspace-locks` |
| `.../availableServiceTiers` | `2020-08-01` | `available-service-tiers` |
| `.../linkedStorageAccounts` | `2020-08-01` | `linked-storage-accounts`: customer-owned storage per data source type |
| `Microsoft.SecurityInsights/threatIntelligence/main/taxiiClients` | `Sentinel` pin, then `2024-03-01`, then `2023-11-01` | `taxii-clients`: not in the published REST reference, so a service that does not answer leaves an empty list rather than a failed capture |

`sourceControls` (the `repositories` capture) is a special case: it is published on a
different cadence than the rest of Sentinel and the GA Sentinel pin returns
`UnsupportedApiVersion` against ARM. The collector tries a fallback chain in order,
`2024-09-01` (the `Sentinel` pin) → `2023-11-01` → `2023-06-01-preview` → `2022-12-01-preview`,
and treats any 4xx as "feature not present" rather than a failure.

### Other services

Beyond Azure Resource Manager, the Blueprint calls these services. None of them takes an
api-version from the tables above.

| Service | Endpoint | Used by | Notes |
|---|---|---|---|
| Log Analytics query API | `Invoke-AzOperationalInsightsQuery` (`api.loganalytics.io/v1`) | The 38 KQL captures below | Workspace-scoped and read-only; needs Log Analytics Reader. |
| Microsoft Graph (beta) | `https://graph.microsoft.com/beta/security/rules/detectionRules`, paged on `@odata.nextLink` | `defender-custom-detections` | Needs `CustomDetection.Read.All`. A Graph PowerShell SDK session is used when one exists, otherwise the Azure PowerShell context; a 401 or 403 is a failed capture, not an empty list. |
| Azure Retail Prices API | `https://prices.azure.com/api/retail/prices` with an OData `$filter` | `retail-prices` (the cost estimate) | Anonymous, no authentication header. |
| Microsoft Learn | The Microsoft Sentinel and Defender XDR What's new pages, read as Markdown (`Accept: text/markdown`) | `whats-new`, `Get-iSOCBlueprintWhatsNew` | Public pages. A page that cannot be read is recorded and the other is still read. |
| Sentinel-As-Code Toolkit (GitHub) | `https://raw.githubusercontent.com/noodlemctwoodle/Sentinel-As-Code-Toolkit/main/data/connectors.json` | `Update-iSOCBlueprintConnectorCatalogue` (maintainers) | Refreshes the bundled connector catalogue; never called during a run. |
| SharePoint Online | PnP.PowerShell 3.4.1 cmdlets (sites, lists, files, pages and web parts, navigation, the site collection app catalogue, Entra app site permissions), plus `/_api/web/sitecollectionappcatalog/AvailableApps` through `Invoke-PnPSPRestMethod` | `Publish-iSOCBlueprintSite`, `Initialize-iSOCBlueprintSite` | Publishing signs in interactively or with a SharePoint access token (audience `https://<tenant>.sharepoint.com`); initialising also needs the tenant admin site. |

## Modules

Pinned in the `Modules` block of `Engine/Blueprint.psd1`: `Az.Accounts`, `Az.SecurityInsights`,
`Az.OperationalInsights`, `Az.Monitor`, `Az.Resources`, `Az.LogicApp` and `powershell-yaml`.
The SharePoint commands also need PnP.PowerShell 3.4.1 on PowerShell 7.4, and the Defender
custom detection capture uses the Graph PowerShell SDK (`Microsoft.Graph.Authentication`)
when it is loaded. `Test-iSOCBlueprintPrerequisite` reports what a machine has.

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
- `Invoke-AzRestMethod -Uri https://graph.microsoft.com/beta/security/rules/detectionRules` for the
  `defender-custom-detections` capture (Defender XDR custom detection rules, paged on
  `@odata.nextLink`), through `Private/Get-DefenderCustomDetections.ps1`. A Graph PowerShell SDK
  session (`Connect-MgGraph -Scopes 'CustomDetection.Read.All'`, `Invoke-MgGraphRequest`) is used
  when one exists, otherwise the Azure PowerShell context, which needs the application permission
  `CustomDetection.Read.All`; a 401 or 403 is recorded as a failed capture, not as an empty list.
  The companion `custom-detection-table-references` file is derived locally with
  `Resolve-KqlTableNames`.
- `Get-AzureRetailPrice` (repo-local helper in `Private/Get-AzureRetailPrice.ps1`)

The `Az.SecurityInsights` / `Az.OperationalInsights` / `Az.Monitor` pins therefore exist for
a possible future cmdlet migration rather than current runtime use. Note `Az.LogicApp` is
pinned but not exercised for the playbook LIST: see [REST-only gaps](#rest-only-gaps) for why
that call deliberately uses REST instead of `Get-AzLogicApp`.

## Authentication pattern

GitHub Actions OIDC → Entra federated credential → service principal
`AZURE_BLUEPRINT_CLIENT_ID` (separate from the deploy SP). Read-only roles:

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

The collector runs **38 targeted KQL queries** through `Invoke-AzOperationalInsightsQuery`,
each inside its own `Try-Capture` block that writes one `_raw/<name>.json` file. They are
**not** all cheap billing-metadata reads: a good half of them query raw operational and
security tables directly (`CommonSecurityLog`, `Syslog`, `SecurityEvent`, `SecurityAlert`,
`AzureActivity`, `AzureDiagnostics`, XDR `Device*`/`Email*`/`Identity*` tables, and `Event`
via `find`). To enumerate them at any time, grep the script for `Try-Capture` blocks that
set `$kql`.

Grouped by purpose:

**Usage, cost and ingestion health**

- `tables-with-data` - which schema'd tables actually receive data, with 90d/30d/7d/24h
  billable-GB breakdowns and the 7-day ingested total (`Usage`).
- `ingestion-latency` - broken-pipeline detector over ingestion/schema operations (`Operation`).
- `workspace-usage` - workspace-level ingestion volume trend.
- `workspace-usage-daily` - billable and free GB per day for 30 days, the ingestion trend
  line on the dashboard.
- `azure-diagnostics-categories` - `AzureDiagnostics` row counts by resource provider and
  category over 7 days, the input to the duplicate-firewall-logging rule.
- `la-query-logs` - Log Analytics query-audit activity over 7 days; zero records means query
  auditing is off (SAC-PLT-12).
- `table-query-usage` - audited queries, distinct users and the last query per lake-retained
  table over 30 days (`LAQueryLogs` matched against every such table name from the
  `workspace-tables` capture written earlier in the run, 60 names per query;
  a failed batch fails the capture rather than writing an empty file); the usage evidence on the data lake
  page. Empty when no table keeps data in the lake beyond its analytics retention.

**Sentinel health and posture**

- `sentinel-health` and `sentinel-health-summary` - `SentinelHealth`-based connector/rule health;
  `sentinel-health` carries the failure count and last failure per resource, the connector
  health issues on page 11.
- `rule-health` - analytics rules whose scheduled runs failed in the last 7 days, with the
  failure count, last failure and recorded reason (`SentinelHealth`, resource type
  "Analytics Rule"); the input to SAC-DET-14 and the rule-run-failures table.
- `ueba-data-presence` - infers whether UEBA is producing data (row presence in
  `BehaviorAnalytics` / `IdentityInfo` / `UserPeerAnalytics`, over 12 days with 7- and 14-day
  counts beside it), the operational counterpart to the `settings/Ueba` configuration signal,
  and the IdentityInfo evidence for entity analytics (SAC-COV-08).

(SOC-optimisation recommendations, `soc-optimization`, are captured separately over REST from
`.../recommendations`, not via KQL.)

**Incidents**

- `incidents-summary`, `incidents-mttr`, `incidents-daily-metrics`,
  `incidents-detail-by-provider`, `incidents-by-rule` (every rule title) - incident counts, mean-time-to-respond,
  daily trend, per-provider detail and per-rule breakdown. `incidents-summary` returns one
  row with `Count`, `Closed` and six bags (`ByStatus`, `BySeverity`, `ByClassification`,
  `ByProvider`, `OpenBySeverity`, `ClosedBy`) whose values are real counts; closed incidents
  with an empty classification are reported as `Unclassified`. `ClosedBy` sorts each closed
  incident by the first record that shows it Closed: `AutomationRule` (`ModifiedBy contains
  "Automation"`, the test the automation rules guide uses), `DefenderXdr`, `Analyst` (a user
  principal name) or `Other`; only the category is exported. The same row carries the last 7 days (`Count7d`,
  `Closed7d`, `TruePositive7d`, `FalsePositive7d`) and the incidents raised through Defender
  XDR (`Unified`, `Unified7d`: provider Microsoft XDR or Microsoft 365 Defender);
  `incidents-mttr` carries the 7-day MTTA and MTTR beside the 30-day ones.
- `rule-effectiveness` - per detection over 30 days: incidents, closures and the
  true/false/benign-positive split, with a false-positive rate over closed incidents. Each
  incident is counted once (`arg_max` by `IncidentNumber`) and joined to its alerts. Sentinel
  rules are keyed on the rule id from `ExtendedProperties` (`Analytic Rule Ids` on current
  alerts, `Analytic Rule Id` on older ones) and carry `Source` "Analytics rule"; alerts from
  other products (Defender XDR, Entra ID Protection, Purview) have no rule id, are keyed on
  the alert name and carry the product as `Source`. Sentinel rules sort first, then the
  300-row cap applies, so a busy XDR tenant never pushes its own rules off the list.
- `incident-title-stats` - incident titles seen five or more times in 30 days, with totals,
  closures, average minutes to close, closures within an hour and the verdict split
  (aggregates only, no per-incident rows); the input to the automation-opportunities table.

**Analytics and threat intelligence**

- `analytics-rule-volumes` - per-rule alert volume from `SecurityAlert`, each alert counted
  once (its first record in the window, by `SystemAlertId`, however often a status change
  wrote it again), grouped by `AlertName`, `ProductName`, `AlertSeverity` (every row, so the
  pack and the dashboard list every alerting rule rather than a top fifty), with the provider
  and the last 7 days' count beside the 30-day total. Summed, it gives the alerts in the
  dashboard's alert lifecycle and estate flow, split into Sentinel's and Defender XDR's.
- `rules-fired` - alerts in 30 days per Scheduled or NRT rule, keyed on the rule id rather
  than the alert name, so renamed rules and rules sharing a name are told apart.
- `threat-intel-counts` - threat-intelligence records and distinct indicators per source
  system from KQL. (The related `threat-intel-metrics` capture is REST, from
  `.../threatIntelligence/main/metrics`.)
- `threat-intel-tables` - records over 30 and 7 days, first and last record, in each of
  `ThreatIntelIndicators`, `ThreatIntelObjects` and the retired `ThreatIntelligenceIndicator`:
  the table migration status on page 27.
- `threat-intel-health` - each indicator in `ThreatIntelIndicators` at its latest state:
  active, deleted, revoked and still within its validity.
- `threat-intel-objects` - `ThreatIntelObjects` rows by STIX type over 30 days.
- `threat-intel-by-type` - indicators by observable type (IP, domain, URL, file hash, email)
  over 30 days from `ThreatIntelIndicators` (`ObservableKey`), falling back to the retired
  `ThreatIntelligenceIndicator` table when the current one is absent.

**Table hygiene, agent migration and connector misrouting**

- `cef-devices` - top CEF device vendor/product pairs (`CommonSecurityLog`).
- `cef-in-syslog` - CEF records (a message starting `CEF:` or `0|`) that landed in `Syslog`,
  by forwarder and the vendor and product in the CEF header; a forwarder misconfiguration
  that should be split into a dedicated `CommonSecurityLog` stream (SAC-LOG-23).
- `security-event-duplicates` - duplicate `SecurityEvent` records per host in the last hour,
  with the number of distinct events duplicated; typically MMA + AMA dual-collection
  (SAC-LOG-22).
- `agent-heartbeat-mix` - machines by OS, agent category (Azure Monitor Agent, Direct Agent
  for the legacy MMA, SCOM) and agent version over 7 days.
- `syslog-contributors` - `Syslog` records and billed size by host and facility over 7 days.
- `securityevent-top-hosts` - `SecurityEvent` records and billed size by host over 7 days.
- `ama-agents` and `ama-mma-migration` - Azure Monitor Agent inventory and MMA→AMA migration
  status.
- `top-event-ids` - every billable Windows event ID across `Event`/`SecurityEvent` (via
  `find`), largest first, with the record count; drives table-noise tuning.
- `azure-activity-coverage` - per-subscription `AzureActivity` volume, surfaces subscriptions
  not shipping Activity Logs.
- `azure-diagnostics-providers` - `AzureDiagnostics` volume by resource provider.
- `azure-firewall-categories` - Azure Firewall rows by category, legacy `AzureFirewall*` and
  resource-specific `AZFW*`, asked for by name so the legacy and resource-specific forms sit
  side by side.
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
       IngestedLast7d  = sumif(Quantity, TimeGenerated > ago(7d)) / 1024.0,
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

## Microsoft Learn pages

The Microsoft Learn pages the findings and report pages link to, the best-practice pages
among them, are listed by topic on the report's Microsoft References page
(`96-references-microsoft.md`).

## Azure Retail Prices API

Anonymous, no auth required. Used by `Private/Get-AzureRetailPrice.ps1`.

- Endpoint: <https://prices.azure.com/api/retail/prices>
- Filter syntax: `$filter=serviceName eq '<name>' and armRegionName eq '<region>' and priceType eq 'Consumption'`
- Pagination: follow `NextPageLink` in the response.
- Documentation: <https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices>

## Data connector catalogue

Which data connector writes which table, and the Content Hub solution that
ships it, comes from `Private/Resources/connector-catalogue.json`: about 630
connectors and their tables, copied from the Sentinel as Code Toolkit's
`data/connectors.json`. The Toolkit builds that file from Microsoft's
Solutions Analyzer CSVs in the Azure-Sentinel repository
(<https://github.com/Azure/Azure-Sentinel/tree/master/Tools/Solutions%20Analyzer>),
taking a connector's tables from its own mapping where Microsoft publishes one
and otherwise from every table its solution's content uses. Refresh the copy
with `Update-iSOCBlueprintConnectorCatalogue` (it reads the Toolkit's file on
GitHub by default, or a local path with `-Source`).

## Sentinel free benefit

Confirms which tables are eligible for the Sentinel ingestion benefit. List maintained
in `Private/Resources/sentinel-benefit-tables.json` and reviewed against
<https://learn.microsoft.com/azure/sentinel/billing-reduce-costs> on every release.
