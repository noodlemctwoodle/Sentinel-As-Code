#Requires -Version 7.6

<#
.SYNOPSIS
    Read the captured JSON the estimate is built from and the window it covers.

.DESCRIPTION
    A step of the cost estimate. Steps run in order and pass their results to
    later ones through the estimate context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Cost/Steps/Read-CostInputs.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, cost estimate
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Read-CostInputs {
    <#
    .SYNOPSIS
        Read the captured JSON the estimate is built from and the window it covers.

    .PARAMETER Context
        The estimate context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the estimate context.
    $InputRoot = $Context.InputRoot
    $ResourcesRoot = $Context.ResourcesRoot

    $tables       = @(Read-CostJson (Join-Path $InputRoot 'tables-with-data.json'))
    $schemas      = @(Read-CostJson (Join-Path $InputRoot 'workspace-tables.json'))
    $workspace    = Read-CostJson (Join-Path $InputRoot 'workspace.json')
    # How Sentinel is billed: the SecurityInsights solution's properties.sku
    # (Unified is simplified pricing, anything else classic).
    $billedModel  = $null
    foreach ($sol in @(Read-CostJson (Join-Path $InputRoot 'solutions-installed.json'))) {
        if (-not $sol -or -not $sol.PSObject.Properties['plan'] -or -not $sol.plan -or [string]$sol.plan.product -notmatch 'SecurityInsights$') { continue }
        $solProps = if ($sol.PSObject.Properties['properties']) { $sol.properties } else { $null }
        $solSku = if ($solProps -and $solProps.PSObject.Properties['sku'] -and $solProps.sku -and $solProps.sku.PSObject.Properties['name']) {
            [string]$solProps.sku.name
        } else { '' }
        if ($solSku) { $billedModel = if ($solSku -eq 'Unified') { 'Simplified' } else { 'Classic' } }
    }
    $pricesBlob   = Read-CostJson (Join-Path $InputRoot 'retail-prices.json')
    $benefitJson  = Read-CostJson (Join-Path $ResourcesRoot 'sentinel-benefit-tables.json')
    # The days of Usage the tables carry: the run's lookback (run-context.json),
    # 30 for a run collected before the setting existed. A month is projected
    # from it as 30 days at the window's rate.
    $runContext   = Read-CostJson (Join-Path $InputRoot 'run-context.json')
    $windowDays   = 30
    if ($runContext -and $runContext.PSObject.Properties['LookbackDays'] -and [int]$runContext.LookbackDays -ge 1) {
        $windowDays = [int]$runContext.LookbackDays
    }
    $toMonth      = 30.0 / $windowDays

    # Left for the steps after this one.
    $Context.tables = $tables
    $Context.schemas = $schemas
    $Context.workspace = $workspace
    $Context.billedModel = $billedModel
    $Context.pricesBlob = $pricesBlob
    $Context.benefitJson = $benefitJson
    $Context.windowDays = $windowDays
    $Context.toMonth = $toMonth
}
