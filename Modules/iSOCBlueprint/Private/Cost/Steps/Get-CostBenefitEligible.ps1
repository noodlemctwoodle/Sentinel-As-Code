#Requires -Version 7.6

<#
.SYNOPSIS
    List what each data grant could cover, at list price and not deducted.

.DESCRIPTION
    A step of the cost estimate. Steps run in order and pass their results to
    later ones through the estimate context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Cost/Steps/Get-CostBenefitEligible.ps1
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

function Get-CostBenefitEligible {
    <#
    .SYNOPSIS
        List what each data grant could cover, at list price and not deducted.

    .PARAMETER Context
        The estimate context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the estimate context.
    $benefitGroups = $Context.benefitGroups
    $perTable = $Context.perTable

    # The data grants: what each could cover, at list price, not deducted.
    $benefitEligible = @(foreach ($g in $benefitGroups) {
            $label = if ($g.PSObject.Properties.Name -contains 'short' -and $g.short) { [string]$g.short } else { [string]$g.name }
            $covered = @($perTable | Where-Object { $_.Benefit -eq $label })
            if ($covered.Count -eq 0) { continue }
            [pscustomobject]@{
                Benefit     = [string]$g.name
                Allowance   = $(if ($g.PSObject.Properties.Name -contains 'allowance') { [string]$g.allowance } else { '' })
                Tables      = (@($covered | Sort-Object -Property Gb30d -Descending | ForEach-Object { $_.Table }) -join ', ')
                Gb30d       = [math]::Round((Get-CostPropertySum $covered 'Gb30d'), 2)
                MonthlyCost = [math]::Round((Get-CostPropertySum $covered 'MonthlyCost'), 2)
                Learn       = $(if ($g.PSObject.Properties.Name -contains 'learn') { [string]$g.learn } else { '' })
            }
        })

    # Left for the steps after this one.
    $Context.benefitEligible = $benefitEligible
}
