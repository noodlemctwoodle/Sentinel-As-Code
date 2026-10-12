#Requires -Version 7.2

<#
.SYNOPSIS
    Classify a workspace's operational tables by Sentinel data lake tier and
    list the tables that keep data in the lake beyond their analytics
    retention.

.DESCRIPTION
    The Markdown renderer (88-sentinel-data-lake.md) and the SharePoint
    dashboard both show the tier distribution and the extended-retention
    tables. One function feeds both so the page and the dashboard never
    disagree. The categories follow the lake's behaviour: on an enrolled
    tenant every Analytics-plan table is mirrored to the lake at the same
    retention (Analytics + Lake mirror); a table whose total retention
    exceeds its analytics retention also stores in the lake beyond it
    (Analytics + Lake extended); a table on the DataLake plan bypasses the
    analytics tier (Lake only); without enrolment every table is
    Analytics only. Basic and Auxiliary plan tables are counted on the
    side, since they are neither analytics-tier nor lake-tier.

.NOTES
    File:         Tools/Documenter/Private/Get-TableTierProfile.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-12
    Version:      0.1.0
    Last Updated: 2026-10-12
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-TableTier {
    <#
    .SYNOPSIS
        Classify one workspace table by data lake tier.

    .PARAMETER Table
        A workspace table resource (properties.plan, properties.retentionInDays,
        properties.totalRetentionInDays).

    .PARAMETER LakeEnrolled
        Whether the tenant is enrolled in the Sentinel data lake.

    .OUTPUTS
        [string] One of AnalyticsOnly, MirroredOnly, MirroredExtended, LakeOnly.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)] [object] $Table,
        [Parameter(Mandatory = $false)] [bool] $LakeEnrolled = $false
    )
    $props = if ($Table.PSObject.Properties['properties']) { $Table.properties } else { $null }
    $plan = if ($props -and $props.PSObject.Properties['plan']) { [string]$props.plan } else { '' }
    $r = 0; $tr = 0
    if ($props -and $props.PSObject.Properties['retentionInDays'] -and $props.retentionInDays) { $r = [int]$props.retentionInDays }
    if ($props -and $props.PSObject.Properties['totalRetentionInDays'] -and $props.totalRetentionInDays) { $tr = [int]$props.totalRetentionInDays }
    if ($plan -eq 'DataLake') { return 'LakeOnly' }
    if ($LakeEnrolled -and $tr -gt $r) { return 'MirroredExtended' }
    if ($LakeEnrolled) { return 'MirroredOnly' }
    return 'AnalyticsOnly'
}

function Get-TableTierProfile {
    <#
    .SYNOPSIS
        Return tier counts and extended-retention rows for a set of tables.

    .PARAMETER Tables
        Workspace table resources (name, properties.plan,
        properties.retentionInDays, properties.totalRetentionInDays), already
        filtered to the operational set the caller wants counted.

    .PARAMETER LakeEnrolled
        Whether the tenant is enrolled in the Sentinel data lake. Without it
        every table is Analytics only, whatever its retention.

    .OUTPUTS
        [pscustomobject] Tiers (ordered: AnalyticsOnly, MirroredOnly,
        MirroredExtended, LakeOnly, Basic, Auxiliary), RetentionRows
        (Table, Plan, AnalyticsDays, LakeOnlyDays, TotalDays for tables that
        store in the lake beyond analytics retention or are Lake only),
        LakeOnlyTables (names).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] [object[]] $Tables,
        [Parameter(Mandatory = $false)] [bool] $LakeEnrolled = $false
    )

    $tiers = [ordered]@{ AnalyticsOnly = 0; MirroredOnly = 0; MirroredExtended = 0; LakeOnly = 0; Basic = 0; Auxiliary = 0 }
    $rows = [System.Collections.Generic.List[object]]::new()
    $lakeOnly = [System.Collections.Generic.List[string]]::new()

    foreach ($t in @($Tables)) {
        if ($null -eq $t) { continue }
        $props = if ($t.PSObject.Properties['properties']) { $t.properties } else { $null }
        $plan = if ($props -and $props.PSObject.Properties['plan']) { [string]$props.plan } else { '' }
        $r = 0; $tr = 0
        if ($props -and $props.PSObject.Properties['retentionInDays'] -and $props.retentionInDays) { $r = [int]$props.retentionInDays }
        if ($props -and $props.PSObject.Properties['totalRetentionInDays'] -and $props.totalRetentionInDays) { $tr = [int]$props.totalRetentionInDays }
        $lakeOnlyDays = if ($tr -gt $r) { $tr - $r } else { 0 }

        if ($plan -eq 'Basic') { $tiers.Basic++ } elseif ($plan -eq 'Auxiliary') { $tiers.Auxiliary++ }
        $category = Get-TableTier -Table $t -LakeEnrolled $LakeEnrolled
        $tiers[$category]++

        if ($plan -eq 'DataLake') { $lakeOnly.Add([string]$t.name) }
        if ($lakeOnlyDays -gt 0 -or $plan -eq 'DataLake') {
            $rows.Add([pscustomobject]@{
                Table         = [string]$t.name
                Plan          = $plan
                AnalyticsDays = $r
                LakeOnlyDays  = $lakeOnlyDays
                TotalDays     = $tr
            })
        }
    }

    return [pscustomobject]@{
        Tiers          = $tiers
        RetentionRows  = @($rows)
        LakeOnlyTables = @($lakeOnly)
    }
}
