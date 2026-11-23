#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 88-sentinel-data-lake.md (part 3 of 3).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/SentinelDataLake/Write-BlueprintSentinelDataLakeSectionPart3.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintSentinelDataLakeSectionPart3 {
    <#
    .SYNOPSIS
        Build the figures for and write 88-sentinel-data-lake.md (part 3 of 3).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $analyticsCost = $Context.analyticsCost
    $analyticsGb = $Context.analyticsGb
    $assetDataRows = $Context.assetDataRows
    $cost = $Context.cost
    $dlCandidateRows = $Context.dlCandidateRows
    $lakeArchitectureBlock = $Context.lakeArchitectureBlock
    $lakeBillingMeters = $Context.lakeBillingMeters
    $lakeCapabilities = $Context.lakeCapabilities
    $lakeCost = $Context.lakeCost
    $lakeGb = $Context.lakeGb
    $lakeHeadline = $Context.lakeHeadline
    $lakeResourceBlock = $Context.lakeResourceBlock
    $lakeSignals = $Context.lakeSignals
    $lakeTablesBlock = $Context.lakeTablesBlock
    $lakeUsageBlock = $Context.lakeUsageBlock
    $tierChartBlock = $Context.tierChartBlock

    # Asset-data block — present when at least one asset-family table is
    # detected. Helps confirm the Lake's auto-onboarded system tables
    # (Entra, M365, Azure Resource Graph) are flowing.
    $assetDataBlock = if ($assetDataRows.Count -gt 0) {
        @"

## Auto-ingested asset data

Sentinel Data Lake automatically creates and ingests asset-data tables on tenant onboarding (Microsoft Entra identity records, Microsoft 365 activity, Azure Resource Graph asset snapshots, plus UEBA enrichment). These tables appear in the Lake exploration UI as *System tables*. Receiving-data status confirms each pipeline is active.

$(Format-BlueprintTable -Items $assetDataRows -Columns 'Table','Family','IngestState','Retention')
"@
    } else { '' }

    $lakeBody = @"
$(Format-Banner -Title 'Microsoft Sentinel Data Lake')

$lakeHeadline

## Enrollment signals

The blueprint's primary signal is the **Microsoft.SentinelPlatformServices/sentinelPlatformServices** resource, captured through Resource Graph across every visible subscription. Presence of this resource means the tenant is onboarded to Sentinel Data Lake; absence means the tenant is not. The other two rows are supporting checks: the workspace-level billing flag and the table-plan routing state.

$(Format-BlueprintTable -Items $lakeSignals -Columns 'Signal','Value','Interpretation')
$lakeResourceBlock
$lakeArchitectureBlock
$tierChartBlock

Retention per table, including the retention that rolls into the lake and whether each such table is still being fed, is in [89-retention.md](89-retention.md).
$lakeTablesBlock
$lakeUsageBlock
$assetDataBlock

## Cost split: Analytics vs Lake (last {lookback-d})

| Plan | Ingest (GB) | Estimated monthly cost |
|---|---:|---:|
| Analytics | $(Format-BlueprintGb $analyticsGb) | $(Format-BlueprintMoney $analyticsCost $cost.Currency) |
| DataLake | $(Format-BlueprintGb $lakeGb) | $(Format-BlueprintMoney $lakeCost $cost.Currency) |

## Lake billing meters

When Lake is enrolled, five new meters can appear on the bill. The table below documents what each one charges for so a billing surprise can be traced to its source.

$(Format-BlueprintTable -Items $lakeBillingMeters -Columns 'Meter','ChargedPer','AppliesTo')

> Notes
>
> - **Mirrored data is free**: mirroring an Analytics-plan table to the Lake at the same retention incurs no Lake-storage charge. Extended Lake-only retention beyond the Analytics period is where Lake-storage starts billing.
> - **Compression is 6:1**: Lake-storage bills the compressed footprint. 600 GB of raw logs is billed as 100 GB of compressed Lake storage.
> - **Long-term retention, search-jobs, and auxiliary-logs meters fold into the Lake meters** once the workspace is onboarded (see the onboarding doc for the exact mapping).

## Lake-derived capabilities

Features that unlock when the tenant is onboarded to the Lake. Each surface points at where it lives in the portal plus which Lake meter it bills against.

$(Format-BlueprintTable -Items $lakeCapabilities -Columns 'Capability','Surface','Billing')

## Migration candidates

Top Analytics-plan tables (0.5 GB or more per 30 days) that are typical Lake-tier candidates: high ingest volume, low real-time-query frequency. Defender XDR advanced hunting surfaces (Device*, Email*, Url*) and raw EDR/firewall telemetry are the usual wins. Confirm a table's analytics-rule references first before migrating: a rule whose query joins against the candidate table will start failing if the table is moved without re-pointing the query.

$(if ($dlCandidateRows.Count -gt 0) { Format-BlueprintTable -Items $dlCandidateRows -Columns 'Table','Gb30d','MonthlyCost','Recommendation' } else { '_No Analytics-plan tables above the 0.5 GB per 30 days threshold, so Lake migration is not currently cost-justified on this workspace._' })

## When to enroll

- **Sustained ingest above 500 GB a month** of verbose / low-query telemetry (Defender XDR raw events, firewall syslog, EDR process telemetry).
- **Long-tail investigations need affordable retention**: Lake supports up to 12 years at storage rates with 6:1 compression, vs Analytics' high per-GB interactive retention rate.
- **Already onboarded to the Defender unified SecOps portal**: Lake is the implicit storage tier for unified-portal workflows (graph, MCP, notebooks).
- **Compliance retention requirements**: regulatory retention obligations (SOX, GDPR audit, PCI-DSS) often demand multi-year retention that's prohibitively expensive on Analytics-tier storage.

## When to stay on the legacy model

- **Ingest below about 100 GB a month**: Analytics-plan per-GB rate is competitive at low volumes and avoids the operational complexity of plan-routing.
- **Every table queries in near-real-time**: the Lake's higher query latency makes it a poor fit for detection-rule-heavy workloads.
- **CMK encryption is required**: Sentinel Data Lake does **not** support Customer-Managed Keys; workspaces using CMK cannot use Lake experiences.
- **Compliance / contract requires PerGB2018 billing**: some enterprise agreements lock to legacy meters that don't include the Lake meter set.

[Microsoft Sentinel Data Lake overview (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-overview)
[Onboard to Microsoft Sentinel data lake (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-onboarding)
[Data lake tier billing (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/billing#data-lake-tier)
[Manage data tiers and retention (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/manage-data-overview)
[KQL and the Microsoft Sentinel data lake (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/kql-overview)
[KQL jobs (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/kql-jobs)
[Jupyter notebooks in the Sentinel data lake (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/notebooks-overview)
[Sentinel graph (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-graph-overview)
"@
    Write-BlueprintSection '88-sentinel-data-lake.md' $lakeBody
}
