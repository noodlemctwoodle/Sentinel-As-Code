#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-MON-04: MITRE tactic with zero enabled rules

.DESCRIPTION
    Gap check for rule SAC-MON-04 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Monitoring/Test-MitreTacticCoverage.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# ------------------------------------------------------------
# SAC-MON-04, MITRE tactic with zero enabled rules
# ------------------------------------------------------------
function Test-MitreTacticCoverage {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.MitreTactics) { return $null }
    $coveredTactics = @{}
    foreach ($rule in @($Inventory.AlertRules)) {
        $enabled = Get-PropOrDefault $rule 'properties.enabled' $false
        if (-not $enabled) { continue }
        $tactics = Get-PropOrDefault $rule 'properties.tactics' @()
        foreach ($t in @($tactics)) { $coveredTactics[$t] = $true }
    }
    $uncovered = @($Inventory.MitreTactics | Where-Object { -not $coveredTactics.ContainsKey($_.sentinelShortName) })
    if ($uncovered.Count -gt 0) {
        $names = ($uncovered | Select-Object -ExpandProperty name) -join ', '
        return New-Finding -Evidence "$(Select-GapWording $uncovered.Count 'MITRE tactic' 'MITRE tactics') with zero enabled rules: $names." -Detail @{ UncoveredTactics = $uncovered }
    }
    return $null
}
