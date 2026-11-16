#Requires -Version 7.6

<#
.SYNOPSIS
    Set up the caveats and the plan totals, and answer early when there is no table or usage data.

.DESCRIPTION
    A step of the cost estimate. Steps run in order and pass their results to
    later ones through the estimate context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Cost/Steps/Initialize-CostResult.ps1
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

function Initialize-CostResult {
    <#
    .SYNOPSIS
        Set up the caveats and the plan totals, and answer early when there is no table or usage data.

    .PARAMETER Context
        The estimate context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the estimate context.
    $schemas = $Context.schemas
    $tables = $Context.tables

    $caveats = @(
        'Query-time billing for Basic/Auxiliary plans not included.',
        'Search-job and restored-log storage not included.',
        'Data-export egress and cross-region transfer not included.',
        'Retention beyond the free 90 days and data lake storage not included.',
        'Defender XDR-side meters not included.',
        'Data grants (Microsoft 365 E5 and Defender for Servers Plan 2) are not deducted: they depend on licence and server counts the Blueprint does not read. The eligible volume is listed as the most they could save.'
    )

    $byPlan = @{
        Analytics = @{ Gb30d = 0.0; MonthlyCost = 0.0 }
        Basic     = @{ Gb30d = 0.0; MonthlyCost = 0.0 }
        Auxiliary = @{ Gb30d = 0.0; MonthlyCost = 0.0 }
        DataLake  = @{ Gb30d = 0.0; MonthlyCost = 0.0 }
    }

    if (-not $tables -or -not $schemas) {
        $Context.result = [pscustomobject]@{
            MonthlyTotal              = 0.0
            Currency                  = 'unknown'
            Region                    = $null
            AsOfUtc                   = $null
            ByPlan                    = $byPlan
            Top10TablesByCost         = @()
            CommitmentTierWhatIf      = @()
            DedicatedClusterCandidate = $false
            Caveats                   = $caveats + 'No table or usage data available, workspace may be empty or KQL Usage query failed.'
            MethodologyVersion        = '1.0.0'
        }
        $Context.stop = $true
        return
    }

    # Left for the steps after this one.
    $Context.caveats = $caveats
    $Context.byPlan = $byPlan
}
