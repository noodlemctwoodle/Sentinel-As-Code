#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 88-sentinel-data-lake.md (part 1 of 3).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/SentinelDataLake/Write-BlueprintSentinelDataLakeSection.ps1
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
function Write-BlueprintSentinelDataLakeSection {
    <#
    .SYNOPSIS
        Build the figures for and write 88-sentinel-data-lake.md (part 1 of 3).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $cost = $Context.cost
    $hasDataLake = $Context.hasDataLake
    $n = $Context.n
    $operationalTables = $Context.operationalTables
    $populatedTableNames = $Context.populatedTableNames
    $s = $Context.s
    $sentinelDataLake = $Context.sentinelDataLake
    $unifiedBilling = $Context.unifiedBilling
    $workspaceTables = $Context.workspaceTables

    # ---------------------------------------------------------------------------
    # Section 88 — Microsoft Sentinel Data Lake
    # ---------------------------------------------------------------------------
    # Lake-tier tables surfaced from $workspaceTables (those on plan='DataLake').
    # Migration candidates surfaced from $cost.AllTablesByCost — high-volume
    # tables on the Analytics plan are typical Lake-migration targets for
    # cost optimisation. The enrollment signals were computed in section 83's
    # block ($hasDataLake / $unifiedBilling / $sentinelDataLake / $plansInUse)
    # so this block consumes them rather than recomputing.

    $dlTables = @($workspaceTables | Where-Object { $_.properties.plan -eq 'DataLake' })
    $dlTableRows = $dlTables | ForEach-Object {
        [pscustomobject]@{
            Table            = $_.name
            RetentionDays    = $_.properties.retentionInDays
            TotalRetention   = $_.properties.totalRetentionInDays
        }
    }

    # Tier-distribution stats. When Lake is enrolled every Analytics-plan
    # table is auto-mirrored to the Lake at the same retention. A table
    # that has totalRetentionInDays > retentionInDays is also storing
    # additional time in the Lake beyond the Analytics period. Tables on
    # plan = 'DataLake' route exclusively to the Lake (no Analytics tier).
    # Catalogue-only tables (zero ingest in the workspace) are excluded
    # from the tier-distribution chart because they don't contribute to
    # the Lake state.
    # Shared with the SharePoint build (Private/Get-TableTierProfile.ps1) so
    # the page's pie and the dashboard's lake panel count the same tables the
    # same way.
    $tierProfile   = Get-TableTierProfile -Tables $operationalTables -LakeEnrolled $hasDataLake
    $tierStats     = $tierProfile.Tiers
    $retentionRows = $tierProfile.RetentionRows

    # Asset-data system tables that Sentinel Data Lake auto-ingests on
    # tenant onboarding. Detecting these by name confirms the Lake's
    # Microsoft Entra / Microsoft 365 / Azure Resource Graph asset
    # pipelines are actually populating the workspace.
    $assetTableNames = @(
        @{ Pattern = '^IdentityInfo$';                 Family = 'Microsoft Entra (identity)' },
        @{ Pattern = '^EntityGraph';                   Family = 'Microsoft Sentinel graph (entities)' },
        @{ Pattern = '^Asset';                         Family = 'Azure Resource Graph (assets)' },
        @{ Pattern = '^Office(SharePoint|Exchange|Teams)';  Family = 'Microsoft 365 (activity)' },
        @{ Pattern = '^Behavior(Analytics)?$';         Family = 'Microsoft Sentinel UEBA (asset enrichment)' }
    )
    $assetDataRows = New-Object System.Collections.Generic.List[object]
    foreach ($t in $workspaceTables) {
        foreach ($m in $assetTableNames) {
            if ($t.name -match $m.Pattern) {
                $hasData = $populatedTableNames.ContainsKey($t.name)
                $assetDataRows.Add([pscustomobject]@{
                    Table       = $t.name
                    Family      = $m.Family
                    IngestState = if ($hasData) { 'Receiving data' } else { 'Defined, no data' }
                    Retention   = $t.properties.retentionInDays
                })
                break
            }
        }
    }

    # Lake billing meters reference. Static per Microsoft Sentinel
    # pricing docs — surfaces all five Lake-specific cost surfaces so
    # reviewers know what to expect on the bill when Lake is in use.
    $lakeBillingMeters = @(
        [pscustomobject]@{ Meter = 'Data lake ingestion';      ChargedPer = 'GB';            AppliesTo = 'Data ingested into tables with retention set to Lake-only. Mirrored-to-Lake ingest is not charged.' }
        [pscustomobject]@{ Meter = 'Data processing';          ChargedPer = 'GB';            AppliesTo = 'Transformations (redaction, splitting, filtering, normalization) on Lake-only ingest. Not charged for mirrored ingest.' }
        [pscustomobject]@{ Meter = 'Data lake storage';        ChargedPer = 'GB · month';    AppliesTo = 'Data remaining in Lake AFTER the analytics-tier retention period ends. Compression 6:1 applied before billing.' }
        [pscustomobject]@{ Meter = 'Data lake query';          ChargedPer = 'GB scanned';    AppliesTo = 'KQL queries and KQL jobs over Lake-tier data. Charged per uncompressed GB scanned.' }
        [pscustomobject]@{ Meter = 'Advanced data insights';   ChargedPer = 'compute hour';  AppliesTo = 'Jupyter notebook sessions, scheduled notebook jobs, custom graph build/query. Per vCore-hour (pools of 12, 32, or 80 vCores).' }
    )

    # Lake-derived capabilities — features that unlock automatically when
    # the tenant onboards to Lake. Helps the reader connect "Lake is
    # enrolled" to the operational surfaces they'd see in Defender portal.
    $lakeCapabilities = @(
        [pscustomobject]@{ Capability = 'KQL exploration over Lake';          Surface = 'Defender portal · Investigate · KQL editor';   Billing = 'Data lake query (GB scanned)' }
        [pscustomobject]@{ Capability = 'KQL jobs (promote Lake → Analytics)'; Surface = 'Defender portal · Microsoft Sentinel · Jobs'; Billing = 'Data lake query (job execution)' }
        [pscustomobject]@{ Capability = 'Jupyter notebooks';                   Surface = 'Defender portal · Microsoft Sentinel · Notebooks · VS Code extension'; Billing = 'Advanced data insights (compute hour)' }
        [pscustomobject]@{ Capability = 'Microsoft Sentinel graph (embedded)'; Surface = 'Defender portal hunting graph · Blast radius'; Billing = 'No additional charge for embedded graphs' }
        [pscustomobject]@{ Capability = 'Custom graphs';                       Surface = 'Notebooks · Graph Query APIs · MCP graph tools'; Billing = 'Advanced data insights (compute hour, graph build/query)' }
        [pscustomobject]@{ Capability = 'MCP server (data exploration)';       Surface = 'Sentinel MCP server (AI agents)';              Billing = 'No charge for the server; tools invoke Lake-query meter' }
        [pscustomobject]@{ Capability = 'MCP entity analyzer';                 Surface = 'Sentinel MCP server';                           Billing = 'Security Compute Units (SCU) + Lake-query meter' }
        [pscustomobject]@{ Capability = 'Auto-ingested asset data';            Surface = 'System tables (Entra, M365, Azure Resource Graph)'; Billing = 'Ingestion + storage charged like any Lake table' }
        [pscustomobject]@{ Capability = '12-year affordable retention';         Surface = 'Manage data tiers in Defender portal';          Billing = 'Lake storage (per GB-month, 6:1 compression)' }
    )

    # Top-by-Lake-only-retention chart inputs (top 10 tables paying for
    # extended Lake retention beyond Analytics). xychart-beta-friendly
    # axis labels truncated to 14 chars.
    $topRetention = @($retentionRows | Sort-Object LakeOnlyDays -Descending | Select-Object -First 10)
    $retAxis  = ($topRetention | ForEach-Object {
        $n = $_.Table
        $s = if ($n.Length -gt 14) { $n.Substring(0,14) } else { $n }
        "`"$s`""
    }) -join ', '
    $retLakeBars = ($topRetention | ForEach-Object { $_.LakeOnlyDays }) -join ', '
    $retAnaBars  = ($topRetention | ForEach-Object { $_.AnalyticsDays }) -join ', '
    $retYmax = 1
    foreach ($r in $topRetention) { $sum = $r.AnalyticsDays + $r.LakeOnlyDays; if ($sum -gt $retYmax) { $retYmax = $sum } }

    # Lake-side ingest + cost split from $cost.ByPlan. Defensive lookups because
    # older cost captures may not include DataLake.
    $lakeGb = 0.0
    $lakeCost = 0.0
    $analyticsGb = 0.0
    $analyticsCost = 0.0
    if ($cost -and $cost.ByPlan) {
        if ($cost.ByPlan.PSObject.Properties.Name -contains 'DataLake') {
            $lakeGb   = [double]$cost.ByPlan.DataLake.Gb30d
            $lakeCost = [double]$cost.ByPlan.DataLake.MonthlyCost
        }
        if ($cost.ByPlan.PSObject.Properties.Name -contains 'Analytics') {
            $analyticsGb   = [double]$cost.ByPlan.Analytics.Gb30d
            $analyticsCost = [double]$cost.ByPlan.Analytics.MonthlyCost
        }
    }

    # Migration candidates: Analytics-plan tables with ≥0.5 GB/30d are typical
    # Lake-tier candidates, particularly verbose Defender XDR advanced hunting
    # tables (Device*, Email*) and verbose security logs that don't drive
    # real-time detection. Every qualifying table is listed, costliest first.
    $dlCandidateRows = @()
    if ($cost -and $cost.PSObject.Properties.Name -contains 'AllTablesByCost' -and $cost.AllTablesByCost) {
        $dlCandidateRows = @($cost.AllTablesByCost |
            Where-Object { $_.Plan -eq 'Analytics' -and ([double]$_.Gb30d * 30.0 / (Get-BlueprintWindow).Days) -ge 0.5 } |
            ForEach-Object {
                [pscustomobject]@{
                    Table         = $_.Table
                    Gb30d         = $_.Gb30d
                    MonthlyCost   = (Format-BlueprintMoney $_.MonthlyCost $cost.Currency)
                    Recommendation = 'Consider DataLake plan if rule queries are infrequent'
                }
            })
    }

    # Headline narrative — one of four states based on the captured signals.
    $lakeHeadline = if ($hasDataLake -and $dlTables.Count -gt 0) {
        "**Sentinel Data Lake is enrolled and active.** $(Format-BlueprintPlural $dlTables.Count 'table') $(if ($dlTables.Count -eq 1) { 'routes' } else { 'route' }) to the Lake at the DataLake-rate ingestion meter (~$(Format-BlueprintGb $lakeGb) GB in {lookback-d}, est. $(Format-BlueprintMoney $lakeCost $cost.Currency) / month). Analytics-plan tables continue to bill at the higher Sentinel-rate meter."
    } elseif ($hasDataLake -and $dlTables.Count -eq 0) {
        "**Sentinel Data Lake is enrolled on this workspace** (``features.unifiedSentinelBillingOnly = true``), but no tables currently route to the Lake. All ingest is on the Analytics plan billed at the full Sentinel-rate meter. See *Migration candidates* below for verbose tables that could move to the Lake to reduce monthly cost, since the Lake-rate per-GB ingestion meter is typically a fraction of the Sentinel-rate."
    } elseif (-not $hasDataLake -and $analyticsGb -gt 30) {
        "**Sentinel Data Lake is not enrolled.** This workspace ingests $(Format-BlueprintGb $analyticsGb) GB in {lookback-d} on the Analytics plan at the full Sentinel-rate meter. For high-volume workspaces, onboarding to the unified Sentinel/Defender billing model unlocks the DataLake plan, which routes verbose, low-query tables (Defender XDR advanced hunting, raw firewall, EDR telemetry) to a cheaper ingestion tier with longer affordable retention."
    } else {
        "**Sentinel Data Lake is not enrolled.** This workspace is on the legacy per-GB billing model with no Lake-tier ingest. Lake becomes cost-relevant once steady-state ingest exceeds a few hundred GB a month, particularly for verbose Defender XDR tables; below that the per-GB Analytics rate is competitive."
    }

    # Enrollment-signal table — primary signal is the
    # Microsoft.SentinelPlatformServices resource; the workspace billing
    # flag and table-plan signals are supporting checks.
    $lakeResource = @($sentinelDataLake) | Select-Object -First 1
    $lakeSignals = @(
        [pscustomobject]@{
            Signal      = 'Microsoft.SentinelPlatformServices/sentinelPlatformServices'
            Value       = if ($lakeResource) { "$($lakeResource.name) ($(Get-BlueprintRegionName ([string]$lakeResource.location)))" } else { '(not found)' }
            Interpretation = if ($lakeResource) { "Lake provisioned at tenant scope, region '$(Get-BlueprintRegionName ([string]$lakeResource.location))', billing subscription '$($lakeResource.subscriptionId)' / RG '$($lakeResource.resourceGroup)'" } else { 'No Sentinel Data Lake resource found in the visible subscriptions, so the tenant is not onboarded to Lake' }
        },
        [pscustomobject]@{
            Signal      = 'workspace.properties.features.unifiedSentinelBillingOnly'
            Value       = if ($unifiedBilling) { 'true' } else { 'false / absent' }
            Interpretation = if ($unifiedBilling) { 'Workspace on unified Sentinel/Defender billing, eligible for Lake' } else { 'Workspace on legacy per-GB billing, not on the unified model' }
        },
        [pscustomobject]@{
            Signal      = "Tables on plan='DataLake'"
            Value       = (Format-BlueprintPlural $dlTables.Count 'table')
            Interpretation = if ($dlTables.Count -gt 0) { 'Data actively routed to Lake-only tier' } else { 'No tables route to Lake-only tier (mirrored data still flows when Lake is enrolled)' }
        }
    )

    # Lake resource detail block, only rendered when the platform-services
    # resource exists. Surfaces the audit trail (createdBy/At) so reviewers
    # can answer "when was this onboarded and by whom" from the doc.
    $lakeResourceBlock = if ($lakeResource) {
        $createdAt = if ($lakeResource.systemData.createdAt) { Format-BlueprintDate $lakeResource.systemData.createdAt -Time } else { '_(unknown)_' }
        $modifiedAt = if ($lakeResource.systemData.lastModifiedAt) { Format-BlueprintDate $lakeResource.systemData.lastModifiedAt -Time } else { '_(unknown)_' }
        @"

## Lake resource detail

| Property | Value |
|---|---|
| Resource ID | ``$($lakeResource.id)`` |
| Resource name | ``$($lakeResource.name)`` |
| Region | $(Format-WorkspaceRegion $lakeResource.location -WithCode) |
| Subscription | ``$($lakeResource.subscriptionId)`` |
| Resource group | ``$($lakeResource.resourceGroup)`` |
| Provisioning state | ``$($lakeResource.properties.provisioningState)`` |
| System-assigned MI principal | ``$($lakeResource.identity.principalId)`` |
| Onboarded by | ``$($lakeResource.systemData.createdBy)`` |
| Onboarded at | $createdAt |
| Last modified | $modifiedAt |

The Sentinel Data Lake is a tenant-wide capability but it's provisioned as a single resource pinned to one subscription / resource group / region. Workspaces in **other regions** still mirror to the Lake. See [Onboard to Microsoft Sentinel data lake (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-onboarding) for the cross-region behaviour.
"@
    } else { '' }

    # Tier-distribution pie chart inputs.
    $tierPieRows = @()
    if ($tierStats.AnalyticsOnly    -gt 0) { $tierPieRows += "    `"Analytics only`" : $($tierStats.AnalyticsOnly)" }

    # Left in the render context for later sections.
    $Context.analyticsCost = $analyticsCost
    $Context.analyticsGb = $analyticsGb
    $Context.assetDataRows = $assetDataRows
    $Context.dlCandidateRows = $dlCandidateRows
    $Context.dlTableRows = $dlTableRows
    $Context.lakeBillingMeters = $lakeBillingMeters
    $Context.lakeCapabilities = $lakeCapabilities
    $Context.lakeCost = $lakeCost
    $Context.lakeGb = $lakeGb
    $Context.lakeHeadline = $lakeHeadline
    $Context.lakeResourceBlock = $lakeResourceBlock
    $Context.lakeSignals = $lakeSignals
    $Context.m = $m
    $Context.retAxis = $retAxis
    $Context.retentionRows = $retentionRows
    $Context.retLakeBars = $retLakeBars
    $Context.retYmax = $retYmax
    $Context.tierPieRows = $tierPieRows
    $Context.tierStats = $tierStats
    $Context.topRetention = $topRetention
}
