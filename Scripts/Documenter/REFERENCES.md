# Sentinel Documenter — References & Conventions

A durable record of every API version, module, KQL query and Microsoft Learn page the
documenter depends on. When something in Microsoft's surface area changes, this page is
the first thing to update; the change then ripples through `Documenter.psd1`,
`Private/Invoke-SentinelRest.ps1`, and the gap-rule resources.

> **Banner** Microsoft Sentinel in the Azure portal **retires 2027-03-31** in favour of
> the unified Defender XDR experience. Track the migration timeline at
> <https://learn.microsoft.com/azure/sentinel/move-to-defender>.

## API versions in use

| Surface | Version | Why |
|---|---|---|
| `Microsoft.SecurityInsights/*` | `2024-09-01` | GA. Covers connectors, alert rules, automation rules, watchlists, metadata, content packages. |
| `Microsoft.SecurityInsights/*` (preview) | `2024-10-01-preview` | Content Hub product packages, summary rules, `pricings` resource. |
| `Microsoft.OperationalInsights/workspaces` | `2025-02-01` | Required for `replication`, `publicNetworkAccessForIngestion/Query`, full feature flags. |
| `Microsoft.OperationalInsights/workspaces/tables` | `2023-09-01` | `plan` (Analytics/Basic/Auxiliary/DataLake), `retentionInDays`, `totalRetentionInDays`, `archiveRetentionInDays`. |
| `Microsoft.Insights/dataCollectionRules` (full JSON) | `2023-03-11` | Cmdlet output flattens transforms; REST returns `streamDeclarations` and `dataFlows.transformKql`. |

## Modules

Pinned in `Documenter.psd1`. Use `Az.SecurityInsights` cmdlets where they exist; fall back
to `Invoke-AzRestMethod` (via `Private/Invoke-SentinelRest.ps1`) for the surface listed
below in [REST-only gaps](#rest-only-gaps).

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

These items have no `Az.SecurityInsights` cmdlet (as of the pinned module versions) and
go via `Invoke-SentinelRest`:

- Codeless Connector Framework (CCF) — `dataConnectors` (kind `RestApiPoller`/`GCP` etc.)
  and `dataConnectorDefinitions`.
- Content Hub — `contentPackages`, `contentTemplates`, `contentProductPackages`.
- Repositories — `sourceControls`.
- Summary rules — `contentTemplates?$filter=properties/contentKind eq 'SummaryRule'`.
- Sentinel settings — `Microsoft.SecurityInsights/settings/{Ueba,EntityAnalytics,EyesOn,Anomalies}`.
- DCR full JSON (transforms) — `Microsoft.Insights/dataCollectionRules/{name}`.
- Pricings resource — `Microsoft.SecurityInsights/pricings`.
- Sentinel Data Lake — workspace lake feature + organisational lake resource.

## Recurring KQL queries

The collector issues exactly two KQL queries (cheap; both target the `Usage`/`Operation`
billing-metadata tables, not raw data):

1. **`tables-with-data.json`** — *which schema'd tables actually receive data*

   ```kql
   Usage
   | where TimeGenerated > ago(90d)
   | summarize
       BillableGB    = sumif(Quantity, IsBillable == true) / 1024.0,
       IngestedGB    = sum(Quantity) / 1024.0,
       FirstSeen     = min(TimeGenerated),
       LastIngested  = max(TimeGenerated),
       DayCount      = dcount(bin(TimeGenerated, 1d)),
       BillableLast24h = sumif(Quantity, IsBillable == true and TimeGenerated > ago(1d)) / 1024.0,
       BillableLast7d  = sumif(Quantity, IsBillable == true and TimeGenerated > ago(7d))  / 1024.0
       by DataType, Solution
   ```

2. **`ingestion-latency.json`** — broken-pipeline detector

   ```kql
   Operation
   | where TimeGenerated > ago(7d)
   | where OperationCategory in ("Ingestion", "Schema")
   | summarize Failures = countif(OperationStatus != "Succeeded"), Last = max(TimeGenerated) by OperationKey, Resource
   | where Failures > 0
   ```

## Best-practice Microsoft Learn pages

Linked from `90-gap-analysis.md` and individual section pages.

- Sentinel best practices — <https://learn.microsoft.com/azure/sentinel/best-practices>
- Deployment guide — <https://learn.microsoft.com/azure/sentinel/deploy-overview>
- Skill-up training — <https://learn.microsoft.com/azure/sentinel/skill-up-resources>
- Workspace design — <https://learn.microsoft.com/azure/azure-monitor/logs/workspace-design>
- Sample workspace designs — <https://learn.microsoft.com/azure/sentinel/sample-workspace-designs>
- MITRE coverage — <https://learn.microsoft.com/azure/sentinel/mitre-coverage>
- Connector reference — <https://learn.microsoft.com/azure/sentinel/data-connectors-reference>
- Connector prioritisation — <https://learn.microsoft.com/azure/sentinel/prioritize-data-connectors>
- Tables ↔ connectors map — <https://learn.microsoft.com/azure/sentinel/sentinel-tables-connectors-reference>
- Cost optimisation — <https://learn.microsoft.com/azure/azure-monitor/fundamentals/best-practices-cost>
- Cost logs — <https://learn.microsoft.com/azure/azure-monitor/logs/cost-logs>
- Daily cap — <https://learn.microsoft.com/azure/azure-monitor/logs/daily-cap>
- Table plans — <https://learn.microsoft.com/azure/azure-monitor/logs/logs-table-plans>
- Basic logs configuration — <https://learn.microsoft.com/azure/azure-monitor/logs/basic-logs-configure>
- Retention & archive — <https://learn.microsoft.com/azure/azure-monitor/logs/data-retention-archive>
- Sentinel Data Lake overview — <https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-overview>
- Sentinel billing — <https://learn.microsoft.com/azure/sentinel/billing>
- Sentinel reduce costs — <https://learn.microsoft.com/azure/sentinel/billing-reduce-costs>
- Sentinel monitor costs — <https://learn.microsoft.com/azure/sentinel/billing-monitor-costs>
- Roles & permissions — <https://learn.microsoft.com/azure/sentinel/roles>
- Content Hub — <https://learn.microsoft.com/azure/sentinel/sentinel-solutions>
- CCF authoring — <https://learn.microsoft.com/azure/sentinel/create-codeless-connector>
- CI/CD — <https://learn.microsoft.com/azure/sentinel/ci-cd>
- Custom content CI/CD — <https://learn.microsoft.com/azure/sentinel/ci-cd-custom-content>
- Connector health monitoring — <https://learn.microsoft.com/azure/sentinel/monitor-data-connectors-health>
- Workspace replication — <https://learn.microsoft.com/azure/azure-monitor/logs/workspace-replication>
- Dedicated clusters — <https://learn.microsoft.com/azure/azure-monitor/logs/logs-dedicated-clusters>
- Customer-managed keys — <https://learn.microsoft.com/azure/azure-monitor/logs/customer-managed-keys>
- Private Link Scope (AMPLS) — <https://learn.microsoft.com/azure/azure-monitor/logs/private-link-security>
- Manage data overview — <https://learn.microsoft.com/azure/sentinel/manage-data-overview>
- Manage table tiers & retention — <https://learn.microsoft.com/azure/sentinel/manage-table-tiers-retention>
- Defender migration — <https://learn.microsoft.com/azure/sentinel/move-to-defender>

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
