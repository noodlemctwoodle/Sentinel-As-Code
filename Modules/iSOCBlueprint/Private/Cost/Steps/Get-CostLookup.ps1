#Requires -Version 7.6

<#
.SYNOPSIS
    Look up each table's plan, which data grant covers it and whether the workspace is onboarded to the data lake.

.DESCRIPTION
    A step of the cost estimate. Steps run in order and pass their results to
    later ones through the estimate context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Cost/Steps/Get-CostLookup.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, cost estimate
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-CostLookup {
    <#
    .SYNOPSIS
        Look up each table's plan, which data grant covers it and whether the workspace is onboarded to the data lake.

    .PARAMETER Context
        The estimate context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the estimate context.
    $benefitJson = $Context.benefitJson
    $InputRoot = $Context.InputRoot
    $schemas = $Context.schemas
    $workspace = $Context.workspace

    # Plan lookup: table name -> plan
    $planByTable = @{}
    foreach ($t in $schemas) {
        $name = $t.name
        $plan = ($t.properties.plan) -as [string]
        if ($name) { $planByTable[$name] = $plan }
    }

    # The data grants and the tables each covers: table -> grant. A table on
    # two lists goes to the first. An older file (a flat 'tables' list) reads
    # as one unnamed grant.
    $benefitOf = @{}
    $benefitGroups = @()
    if ($benefitJson) {
        if ($benefitJson.PSObject.Properties.Name -contains 'benefits' -and $benefitJson.benefits) {
            $benefitGroups = @($benefitJson.benefits)
        } elseif ($benefitJson.PSObject.Properties.Name -contains 'tables') {
            $benefitGroups = @([pscustomobject]@{ name = 'Sentinel data grant'; allowance = ''; learn = ''; tables = @($benefitJson.tables) })
        }
        foreach ($g in $benefitGroups) { foreach ($t in @($g.tables)) { if ($t -and -not $benefitOf.ContainsKey([string]$t)) { $benefitOf[[string]$t] = $g } } }
    }

    # Onboarded to the data lake: a lake resource, unified billing, or a
    # table on the lake-only plan.
    $lakeDoc = @(Read-CostJson (Join-Path $InputRoot 'sentinel-data-lake.json') | Where-Object { $_ })
    $unifiedBilling = $false
    if ($workspace -and ($workspace.PSObject.Properties.Name -contains 'properties') -and $workspace.properties -and
        ($workspace.properties.PSObject.Properties.Name -contains 'features') -and $workspace.properties.features -and
        ($workspace.properties.features.PSObject.Properties.Name -contains 'unifiedSentinelBillingOnly')) {
        $unifiedBilling = [bool]$workspace.properties.features.unifiedSentinelBillingOnly
    }
    $lakeEnrolled = ($lakeDoc.Count -gt 0) -or $unifiedBilling -or (@($planByTable.Values | Where-Object { $_ -eq 'DataLake' }).Count -gt 0)

    # Left for the steps after this one.
    $Context.planByTable = $planByTable
    $Context.benefitOf = $benefitOf
    $Context.benefitGroups = $benefitGroups
    $Context.lakeEnrolled = $lakeEnrolled
}
