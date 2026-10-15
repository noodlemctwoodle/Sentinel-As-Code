# Conventions

A durable record of the API versions, services, modules and KQL queries the Blueprint
depends on. When something in Microsoft's surface area changes, this page is
the first thing to update; the change then ripples through `Blueprint.psd1`, the inline
api-version table in `Export-SentinelInventory.ps1`, `Private/Invoke-SentinelRest.ps1`,
and the gap-rule resources.

<!-- bp:tone warning -->

> **Where the api-versions actually live** The `ApiVersions` block in `Blueprint.psd1`
> is a reference copy only, it is **not** read at runtime. `Export-SentinelInventory.ps1`
> hardcodes its own copy of the same five versions in the `$apiVersions` hashtable near
> the top of the script. Reading the manifest at script start was failing silently on the
> ADO Linux agent (the collector's child scopes received an empty `$apiVersions`, so every
> REST call fired without an api-version and Azure returned `400 MissingApiVersionParameter`).
> The two copies must be kept in sync by hand; updating only `Blueprint.psd1` has no effect
> on a run.

<!-- bp:tone warning -->

> **Azure portal retirement** Microsoft Sentinel in the Azure portal **retires 2027-03-31** in favour of
> the unified Defender XDR experience. Track the migration timeline at
> <https://learn.microsoft.com/azure/sentinel/move-to-defender>.

## API versions in use

### Centrally-pinned versions

These five are the `$apiVersions` hashtable keys (`Sentinel`, `SentinelPreview`,
`OperationalInsights`, `Tables`, `DataCollection`), mirrored in the `ApiVersions` block of
`Blueprint.psd1`. Most `Invoke-SentinelRest` calls reference them by key rather than a
literal string.

| Surface | Version | Key | Why |
|---|---|---|---|
| `Microsoft.SecurityInsights/*` | `2024-09-01` | `Sentinel` | GA. Covers onboarding state, data connectors and connector definitions, alert-rule templates, automation rules, watchlists, bookmarks, metadata, content packages, workbook content templates, settings and threat-intelligence metrics, and is the first version tried for `sourceControls` and `taxiiClients`. |
| `Microsoft.SecurityInsights/*` (preview) | `2024-10-01-preview` | `SentinelPreview` | Alert rules: every GA version leaves out `subTechniques`, which the MITRE page reads (falls back to `2024-09-01`, without sub-techniques, when the preview call is refused). Content Hub product packages, SOC-optimisation recommendations and `hunts`. |
| `Microsoft.OperationalInsights/workspaces` | `2025-02-01` | `OperationalInsights` | Required for `replication`, `publicNetworkAccessForIngestion/Query`, full feature flags. Also used for `savedSearches`, `linkedServices` and `dataExports`. |
| `Microsoft.OperationalInsights/workspaces/tables` | `2025-02-01` (falls back to `2023-09-01`) | `Tables` | `plan` (Analytics/Basic/Auxiliary/DataLake), `retentionInDays`, `totalRetentionInDays`, `archiveRetentionInDays`, and on the newer version `schema.tableSubType` (Classic or DCR-based), `lastPlanModifiedDate` and the `*AsDefault` retention flags. A region that does not serve the newer version gets the older one, with a warning in the run log. |
| `Microsoft.Insights/dataCollectionRules` (full JSON) | `2023-03-11` | `DataCollection` | Cmdlet output flattens transforms, where REST returns `streamDeclarations` and `dataFlows.transformKql`. Also used for data collection endpoints. |

### Ad-hoc one-off versions

Beyond the five keyed versions above, the collector hardcodes several literal api-versions
inline where a resource provider is published on its own cadence. These are **not** in the
`$apiVersions` table, so grep `Export-SentinelInventory.ps1` for the literal string when one
needs bumping.

| Surface | Version | Capture |
|---|---|---|
| `.../workspaces/<ws>/summaryLogs` (summary rules) | `2023-01-01-preview` | `summary-rules` |
| `Microsoft.SecurityInsights/bookmarks` (list) | `Sentinel` pin | `bookmarks`: the list is refused over about 8 MB with no paging (`$top` is refused with 400). The collector then keeps the item count the error reports in `bookmarks-count.json` and lists the bookmarks from the `HuntingBookmark` table instead (below); bookmarks not changed within the table's retention are not in it |
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
| `Microsoft.SecurityInsights/sourceControls` | `Sentinel` pin, then `2023-11-01`, `2023-06-01-preview`, `2022-12-01-preview` | `repositories`: published on its own cadence, and the GA pin can return `UnsupportedApiVersion`. Any 4xx means the feature is not present, not a failure |

### Other services

Beyond Azure Resource Manager, the Blueprint calls these services. None of them takes an
api-version from the tables above.

| Service | Endpoint | Used by | Notes |
|---|---|---|---|
| Log Analytics query API | `Invoke-AzOperationalInsightsQuery` (`api.loganalytics.io/v1`) | The 43 KQL captures below | Workspace-scoped and read-only, with Log Analytics Reader. |
| Microsoft Graph (beta) | `https://graph.microsoft.com/beta/security/rules/detectionRules`, paged on `@odata.nextLink` | `defender-custom-detections` | Needs `CustomDetection.Read.All`. A Graph PowerShell SDK session is used when one exists, otherwise the Azure PowerShell context. A 401 or 403 is a failed capture, not an empty list. |
| Azure Retail Prices API | `https://prices.azure.com/api/retail/prices` with an OData `$filter` | `retail-prices` (the cost estimate) | Anonymous, no authentication header. |
| Microsoft Learn | The Microsoft Sentinel and Defender XDR What's new pages, read as Markdown (`Accept: text/markdown`) | `whats-new`, `Get-iSOCBlueprintWhatsNew` | Public pages. A page that cannot be read is recorded and the other is still read. |
| Sentinel-As-Code Toolkit (GitHub) | `https://raw.githubusercontent.com/noodlemctwoodle/Sentinel-As-Code-Toolkit/main/data/connectors.json` | `Update-iSOCBlueprintConnectorCatalogue` (maintainers) | Refreshes the bundled connector catalogue, never called during a run. |
| SharePoint Online | PnP.PowerShell 3.4.1 cmdlets (sites, lists, files, pages and web parts, navigation, the site collection app catalogue, Entra app site permissions), plus `/_api/web/sitecollectionappcatalog/AvailableApps` through `Invoke-PnPSPRestMethod` | `Publish-iSOCBlueprintSite`, `Initialize-iSOCBlueprintSite` | Publishing signs in interactively or with a SharePoint access token (audience `https://<tenant>.sharepoint.com`), and initialising also needs the tenant admin site. |

## Modules

| Module | Version | Used for |
|---|---|---|
| `Az.Accounts` | `3.0.4` | The Azure context and `Invoke-AzRestMethod`, which every REST read goes through |
| `Az.Resources` | `7.4.0` | Resource providers, locks, policy assignments and role assignments |
| `Az.OperationalInsights` | `3.2.0` | `Invoke-AzOperationalInsightsQuery`, for the KQL captures only |
| `Az.SecurityInsights` | `3.1.2` | Pinned for a possible cmdlet migration, not called: Sentinel is read over REST |
| `Az.Monitor` | `5.2.1` | Pinned, not called: data collection and diagnostic settings are read over REST |
| `Az.LogicApp` | `1.7.0` | Pinned, not called: playbooks are read over REST (see REST-only gaps) |
| `powershell-yaml` | `0.4.12` | Reading YAML content when rendering |
| `PnP.PowerShell` | `3.4.1` | The SharePoint commands, on PowerShell 7.4 |
| `Microsoft.Graph.Authentication` | Any | The Defender custom detection capture, when a Graph session is open |

The first seven are pinned in the `Modules` block of `Engine/Blueprint.psd1`.
`Test-iSOCBlueprintPrerequisite` reports what a machine has.

The collector is **REST-first end to end**: every Sentinel and Log Analytics artefact is
read through `Invoke-SentinelRest` (`Private/Invoke-SentinelRest.ps1`, a thin wrapper over
`Invoke-AzRestMethod`), and no `Az.SecurityInsights`, `Az.OperationalInsights` or
`Az.Monitor` inventory cmdlet is called. These are the cmdlets it does call:

| Cmdlet | Module | For |
|---|---|---|
| `Get-AzContext`, `Set-AzContext`, `Get-AzSubscription` | `Az.Accounts` | The context and the subscription |
| `Invoke-AzRestMethod` | `Az.Accounts` | Every REST read, through `Invoke-SentinelRest`, and Microsoft Graph when no Graph session is open |
| `Get-AzResourceProvider` | `Az.Resources` | Resource provider registration |
| `Get-AzResourceLock` | `Az.Resources` | Locks on the subscription, resource group and workspace |
| `Get-AzPolicyAssignment` | `Az.Resources` | Policy assignments on the subscription |
| `Get-AzRoleAssignment` | `Az.Resources` | Role assignments on the workspace and resource group, and for playbook identities |
| `Invoke-AzOperationalInsightsQuery` | `Az.OperationalInsights` | The 43 KQL captures, never inventory |
| `Invoke-MgGraphRequest` | `Microsoft.Graph.Authentication` | Defender custom detections, when a Graph session is open |
| `Get-AzureRetailPrice` | Repository helper | The Azure Retail Prices API (`Private/Get-AzureRetailPrice.ps1`) |

## Authentication pattern

GitHub Actions OIDC → Entra federated credential → the service principal
`AZURE_BLUEPRINT_CLIENT_ID`, separate from the deploy service principal. It holds read-only
roles:

| Role | Scope | Covers |
|---|---|---|
| Microsoft Sentinel Reader | Workspace | Sentinel resources: rules, automation, watchlists, content and settings |
| Log Analytics Reader | Workspace | The workspace, its tables and the KQL captures |
| Reader | Resource groups holding playbooks and data collection rules | Playbooks and data collection rules |
| Monitoring Reader | Subscription | Monitoring configuration such as data collection and diagnostic settings |
| Reader | Subscription | Clusters, policy assignments, locks and resource provider registration |
| `CustomDetection.Read.All` (Microsoft Graph application permission) | Tenant | Defender custom detections, optional |

## REST-only gaps

Nearly everything is read over REST by convention. These are the surfaces where REST is the
**only** option, or where the call shape is worth pinning down:

| Surface | Endpoint | Why REST |
|---|---|---|
| Codeless Connector Framework | `dataConnectors` (kind `RestApiPoller`, `GCP` and others) and `dataConnectorDefinitions` | No cmdlet returns the CCF definitions |
| Content Hub | `contentPackages`, `contentTemplates`, `contentProductPackages` | Not covered by the cmdlets |
| Repositories | `sourceControls` | Published on its own cadence, read through the api-version fallback chain above |
| Summary rules | `.../workspaces/<ws>/summaryLogs` on the OperationalInsights provider, `2023-01-01-preview` | Deployed rules live here, not in Content Hub `contentTemplates` (which lists installable templates) |
| Sentinel settings | `Microsoft.SecurityInsights/settings/{Ueba,EntityAnalytics,EyesOn,Anomalies}`, bundled into `settings.json` | A `null` setting means no settings resource exists, not that the feature is off, so UEBA is also judged from data (`ueba-data-presence`) |
| Playbooks | `Microsoft.Logic/workflows`, `2016-06-01` | `Get-AzLogicApp` leaves `identity` empty even when a managed identity is attached, and the playbook RBAC needs `identity.principalId` |
| Data collection rules | `Microsoft.Insights/dataCollectionRules/{name}` | The cmdlet flattens the transforms that the full JSON carries |
| Microsoft Sentinel pricing | The `SecurityInsights(<workspace>)` solution's `properties.sku` (`Microsoft.OperationsManagement/solutions`, in `solutions-installed.json`): `Unified` is simplified pricing, anything else classic. The commitment tier is the workspace's own SKU | There is no documented `Microsoft.SecurityInsights/pricings` resource; the collector once probed it and it never answered |
| Sentinel data lake | The workspace's lake feature and the organisational lake resource | Not covered by the cmdlets |

## Recurring KQL queries

The collector runs **43 KQL queries** through `Invoke-AzOperationalInsightsQuery`, each in
its own `Try-Capture` block that writes one `_raw/<name>.json`, and a 44th only when the
bookmarks API refuses its list (below). About half read raw
operational and security tables, not only billing metadata, so they cost query time on a
busy workspace, and more the longer the lookback. To list them, grep the collector for
`Try-Capture` blocks that set `$kql`.

Every query reads **one lookback**: `-LookbackDays` (1 to 730, default 30, the
`lookbackDays` pipeline parameter). `Add-BpWindow` declares `let lookback = <n>d;`,
`let recent = <n>d;` and `let daily = <n>d;` ahead of each query, so no query carries a
number of days of its own.
The **recent window** is the shorter of 7 days and the lookback; it carries the figures for
the latest days (the `...7d` columns). Two sub-windows stay fixed because they are not
lookbacks: a table's last 24 hours of ingestion and the one-hour sample the duplicate-event
check reads. The window is written to `run-context.json` (`LookbackDays`, `RecentDays`,
`DailyDays`),
and the pages, the dashboard's cards, the findings, the maturity criteria and the cost
estimate (a month projected from the window's rate) name it from there. The `30d`, `90d`
and `7d` property names in the captures are their historical names for the lookback and
recent figures. A lookback longer than a table's interactive retention returns only what
the table still holds.

### Usage, cost and ingestion health

| Capture | Reads | Window | What it gives |
|---|---|---|---|
| `tables-with-data` | `Usage` | Lookback | Which tables receive data, with billable GB over the lookback, the recent window and the last 24 hours, and the recent window's ingested total |
| `ingestion-latency` | `Operation` | Lookback | Ingestion and schema operations that failed, the broken-pipeline signal |
| `workspace-usage` | `Usage` | Lookback | Total and billable GB, the peak day and the daily average |
| `workspace-usage-daily` | `Usage` | Lookback | Billable and free GB per day, the dashboard's ingestion trend |
| `azure-diagnostics-categories` | `AzureDiagnostics` | Lookback | Rows by resource provider and category, the input to the duplicate firewall logging rule |
| `la-query-logs` | `LAQueryLogs` | Lookback | Query audit activity, where no records means auditing is off (SAC-PLT-12) |
| `table-query-usage` | `LAQueryLogs` | Lookback | Audited queries, distinct users and the last query per lake-retained table, the data lake page's usage evidence |

### Sentinel health and posture

| Capture | Reads | Window | What it gives |
|---|---|---|---|
| `sentinel-health` | `SentinelHealth` | Lookback | Events, failures and the last failure per connector, rule and automation resource |
| `sentinel-health-summary` | `SentinelHealth` | Lookback | Events by operation and status, the operations summary on page 11 |
| `rule-health` | `SentinelHealth` | Lookback | Analytics rules whose runs failed, with the count, last failure and reason (SAC-DET-14) |
| `ueba-data-presence` | `BehaviorAnalytics`, `IdentityInfo`, `UserPeerAnalytics` | Lookback | Whether UEBA produces data, with counts for the lookback and the recent window, the IdentityInfo evidence for entity analytics (SAC-COV-08) |
| `bookmarks` (only when the API refuses the list as too large) | `HuntingBookmark` | The table's retention (no lookback) | Each bookmark's latest entry, less the deleted ones: name, created and updated times, tags and notes, without the query text, result row and entities. Written to `bookmarks-from-logs.json`; the table keeps entries only for its retention, so it can hold fewer bookmarks than the service counts |

SOC optimisation recommendations (`soc-optimization`) are read over REST from
`.../recommendations`, not through KQL.

### Incidents

| Capture | Reads | Window | What it gives |
|---|---|---|---|
| `incidents-summary` | `SecurityIncident` | Lookback | One row of counts: by status, severity, classification and provider, open by severity, and who closed each (automation rule, analyst, Defender XDR or other, the category only), with the recent window and the Defender XDR share beside them |
| `incidents-mttr` | `SecurityIncident` | Lookback | Mean time to acknowledge and to resolve, with the recent window's figures |
| `incidents-daily-metrics` | `SecurityIncident` | Lookback | Incidents created per day |
| `incidents-detail-by-provider` | `SecurityIncident`, `SecurityAlert` | Lookback | Incidents by provider, product and rule, aggregates only |
| `incidents-by-rule` | `SecurityIncident` | Lookback | Incidents per rule title, every title |
| `rule-effectiveness` | `SecurityIncident`, `SecurityAlert` | Lookback | Per detection: incidents, closures, the true, false and benign positive split and the false-positive rate. Sentinel rules are keyed on their rule id, other products' alerts on their name |
| `incident-title-stats` | `SecurityIncident` | Lookback | Titles seen five or more times, with closures, time to close and verdicts, the input to the automation opportunities |

### Analytics and threat intelligence

| Capture | Reads | Window | What it gives |
|---|---|---|---|
| `analytics-rule-volumes` | `SecurityAlert` | Lookback | Alerts per rule, product and severity, each alert counted once (by `SystemAlertId`), with the recent window's count. Summed, the dashboard's Sentinel and Defender XDR alert totals |
| `rules-fired` | `SecurityAlert` | Lookback | Alerts per scheduled or NRT rule, keyed on the rule id so renamed rules stay apart |
| `threat-intel-counts` | `ThreatIntelIndicators`, `ThreatIntelligenceIndicator` | Lookback | Records and distinct indicators per source system |
| `threat-intel-tables` | `ThreatIntelIndicators`, `ThreatIntelObjects`, `ThreatIntelligenceIndicator` | Lookback | Records, first and last record in each, the table migration status on page 27 |
| `threat-intel-health` | `ThreatIntelIndicators` | Lookback | Indicators at their latest state: active, deleted, revoked or expired |
| `threat-intel-objects` | `ThreatIntelObjects` | Lookback | Rows by STIX type |
| `threat-intel-by-type` | `ThreatIntelIndicators` (the retired table when it is absent) | Lookback | Indicators by observable type: IP, domain, URL, file hash, email |

### Table hygiene, agents and connector routing

| Capture | Reads | Window | What it gives |
|---|---|---|---|
| `cef-devices` | `CommonSecurityLog` | Lookback | The top CEF device vendor and product pairs |
| `cef-in-syslog` | `Syslog` | Lookback | CEF records that landed in Syslog, by forwarder, vendor and product (SAC-LOG-23) |
| `security-event-duplicates` | `SecurityEvent` | 1 hour (a sample) | Duplicate records per host, typically MMA and AMA both collecting (SAC-LOG-22) |
| `agent-heartbeat-mix` | `Heartbeat` | Lookback | Machines by OS, agent type (AMA, the legacy MMA, SCOM) and version |
| `ama-agents` | `Heartbeat` | Lookback | Azure Monitor Agent machines with their last heartbeat, OS and version |
| `ama-mma-migration` | `Heartbeat` | Lookback | Machines still reporting through the legacy agent, the MMA to AMA migration status |
| `syslog-contributors` | `Syslog` | Lookback | Records and billed size by host and facility |
| `securityevent-top-hosts` | `SecurityEvent` | Lookback | Records and billed size by host |
| `top-event-ids` | `Event`, `SecurityEvent` (through `find`) | Lookback | Every billable Windows event ID, largest first, for noise tuning |
| `azure-activity-coverage` | `AzureActivity` | Lookback | Volume per subscription, showing subscriptions that send no activity log |
| `azure-diagnostics-providers` | `AzureDiagnostics` | Lookback | Volume by resource provider |
| `azure-firewall-categories` | `AzureDiagnostics` | Lookback | Azure Firewall rows by category, legacy `AzureFirewall*` and resource-specific `AZFW*` side by side |
| `xdr-table-presence` | The Defender XDR tables (`Device*`, `Email*`, `Identity*` and others) | Lookback | Records per table, whether Defender XDR is connected and producing data |

### Daily series for the dashboard's slider

The **daily span** is the lookback, at most 90 days (`daily`). These five count per day
ago (`DaysAgo`, 0 for the last 24 hours, from when the query runs), so the last N days of
them sum to exactly the rolling N-day window the captures above read. The site build
carries them in the dashboard model, whose window slider re-scopes its cards to any number
of days up to the span. Playbook runs are counted per day too, inside `playbook-runs`.

| Capture | Reads | Window | What it gives |
|---|---|---|---|
| `daily-table-usage` | `Usage` | Daily | Billable GB per table per day |
| `daily-alerts` | `SecurityAlert` | Daily | Alerts per day by name, product, severity, provider and rule id, each alert once, on the day it was first seen |
| `daily-incidents` | `SecurityIncident` | Daily | Incidents per day at their latest state, by severity, open or closed, classification and who closed them, with acknowledge and resolve counts and minutes |
| `daily-rule-incidents` | `SecurityIncident`, `SecurityAlert` | Daily | Incidents per detection per day with their verdicts, keyed as `rule-effectiveness` keys them |
| `daily-health` | `SentinelHealth` | Daily | Health events per day by operation and status |

### Two examples

The cheap `Usage` and `Operation` pair that most of the cost section is built on, as they
run (with `lookback` and `recent` declared ahead of them):

1. **`tables-with-data.json`**: which tables receive data

   ```kql
   Usage
   | where TimeGenerated > ago(lookback)
   | summarize
       BillableLast90d = sumif(Quantity, IsBillable == true) / 1024.0,
       IngestedLast90d = sum(Quantity) / 1024.0,
       BillableLast30d = sumif(Quantity, IsBillable == true and TimeGenerated > ago(lookback)) / 1024.0,
       BillableLast7d  = sumif(Quantity, IsBillable == true and TimeGenerated > ago(recent))  / 1024.0,
       IngestedLast7d  = sumif(Quantity, TimeGenerated > ago(recent)) / 1024.0,
       BillableLast24h = sumif(Quantity, IsBillable == true and TimeGenerated > ago(1d))  / 1024.0,
       FirstSeen       = min(TimeGenerated),
       LastIngested    = max(TimeGenerated),
       DayCount        = dcount(bin(TimeGenerated, 1d))
       by DataType, Solution
   ```

2. **`ingestion-latency.json`**: the broken-pipeline signal

   ```kql
   Operation
   | where TimeGenerated > ago(lookback)
   | where OperationCategory in ("Ingestion", "Schema")
   | summarize Failures = countif(OperationStatus != "Succeeded"), Last = max(TimeGenerated)
       by OperationKey = tostring(Detail), Resource = tostring(OperationCategory)
   | where Failures > 0
   ```

## Azure Retail Prices API

Anonymous, with no authentication. Read by `Private/Get-AzureRetailPrice.ps1`.

| | |
|---|---|
| Endpoint | `https://prices.azure.com/api/retail/prices` |
| Filter | `serviceName eq '<name>' and armRegionName eq '<region>' and priceType eq 'Consumption'`, passed as `$filter` |
| Pagination | Follow `NextPageLink` in each response |
| Documentation | [Azure Retail Prices REST API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices) |

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

## Sentinel data grants and pricing

The cost estimate prices with the public Azure Retail Prices API for the
workspace's region, reading two services: `Sentinel` (the simplified
pay-as-you-go, Basic, Auxiliary and data lake meters, and every commitment
tier's price a day as `<n> GB Commitment Tier Capacity Reservation`) and
`Log Analytics` (the classic ingestion meters, the fallback for an older
capture). The meter names it reads are in
`Private/Resources/cost-meters.json`. Prices come in the currency the run
asks for (`-Currency`); `Auto`, the default, takes it from the workspace's
region (`Resolve-AzureRetailCurrency`), since the billing account that
really sets it is not readable with the collector's permissions.

Two data grants cover named tables up to an allowance: the Microsoft 365 E5,
A5, F5 and G5 grant (up to 5 MB per licensed user a day, Entra ID sign-in
and audit logs and the Defender XDR advanced hunting tables) and the
Defender for Servers Plan 2 allowance (500 MB per server a day, SecurityEvent
and the other security tables collected through Defender for Cloud). The
Blueprint cannot read licence or server counts, so it prices those tables at
list and reports the eligible volume beside the total as the most each grant
could save. The lists are in `Private/Resources/sentinel-benefit-tables.json`,
reviewed against
<https://azure.microsoft.com/offers/sentinel-microsoft-365-offer/> and
<https://learn.microsoft.com/azure/defender-for-cloud/data-ingestion-benefit>
on every release. The always-free sources (Azure Activity, Office 365 audit
logs, alerts, SecurityIncident, SentinelHealth) are not billable in `Usage`
and need no entry.

## References

- [Roles and permissions in Microsoft Sentinel](https://learn.microsoft.com/azure/sentinel/roles)
- [Connect from Azure with OpenID Connect](https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect)
- [Azure Retail Prices REST API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices)
