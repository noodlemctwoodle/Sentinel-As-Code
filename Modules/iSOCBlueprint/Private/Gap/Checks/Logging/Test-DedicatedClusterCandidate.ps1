#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-12: Dedicated cluster candidate

.DESCRIPTION
    Gap check for rule SAC-LOG-12 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-DedicatedClusterCandidate.ps1
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
# SAC-LOG-12, Dedicated cluster candidate
# ------------------------------------------------------------
function Test-DedicatedClusterCandidate {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if ($Inventory.DedicatedCluster) { return $null }
    $totalGb30d = 0.0
    foreach ($t in @($Inventory.TablesWithData)) {
        $totalGb30d += [double](Get-PropOrDefault $t 'BillableLast30d' 0)
    }
    $dailyAvg = $totalGb30d / (Get-GapWindow $Inventory).Days
    if ($dailyAvg -gt 500.0) {
        return New-Finding -Evidence "Average ingest about $(Format-BlueprintGb $dailyAvg) GB a day with no dedicated cluster, cluster offers cluster-level CR pricing, CMK, and AZ." -Detail @{ DailyAvgGb = $dailyAvg }
    }
    return $null
}
