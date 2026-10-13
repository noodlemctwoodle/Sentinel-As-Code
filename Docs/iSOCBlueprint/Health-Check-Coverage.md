# Health check cross-reference

Where everything in `Invoke-SentinelHealthCheck.ps1` (contributed by
Lasitha R) lives in the Blueprint. This edition checks the copy delivered
on 13 October 2026, which reports build 2026.09.25.3, and the HTML layout
preview that came with it. The health check is a one-off interactive script
with a single HTML report; its content is ported layer by layer (collector
capture, gap rule, Markdown page, SharePoint dashboard) rather than copied.

Three tables follow, so nothing is left unaccounted for:

- **Sections**: every heading the report writes, with the Blueprint page
  and section that carries it.
- **Data**: every query and API call the script makes, with the `_raw`
  capture that holds the same data.
- **Findings**: every key finding the report raises, with the gap rule
  that raises it here.

"New" marks what this pass added. The maturity model is this project's own
methodology (see [Sentinel-Maturity-Model.md](Sentinel-Maturity-Model.md)); the
health check's SOC-CMM naming, levels and identifiers were not carried
over.

## Page map

The report's 28 numbered sections against the Blueprint pages that hold
them. The Blueprint groups by topic rather than copying the report's two
deep-dive sections, so those spread over several pages; the table below
lists each subsection.

| Report section | Blueprint pages |
| --- | --- |
| 1 Summary | `00-overview.md`, `01-live-snapshot.md` |
| 2 Tenant and subscription | `86-subscription-context.md` |
| 3 Log Analytics workspace, ingestion summary | `80-workspace.md`, `81-table-plans-retention.md` |
| 4 Data export | `36-data-export.md` |
| 5 Workspace resilience | `80-workspace.md` |
| 6 Permissions | `85-rbac.md` |
| 7 Sentinel usage and table costs | `84-cost-estimate.md` |
| 8 Data retention and improvements | `89-retention.md` |
| 9 Microsoft Sentinel data lake | `88-sentinel-data-lake.md` |
| 10 Deprecated and legacy features | `02-deprecated-legacy-features.md`; agent heartbeat mix on `87-azure-monitor-agents.md` |
| 11 Classic tables | `81-table-plans-retention.md` |
| 12 Content Hub solutions | `70-content-hub.md` |
| 13 Analytics rules | `20-analytics-rules.md`, `21-rule-performance.md`, `22-rule-health-quality.md`; MITRE on `25-mitre-coverage.md`; unmonitored tables on `28-detection-opportunities.md` |
| 14 Summary rules | `38-summary-rules.md` |
| 15 Auxiliary tier candidates | `88-sentinel-data-lake.md`, "Migration candidates" |
| 16 Automation rules, 17 Playbooks | `60-automation-rules-playbooks.md` |
| 18 Watchlists | `50-watchlists.md` |
| 19 Hunting | `30-hunting-queries.md` |
| 20 UEBA and entity analytics | `26-ueba.md` |
| 21 Threat intelligence and feeds | `27-threat-intelligence.md` |
| 22 Ingestion and cost recommendations | `84-cost-estimate.md`, `90-gap-analysis.md` |
| 23 Data collection rules | `83-data-collection.md`; connector and DCR health on `11-sentinel-health.md` |
| 24 Configuration and ingestion deep dive | `87-azure-monitor-agents.md`, `14-coverage-breakdowns.md`, `13-data-source-hygiene.md`, `37-search-restore.md`, `10-data-connectors.md` |
| 25 Operations deep dive | `11-sentinel-health.md`, `15-incidents.md`, `16-alerts.md`, `27-threat-intelligence.md`, `22-rule-health-quality.md`, `12-soc-optimization.md` |
| 26 Sentinel and Defender XDR unification | `10-data-connectors.md` |
| 27 SOC maturity assessment | `91-maturity-assessment.md` |
| 28 Findings and recommended actions | `90-gap-analysis.md` |

## Sections

The report numbers its sections in the HTML; the script names them. Sections
the HTML preview omits (because that run had no data for them) are listed
too.

| Health check section | Blueprint page and section | Gap rules |
| --- | --- | --- |
| Summary: environment at a glance | `00-overview.md` (headline, counts, estate flow); dashboard Overview glance tiles and estate rings | |
| Summary: workspace snapshot | `01-live-snapshot.md`, "Workspace at a glance" | |
| Summary: key findings | `00-overview.md`, "Top findings"; `01-live-snapshot.md`, "Top recommendations"; dashboard top findings | all |
| Summary: report contents | `index.md`; SharePoint navigation and the dashboard contents cards | |
| Tenant and subscription | `86-subscription-context.md`, "Subscription" and "Signed-in identity" (new) | SAC-PLT-09 |
| Log Analytics workspace | `80-workspace.md`, "SKU and pricing", "Networking + replication" | SAC-LOG-03 |
| Log Analytics workspace: ingestion summary | `80-workspace.md`, "Usage telemetry" and the daily ingestion chart | |
| Data export: continuous data exports | `36-data-export.md`, "Continuous data exports" (heading and destination type new) | |
| Data export: linked storage accounts | `36-data-export.md`, "Linked storage accounts" (new) | |
| Data export: ADX clusters linked to the workspace | `36-data-export.md`, "ADX clusters linked to the workspace" (new) | |
| Workspace resilience and resilience findings | `80-workspace.md`, "Resilience summary" | SAC-PLT-05, SAC-PLT-06, SAC-GOV-03 |
| Permissions: assignments by role | `85-rbac.md`, "Assignments by role" (new) | |
| Permissions: Sentinel role assignments | `85-rbac.md`, "Microsoft Sentinel role assignments" (new) | SAC-GOV-04 |
| Permissions: Log Analytics and monitoring role assignments | `85-rbac.md`, "Log Analytics and monitoring role assignments" (new) | |
| Permissions: high-privilege assignments | `85-rbac.md`, "High-privilege assignments" (new) | SAC-GOV-06, SAC-GOV-05 |
| Sentinel usage and table costs: top tables by cost | `84-cost-estimate.md`, "Tables by cost" (every table; the chart shows the ten costliest); dashboard top tables | |
| Data retention: per-table retention overrides | `89-retention.md`, "Tables with non-default retention" | |
| Data retention: retention improvement recommendations | `89-retention.md`, "Retention recommendations" (new, all three checks shown with their outcome) | SAC-LOG-07 |
| Tables no longer receiving data, with and without rules | `81-table-plans-retention.md`, "Silent" detail with days silent, rules and verdict | SAC-MON-06, SAC-INV-01 |
| Data lake: tables ingested into the lake | `88-sentinel-data-lake.md`, tier distribution and "Lake-only tables" | |
| Data lake: analytics retention that rolls into the lake | `89-retention.md`, "Retention that rolls into the lake" (now every table, with volume and rules, rather than the top ten) | |
| Data lake: ingestion validation | `89-retention.md`, "Ingestion validation" (new) | |
| Data lake: which lake tables are used | `88-sentinel-data-lake.md`, "Lake usage evidence" | SAC-LOG-21 (new) |
| Data lake: tables that should move to the lake | `88-sentinel-data-lake.md`, "Migration candidates" | SAC-LOG-02 |
| Data lake: analytics tables with no long-term retention | `88-sentinel-data-lake.md`, "Analytics tables without extended lake retention" | SAC-LOG-14 |
| Deprecated and legacy features | `02-deprecated-legacy-features.md`, "Legacy features still in use" with the deadline runway (new) | SAC-PLT-03, SAC-PLT-02, SAC-TI-01, SAC-TI-02, SAC-DET-08, SAC-LOG-06 |
| Deprecated and legacy features: agent heartbeat mix | `87-azure-monitor-agents.md`, "Agent heartbeat mix" (new) | SAC-PLT-03 |
| Classic tables: inventory, still receiving data, dormant | `81-table-plans-retention.md`, "Classic custom tables (legacy Data Collector API)" | SAC-PLT-02, SAC-INV-04 |
| Content Hub solutions: updates and deprecations | `70-content-hub.md` | SAC-DET-07, SAC-DET-13 |
| Analytics rules: MITRE ATT&CK tactic coverage | `25-mitre-coverage.md`; dashboard MITRE matrix | SAC-MON-04 |
| Analytics rules: rule health issues | `22-rule-health-quality.md`, "Rule run failures (last 7d)" | SAC-DET-14 |
| Analytics rules: noisy rules | `21-rule-performance.md`, "Noisy rules (closed mostly as false positive)" | SAC-DET-06 |
| Analytics rules: rule effectiveness | `21-rule-performance.md`, "Rule effectiveness (last 30d)", every detection (Sentinel rules first) rather than the top 25 | |
| Analytics rules: tables ingested but not referenced by any rule | `28-detection-opportunities.md`, "Tables with data but no detection" with every template per table (previously three and a count); `81-table-plans-retention.md`, "Tables by detection coverage" | SAC-MON-05 |
| Analytics rules: suggested rules for unmonitored tables | `28-detection-opportunities.md`, "Undeployed templates ready to enable"; dashboard detection opportunities | SAC-MON-05 |
| Analytics rules: unmonitored tables with no available templates | `28-detection-opportunities.md`, "Tables with no template available" (new) | SAC-MON-05 |
| Summary rules: configured summary rules | `38-summary-rules.md` | SAC-LOG-19 (new) |
| Data lake tier candidates (the preview calls it auxiliary tier candidates) | `88-sentinel-data-lake.md`, "Migration candidates" | SAC-LOG-02 |
| Automation rules and automation opportunities | `60-automation-rules-playbooks.md`, "Automation rules" and "Automation opportunities" | SAC-AUT-01 |
| Playbooks: inventory and recent failures | `60-automation-rules-playbooks.md`, "Playbooks (Logic Apps)" and "Playbook runs (last 7d)"; dashboard playbook health | SAC-AUT-02, SAC-AUT-05 |
| Watchlists | `50-watchlists.md` | |
| Hunting: hunting queries, active hunts, bookmarks | `30-hunting-queries.md`, every query rather than the top 50 | SAC-HNT-01 |
| UEBA and entity analytics | `26-ueba.md`, with "Entity analytics" (new) | SAC-COV-05, SAC-COV-08 (new) |
| Threat intelligence: TI table migration status | `27-threat-intelligence.md`, "Table migration status" (new) | SAC-TI-01 |
| Threat intelligence: indicator health | `27-threat-intelligence.md`, "Indicator health (last 30d)" (new) | |
| Threat intelligence: indicators by source | `27-threat-intelligence.md`, the source distribution and "Indicators by source (last 30d)" (new, with distinct indicators) | SAC-TI-05 |
| Threat intelligence: indicators by type | `27-threat-intelligence.md`, "Indicators by type (last 30d)" | |
| Threat intelligence: STIX object types | `27-threat-intelligence.md`, "STIX objects (last 30d)" | |
| Threat intelligence: TAXII feeds | `27-threat-intelligence.md`, "TAXII clients" (new) | SAC-TI-05 |
| Threat intelligence: connectors | `27-threat-intelligence.md`, "Threat intelligence connectors" | SAC-TI-05 |
| Ingestion and cost recommendations | `84-cost-estimate.md`, `90-gap-analysis.md`, `12-soc-optimization.md` | SAC-LOG-02, SAC-LOG-15 to SAC-LOG-19 |
| Data collection rules: inventory | `83-data-collection.md`, "DCRs" | |
| Data collection rules: connector and DCR health issues | `11-sentinel-health.md`, "Connector and DCR health issues (last 7d)" (new, with failure counts) | |
| Deep dive: agent posture (AMA vs MMA by machine type) | `87-azure-monitor-agents.md`, "AMA vs MMA migration status" | SAC-PLT-03 |
| Deep dive: AzureDiagnostics by resource provider and category | `14-coverage-breakdowns.md`, per resource provider and per category (new) | SAC-LOG-18 |
| Deep dive: Azure Firewall legacy and modern category overlap | `14-coverage-breakdowns.md`, "Azure Firewall categories (last 7d)" (new) | SAC-LOG-06 |
| Deep dive: AzureActivity by subscription | `14-coverage-breakdowns.md` | |
| Deep dive: SecurityEvent top event IDs by size | `13-data-source-hygiene.md`, "Event IDs by billed size (last 7d)" (every event ID with its record count) | SAC-LOG-17 |
| Deep dive: SecurityEvent top hosts | `13-data-source-hygiene.md`, "SecurityEvent hosts (last 7d)" (every host) | |
| Deep dive: SecurityEvent duplicates | `13-data-source-hygiene.md`, "SecurityEvent duplicates (last 1h)" (duplicated events new) | SAC-LOG-22 (new) |
| Deep dive: Syslog contributors | `13-data-source-hygiene.md`, "Syslog contributors (last 7d)" | SAC-LOG-16 |
| Deep dive: CEF records landing in Syslog | `13-data-source-hygiene.md`, "CEF records misrouted into Syslog" (vendor and product new) | SAC-LOG-23 (new) |
| Deep dive: CommonSecurityLog contributors | `13-data-source-hygiene.md`, "CEF devices (last 7d)" | SAC-LOG-15 |
| Deep dive: Defender XDR tables ingested | `14-coverage-breakdowns.md`, XDR table activity and presence | |
| Deep dive: Entra ID tables present | `14-coverage-breakdowns.md`, Entra ID table presence | |
| Deep dive: search, restore and KQL job output tables | `37-search-restore.md` | |
| Deep dive: Defender for Cloud connector status | `10-data-connectors.md`, "Defender XDR unification" | SAC-COV-07 |
| Operations: SentinelHealth operations | `11-sentinel-health.md`, "Operations summary" | |
| Operations: LAQueryLogs audit | `11-sentinel-health.md`, "Query logging activity" | SAC-PLT-12 (new) |
| Operations: incident metrics (7d) | `15-incidents.md`, "Incident metrics (last 7d)" (new) | SAC-INC-05, SAC-INC-06, SAC-INC-02 |
| Operations: alert volumes by provider | `16-alerts.md`, "Alert volumes by provider (last 7d)" (new, every alert name that fired rather than the top 25) | |
| Operations: legacy Microsoft incident creation rules | `20-analytics-rules.md`, "MS Incident Creation rules" | SAC-DET-08 |
| Operations: threat intelligence table version usage | `20-analytics-rules.md` and `27-threat-intelligence.md` | SAC-TI-02 |
| Operations: analytics rule complexity | `22-rule-health-quality.md`, "Rule complexity" | |
| Operations: rules without entity mappings | `22-rule-health-quality.md`, "Rules without entity mappings" (new) | SAC-DET-03 |
| Operations: rules producing alerts only | `22-rule-health-quality.md`, "Rules that raise alerts without incidents" (new) | SAC-MON-01 |
| Operations: stale rules | `22-rule-health-quality.md`, "Stale rules" | SAC-DET-04 |
| Operations: SOC optimization recommendations | `12-soc-optimization.md` | |
| Sentinel and Defender XDR unification | `10-data-connectors.md`, "Defender XDR unification", with unified incidents, Defender XDR alerts and the retired Azure Security Center path (new) | SAC-DET-08, SAC-PLT-11 |
| Maturity: scope of this assessment | `91-maturity-assessment.md`, header and "Out of scope" | |
| Maturity: framework alignment | `91-maturity-assessment.md`, "NIST CSF 2.0 rollup" | |
| Maturity: the maturity scale | `91-maturity-assessment.md`, "Maturity scale" (new) | |
| Maturity: matrix by aspect | `91-maturity-assessment.md`, "Area scores" and "Areas"; dashboard Assessment tab (maturity view) | |
| Maturity: domain summary | Not carried: the areas are not grouped into SOC-CMM domains | |
| Maturity: score breakdown, evidence and next steps | `91-maturity-assessment.md`, "Criteria" | |
| Maturity: open gaps and operational impact | `91-maturity-assessment.md`, "Open gaps and their impact" (new) | |
| Maturity: improvement roadmap | `91-maturity-assessment.md`, "Roadmap" (every gap) | |
| Maturity: quick wins | `91-maturity-assessment.md`, "Quick wins" | |
| Maturity: assessment scope and limitations | `91-maturity-assessment.md`, "Out of scope" | |
| Maturity: full assessment evidence by aspect | `91-maturity-assessment.md`, "Criteria", evidence column | |
| Maturity: reference, aspects and NIST CSF 2.0 subcategories | [Sentinel-Maturity-Model.md](Sentinel-Maturity-Model.md); the subcategories in `maturity.json` and on the dashboard Assessment tab (maturity view) | |
| Findings and recommended actions | `90-gap-analysis.md`; dashboard Findings; SharePoint findings list with history | all |

## Data

Every call the script makes, and the capture in `_raw/` that holds the same
data. Where the window or shape differs, the note says how.

### Azure Resource Manager and Az cmdlets

| Health check call | Blueprint capture | Note |
| --- | --- | --- |
| `Get-AzSubscription`, `Get-AzContext` (tenant, subscription, signed-in account) | `subscription.json`, `run-context.json` | `Account` and `AccountType` in the run context are new |
| `Get-AzOperationalInsightsWorkspace`; workspace GET (SKU, cap, network, replication, identity, cluster) | `workspace.json` | api-version 2025-02-01 |
| `.../settings/SentinelDataLake` and the other data lake probes | `sentinel-data-lake.json` | Read from Resource Graph (`sentinelPlatformServices`) instead; see below |
| `.../dataExports` | `data-exports.json` | |
| `.../linkedStorageAccounts` | `linked-storage-accounts.json` | New |
| `.../linkedServices` | `linked-services.json` | |
| `.../providers/Microsoft.Insights/diagnosticSettings` | `diagnostic-settings.json` | |
| `Get-AzRoleAssignment` at workspace scope | `rbac-workspace.json` (and `rbac-resourcegroup.json`) | |
| `.../tables` (newest version first) | `workspace-tables.json` | Now 2025-02-01, falling back to 2023-09-01 |
| `.../alertRules` | `alert-rules.json`, `rule-table-references.json` | |
| `.../contentPackages`, `.../contentProductPackages` | `content-packages.json`, `content-product-packages.json` | |
| `.../alertRuleTemplates` | `alert-rule-templates.json`, `template-table-references.json` | |
| `.../automationRules` | `automation-rules.json` | |
| `Microsoft.Logic/workflows` and their runs | `playbooks.json`, `playbook-runs.json`, `rbac-playbook-mi.json` | |
| `.../settings/Ueba`, `.../settings/EntityAnalytics` | `settings.json` | |
| `.../watchlists` | `watchlists.json` | |
| `Microsoft.Insights/workbooks` in the resource group | `workbooks-saved.json` | Scoped to the workspace rather than the resource group |
| `.../huntsessions` | `hunts.json` | The documented `hunts` resource |
| `.../savedSearches` | `kql-savedsearches.json`, `hunting-queries.json`, `parsers-functions.json` | |
| `.../bookmarks` | `bookmarks.json`, or `bookmarks-count.json` when the list is too large | |
| `.../threatIntelligence/main/taxiiClients` | `taxii-clients.json` | New |
| `.../dataConnectors` (TI connectors, Defender for Cloud) | `data-connectors-classic.json` | |
| `.../summaryLogs` | `summary-rules.json` | |
| `Microsoft.Insights/dataCollectionRules` in the subscription | `dcrs.json` | |
| `.../onboardingStates/default` | `onboarding-state.json` | |
| `.../recommendations` (SOC optimization) | `soc-optimization.json` | |

### KQL

| Health check query | Blueprint capture | Note |
| --- | --- | --- |
| Per-table record count and first and last ingestion (classic tables over 90 days, lake tables over the lookback) | `tables-with-data.json` | From `Usage` over 90 days: GB rather than records, last ingestion per table |
| `Usage` billable GB by table | `tables-with-data.json` | 90, 30, 7 days and 24 hours |
| `Usage` billable GB per day | `workspace-usage-daily.json` | Free GB beside it |
| `Heartbeat` agent mix by OS, category, version | `agent-heartbeat-mix.json` | New |
| `Heartbeat` AMA and MMA by machine type | `ama-mma-migration.json` | Finer machine types |
| `SecurityAlert` from Azure Security Center (7 days) | `analytics-rule-volumes.json` | Product name over 30 days |
| `SentinelHealth` analytics rule failures | `rule-health.json` | 7 days rather than the lookback |
| Rule effectiveness (incidents, closures, verdicts per rule) | `rule-effectiveness.json` | Keyed on rule id, other products' alerts included |
| Tables with no billable data for 7 days | `tables-with-data.json` | |
| Automation opportunities (frequent, fast-closing titles) | `incident-title-stats.json` | Thresholds applied on the page |
| `BehaviorAnalytics` rows (7 days) | `ueba-data-presence.json` | `Count7d` new |
| `IdentityInfo` rows (14 days) | `ueba-data-presence.json` | `Count14d` new |
| TI feature probe (7 days) and TI table volumes (30 days) | `threat-intel-tables.json` | New |
| TI by source, with distinct indicators | `threat-intel-counts.json` | `Indicators` new |
| TI by type | `threat-intel-by-type.json` | |
| TI indicator activity (active, deleted, revoked, valid) | `threat-intel-health.json` | New |
| TI STIX object types | `threat-intel-objects.json` | |
| Microsoft Defender TI seen (7 days) | `threat-intel-counts.json` | Source names over 30 days |
| `SentinelHealth` data connector failures | `sentinel-health.json` | `Failures` and `LastFailure` new |
| Alerts and providers in the lookback | `analytics-rule-volumes.json` | |
| Sentinel alert names fired | `rules-fired.json` | Keyed on rule id |
| Active and seen tables | `tables-with-data.json` | |
| Incidents by status and severity | `incidents-summary.json` | |
| Microsoft 365 Defender alerts (7 days) | `analytics-rule-volumes.json` | |
| `DeviceInfo` presence (1 day) | `xdr-table-presence.json` | Every XDR table over 7 days |
| Unified incidents (7 days) | `incidents-summary.json` | `Unified`, `Unified7d` and `ByProvider` new |
| `SentinelHealth` operations by name and status | `sentinel-health-summary.json` | |
| `LAQueryLogs` count (7 days) | `la-query-logs.json` | |
| Incident metrics (7 days, with MTTA) | `incidents-summary.json`, `incidents-mttr.json` | 7-day columns new |
| Alerts by provider and alert name (7 days) | `analytics-rule-volumes.json` | `ProviderName` and `Alerts7d` new |
| `SecurityEvent` top event IDs by size | `top-event-ids.json` | Every event ID rather than a top N; `LogCount` new; `Event` included |
| `SecurityEvent` top hosts | `securityevent-top-hosts.json` | |
| `SecurityEvent` duplicates (1 hour) | `security-event-duplicates.json` | `DuplicateRecords` new |
| `AzureDiagnostics` by resource provider and category | `azure-diagnostics-providers.json`, `azure-diagnostics-categories.json` | |
| Azure Firewall categories, legacy and modern | `azure-firewall-categories.json` | New |
| `AzureActivity` by subscription | `azure-activity-coverage.json` | |
| `Syslog` contributors by host and facility | `syslog-contributors.json` | Billed size beside the count |
| CEF records in `Syslog` | `cef-in-syslog.json` | `CEF:` prefix and vendor-product new; 7 days rather than 1 |
| `CommonSecurityLog` by vendor and product | `cef-devices.json` | |
| `LAQueryLogs` queries, users and last query per lake table | `table-query-usage.json` | |

## Findings

| Health check key finding | Gap rule |
| --- | --- |
| Legacy MMA agents detected; machines still on MMA | SAC-PLT-03 |
| Classic alert rules in use | Not carried; see below |
| Deprecated Content Hub solutions | SAC-DET-13 |
| Content Hub updates available | SAC-DET-07 |
| MITRE coverage gaps | SAC-MON-04 |
| Noisy rules driving a high false-positive rate | SAC-DET-06 |
| Rules with execution failures | SAC-DET-14 |
| UEBA not enabled | SAC-COV-05 |
| Entity analytics not enabled | SAC-COV-08 (new) |
| No automation rules | SAC-AUT-01 |
| Playbooks failing | SAC-AUT-02 |
| Workspace not onboarded to the Defender portal | SAC-PLT-11 (onboarding itself is not observable) |
| Tables that are candidates for cheaper tiers | SAC-LOG-02, SAC-LOG-11, SAC-LOG-14 |
| Ingested tables with no analytics rules | SAC-MON-05 |
| Workspace resilience gaps | SAC-PLT-05, SAC-PLT-06, SAC-GOV-03 |
| Daily cap not configured | SAC-LOG-03 |
| Summary rules not in use | SAC-LOG-19 (new) |
| No threat intelligence, legacy table only, or both tables | SAC-TI-01, SAC-TI-05 |
| Few hunting queries | SAC-HNT-01 |
| Many high-privilege assignments at workspace scope | SAC-GOV-06, SAC-GOV-05 |
| Tables rules depend on have gone silent (detection gap) | SAC-MON-06 |
| Silent tables nothing depends on | SAC-INV-01 |
| Classic tables still on the Data Collector API, ingesting, or empty | SAC-PLT-02, SAC-INV-04 |
| Analytics retention longer than total retention | SAC-LOG-20 (new) |
| Lake tables with no or stale ingestion | SAC-INV-01, SAC-MON-06; page 89 ingestion validation |
| Lake tables with no usage | SAC-LOG-21 (new) |
| High-volume tables paying full analytics retention | SAC-LOG-02, SAC-LOG-11 |
| Analytics tables with no long-term lake retention | SAC-LOG-14 |
| Azure Firewall categories collected twice | SAC-LOG-06 |
| SecurityEvent duplicates | SAC-LOG-22 (new) |
| CEF records in the Syslog table | SAC-LOG-23 (new) |
| Legacy Microsoft incident-creation rules | SAC-DET-08 |
| Rules without entity mappings | SAC-DET-03 |
| Rules producing alerts only | SAC-MON-01 |
| Rules unmodified for over 12 months | SAC-DET-04 |
| Rules reading the retired TI table | SAC-TI-02 |
| LAQueryLogs not enabled | SAC-PLT-12 (new) |
| Defender for Cloud connector not configured | SAC-COV-07 |

## What was changed on purpose

- The maturity model carries no SOC-CMM naming, levels, identifiers or
  domains; the criteria, impact and guidance wording were reused with
  credit.
- "Defender portal onboarded" is never inferred: the onboarding state
  resource exists on every Sentinel workspace, so the page says the signal
  is not observable from the workspace API.
- The data lake is read from the `sentinelPlatformServices` resource
  through Resource Graph, which reports enrolment for the tenant, rather
  than from the settings paths the script probes.
- Hunts come from the documented `hunts` resource rather than
  `huntsessions`.
- The classic alert rule count is not carried: it matches template names
  containing "classic", which a template GUID never does.
- `Get-AzOperationalInsightsIntelligencePack` is only used by the script to
  pick a workspace interactively; the collector is given its workspace.
- TAXII clients are captured, but the TI connectors stay the primary feed
  signal, because the TAXII client path is not in the published REST
  reference.
- Every capture that can fail is visible as failed or "not captured",
  scores as Unknown in the maturity model and never reads as "none"; the
  health check's empty-result fallback is not reproduced.
- Nothing is truncated: where the report shows a top 25 or top 50, the
  Blueprint lists every row, and the dashboard shows the first entries with
  a "Show all" control. The captures carry no row cap either: their queries
  sort but never `take` or `top`, finding evidence names every item, and a
  chart that folds a long tail into "Other" sits beside a table listing
  every item.
- Status words are plain text (Critical, Warning, Covered, Gap) rather than
  the report's coloured emoji; the Word report colours them by column.
