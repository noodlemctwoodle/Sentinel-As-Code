# Health check cross-reference

Where every section of `Invoke-SentinelHealthCheck.ps1` (build 2026.09.25.3,
contributed by Lasitha R) lives in the Documenter after the merge. The
health check was a one-off interactive script with a single HTML report;
its content was ported layer by layer (collector capture, gap rule,
Markdown page, SharePoint dashboard) rather than copied, so each row names
the page and section that carries the idea now, and the gap rule where one
exists. "New" marks sections added by the cross-reference pass; everything
else already existed in the Documenter.

The maturity model is this project's own methodology (see
[Sentinel-Maturity-Model.md](Sentinel-Maturity-Model.md)); the health
check's SOC-CMM naming, levels and identifiers were not carried over.

## Section by section

| Health check section | Documenter page and section | Gap rule | Notes |
| --- | --- | --- | --- |
| Summary: environment at a glance, workspace snapshot, key findings, report contents | `00-overview.md`, `01-live-snapshot.md`; dashboard Overview (glance tiles, posture cards, estate rings, estate flow, maturity card, quick wins, top findings, contents) | | |
| Tenant and subscription | `86-subscription-context.md` | | |
| Log Analytics workspace (SKU, daily cap, retention, network, ingestion summary) | `80-workspace.md` | SAC-LOG-03 | |
| Data export (Blob, Event Hub, ADX) | `36-data-export.md` | | |
| Workspace resilience (replication, CMK, managed identity, Private Link, daily cap) | `80-workspace.md`, "Resilience summary" (new) | SAC-PLT-05, SAC-PLT-06, SAC-GOV-03 | Customer-managed key read from the Sentinel onboarding state |
| Permissions (Sentinel, LAW, Defender XDR; high-privilege assignments) | `85-rbac.md` | SAC-GOV-05, SAC-GOV-04 | |
| Sentinel usage and table costs | `84-cost-estimate.md`; dashboard "Top tables by volume" | | |
| Data retention and improvements (per-table plans, overrides, recommendations) | `81-table-plans-retention.md` ("Tables with non-default retention"), `88-sentinel-data-lake.md` ("Migration candidates") | SAC-LOG-02, SAC-INV-01, SAC-INV-04 | |
| Tables no longer receiving data, split by rules that depend on them | `81-table-plans-retention.md`, "Silent" detail with days silent, rules and a Detection outage / Cost only verdict (new) | SAC-MON-06 | |
| Microsoft Sentinel Data Lake: tables in the lake, analytics retention rolling into the lake, ingestion validation, usage evidence, tables to move, no long-term retention | `88-sentinel-data-lake.md`: tier distribution, retention split, "Lake usage evidence" (new), "Analytics tables without extended lake retention" (new), "Migration candidates"; dashboard Data lake tile and panel | | Ingestion validation is the Gb90d column of the usage evidence: a configured table with no data in 90 days is not being fed |
| Deprecated and legacy features (MMA agents, classic alert rules, legacy connectors) | `87-azure-monitor-agents.md`, `20-analytics-rules.md` ("MS Incident Creation rules"), `10-data-connectors.md` ("Classic connectors") | SAC-DET-08, SAC-PLT-03 | |
| Classic tables (legacy HTTP Data Collector API), inventory and last ingestion | `81-table-plans-retention.md`, "Classic custom tables (legacy Data Collector API)" (new) | SAC-PLT-02 | From `tableSubType = Classic`, with status, rules and an action per table |
| Content Hub solutions: updates and deprecations | `70-content-hub.md` | SAC-DET-07, SAC-DET-13 | |
| Analytics rules: MITRE coverage | `25-mitre-coverage.md`; dashboard MITRE matrix | SAC-MON-04 | |
| Analytics rules: rule health issues | `20-analytics-rules.md`, "Rule run failures (last 7d)" (new, capture `rule-health`) | SAC-DET-14 (new) | |
| Analytics rules: noisy rules, rule effectiveness | `15-incidents.md` ("Rule effectiveness"), `20-analytics-rules.md` ("By alert volume"); dashboard "Rule effectiveness" | SAC-DET-06 | Sentinel rules first, then other products' alerts with the product named |
| Analytics rules: tables ingested but not referenced, suggested templates, unmonitored tables with no templates | `28-detection-opportunities.md`, `81-table-plans-retention.md` ("Tables by detection coverage"); dashboard "Detection opportunities" | SAC-MON-05 | Every template per table is carried; the dashboard reveals them with "Show all" |
| Summary rules | `38-summary-rules.md` | | |
| Data lake tier candidates | `88-sentinel-data-lake.md`, "Migration candidates" | | |
| Automation rules, automation opportunities (frequent, fast-closing incident titles) | `60-automation-rules-playbooks.md`, "Automation opportunities (incident titles, last 30d)" (new, capture `incident-title-stats`) | SAC-AUT-01 | Title-to-response map ported from the health check |
| Playbooks: inventory and recent failures | `60-automation-rules-playbooks.md`, "Playbook runs (last 7d)"; dashboard "Playbook health" | SAC-AUT-02 | Playbooks whose history could not be read are marked Unavailable, not zero |
| Watchlists: inventory and enrichment coverage | `50-watchlists.md` ("Used by analytics rules", "Broken watchlist references") | | |
| Hunting: queries, active hunts, bookmarks | `30-hunting-queries.md` | SAC-HNT-01 | Bookmark count survives an oversized list through `bookmarks-count.json` |
| UEBA and entity analytics | `26-ueba.md` | SAC-COV-05 | |
| Threat intelligence: table migration status, indicator health, by source, by type, STIX types, TAXII feeds, connectors | `27-threat-intelligence.md`: "Indicator distribution by source", "Indicators by type" (new, capture `threat-intel-by-type`), "STIX objects", "Feeds" | SAC-TI-01, SAC-TI-02, SAC-TI-05 | Feeds come from connector kinds rather than the undocumented TAXII client path |
| Ingestion and cost recommendations | `84-cost-estimate.md` ("Commitment-tier what-if"), `90-gap-analysis.md`, `12-soc-optimization.md` | SAC-LOG-03, SAC-LOG-02, SAC-INV-01, SAC-INV-04, SAC-LOG-06 | |
| Data collection rules: inventory, connector and DCR health | `83-data-collection.md`, `11-sentinel-health.md` | | |
| Deep dive: agent posture (AMA vs MMA) | `87-azure-monitor-agents.md` | SAC-PLT-03 | |
| Deep dive: AzureDiagnostics provider and category breakdown, Azure Firewall overlap | `14-coverage-breakdowns.md` | SAC-LOG-06 | |
| Deep dive: AzureActivity by subscription | `14-coverage-breakdowns.md` | | |
| Deep dive: SecurityEvent top event IDs, top hosts, duplicates | `13-data-source-hygiene.md`: "Top 10 noisy event IDs", "SecurityEvent top hosts" (new, capture `securityevent-top-hosts`), "SecurityEvent duplicates" | | |
| Deep dive: Syslog contributors, CEF in Syslog, CommonSecurityLog contributors | `13-data-source-hygiene.md`: "Syslog contributors" (new, capture `syslog-contributors`), "CEF records misrouted into Syslog", "CEF devices" | | |
| Deep dive: Defender XDR tables, Entra ID tables | `14-coverage-breakdowns.md`: "XDR table activity", "XDR table presence", "Entra ID table presence" (new) | | |
| Deep dive: search, restore and KQL job output tables | `37-search-restore.md` | | |
| Deep dive: Defender for Cloud connector status | `10-data-connectors.md`, "Defender XDR unification" (new) | | Subscription-level and tenant-level connector kinds |
| Operations: SentinelHealth operations, LAQueryLogs audit | `11-sentinel-health.md` | | Plus "Ingestion and schema failures" from the `Operation` table |
| Operations: incident metrics | `15-incidents.md` | SAC-INC-06, SAC-INC-05, SAC-INC-02 | |
| Operations: alert volumes by provider | `15-incidents.md` ("Incident detail by provider"), `20-analytics-rules.md` ("By alert volume") | | |
| Operations: legacy Microsoft incident-creation rules | `20-analytics-rules.md`, `10-data-connectors.md` ("Defender XDR unification") | SAC-DET-08 | |
| Operations: TI table version usage | `27-threat-intelligence.md` | SAC-TI-01, SAC-TI-02 | |
| Operations: analytics rule complexity | `20-analytics-rules.md`, "Rule complexity" (new) | | Own heuristic, documented on the page |
| Operations: rules without entity mappings, alert-only rules, stale rules | `20-analytics-rules.md` ("Mouldy rules"), `90-gap-analysis.md` | SAC-DET-03, SAC-MON-01, SAC-DET-04 | |
| Operations: SOC optimization recommendations | `12-soc-optimization.md` | | |
| Sentinel and Defender XDR unification | `10-data-connectors.md`, "Defender XDR unification" (new) | SAC-DET-08 | Defender-portal onboarding is reported as not observable rather than inferred |
| SOC maturity assessment (SOC-CMM) | `91-maturity-assessment.md`; dashboard Maturity tab; maturity history on SharePoint | | Own methodology, NIST CSF 2.0 crosswalk kept |
| Findings and recommended actions | `90-gap-analysis.md`; dashboard Findings; SharePoint findings list with history | all | |

## What was changed on purpose

- The maturity model carries no SOC-CMM naming, levels or identifiers; the
  criteria, impact and guidance wording were reused with credit.
- "Defender portal onboarded" is never inferred: the onboarding state
  resource exists on every Sentinel workspace, so the page says the signal
  is not observable from the workspace API.
- TAXII feeds are read from connector kinds, matched exactly, rather than
  from the undocumented TAXII client path.
- Every capture that can fail is visible as failed, scores as Unknown in
  the maturity model and renders as "not captured" on its page; the
  health check's empty-result fallback is not reproduced.
- Nothing is truncated on the dashboard; lists show their first entries
  with a "Show all" control.
