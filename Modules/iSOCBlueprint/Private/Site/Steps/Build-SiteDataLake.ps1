#Requires -Version 7.6

<#
.SYNOPSIS
    Build the data lake model and the table tier profile.

.DESCRIPTION
    A step of the SharePoint site build. Steps run in order and pass their results
    to later ones through the build context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Steps/Build-SiteDataLake.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Build-SiteDataLake {
    <#
    .SYNOPSIS
        Build the data lake model and the table tier profile.

    .PARAMETER Context
        The build context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the build context.
    $costModel = $Context.costModel
    $dataLake = $Context.dataLake
    $lakeEnrolled = $Context.lakeEnrolled
    $lakePlanTables = $Context.lakePlanTables
    $tablesData = $Context.tablesData
    $unifiedBilling = $Context.unifiedBilling
    $wsTablesRaw = $Context.wsTablesRaw

    # Sentinel data lake: enrolment signals, tier distribution and the tables
    # that keep data in the lake beyond analytics retention, counted over the
    # operational tables (data in 90 days, plus custom logs) exactly as section
    # 88 counts them, through the shared helper.
    $populatedNames = @{}
    foreach ($t in $tablesData) { if ($t -and $t.PSObject.Properties['DataType'] -and $t.DataType -and (ConvertTo-BuildNumber $t.BillableLast90d) -gt 0) { $populatedNames[[string]$t.DataType] = $true } }
    $operationalTables = @($wsTablesRaw | Where-Object {
        $_ -and $_.PSObject.Properties['name'] -and $_.name -and $_.PSObject.Properties['properties'] -and $_.properties -and (
            ($_.properties.PSObject.Properties['schema'] -and $_.properties.schema -and $_.properties.schema.PSObject.Properties['tableType'] -and $_.properties.schema.tableType -eq 'CustomLog') -or
            $populatedNames.ContainsKey([string]$_.name))
    })
    $tierProfile = Get-TableTierProfile -Tables $operationalTables -LakeEnrolled $lakeEnrolled
    $lakeResource = @($dataLake | Where-Object { $_ }) | Select-Object -First 1
    $lakeCostRow = if ($costModel) { $costModel.byPlan | Where-Object { $_.plan -eq 'DataLake' } | Select-Object -First 1 } else { $null }
    $analyticsCostRow = if ($costModel) { $costModel.byPlan | Where-Object { $_.plan -eq 'Analytics' } | Select-Object -First 1 } else { $null }
    $dataLakeModel = [ordered]@{
        enrolled          = $lakeEnrolled
        signals           = [ordered]@{ resource = ($dataLake.Count -gt 0); unifiedBilling = $unifiedBilling; lakeOnlyTables = $lakePlanTables }
        provisioningState = if ($lakeResource -and $lakeResource.properties -and $lakeResource.properties.PSObject.Properties['provisioningState']) { [string]$lakeResource.properties.provisioningState } else { '' }
        region            = if ($lakeResource -and $lakeResource.PSObject.Properties['location']) { [string]$lakeResource.location } else { '' }
        operationalTables = $operationalTables.Count
        tiers             = $tierProfile.Tiers
        extendedCount     = @($tierProfile.RetentionRows).Count
        extendedTables    = @($tierProfile.RetentionRows | Sort-Object { $_.LakeOnlyDays } -Descending | ForEach-Object {
            [ordered]@{ table = $_.Table; plan = $_.Plan; analyticsDays = $_.AnalyticsDays; lakeOnlyDays = $_.LakeOnlyDays; totalDays = $_.TotalDays }
        })
        cost              = [ordered]@{
            currency     = if ($costModel) { $costModel.currency } else { '' }
            analyticsGb  = if ($analyticsCostRow) { $analyticsCostRow.gb30d } else { 0 }
            analyticsCost = if ($analyticsCostRow) { $analyticsCostRow.cost } else { 0 }
            lakeGb       = if ($lakeCostRow) { $lakeCostRow.gb30d } else { 0 }
            lakeCost     = if ($lakeCostRow) { $lakeCostRow.cost } else { 0 }
        }
    }

    # Left in the build context for later steps.
    $Context.dataLakeModel = $dataLakeModel
}
