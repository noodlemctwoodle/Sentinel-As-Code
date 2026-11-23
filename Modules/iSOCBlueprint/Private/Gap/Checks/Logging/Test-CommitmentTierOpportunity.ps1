#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-10: Commitment-tier opportunity

.DESCRIPTION
    Gap check for rule SAC-LOG-10 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-CommitmentTierOpportunity.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# ------------------------------------------------------------
# SAC-LOG-10, Commitment-tier opportunity
# ------------------------------------------------------------
function Test-CommitmentTierOpportunity {
    <#
    .SYNOPSIS
        Gap check SAC-LOG-10: Commitment-tier opportunity

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    $sku = Get-PropOrDefault $Inventory.Workspace 'properties.sku.name' ''
    if ($sku -ne 'PerGB2018') { return $null }

    $totalGb30d = 0.0
    foreach ($t in @($Inventory.TablesWithData)) {
        $totalGb30d += [double](Get-PropOrDefault $t 'BillableLast30d' 0)
    }
    if ($totalGb30d -le 0) { return $null }
    $dailyAvg = $totalGb30d / (Get-GapWindow $Inventory).Days

    if (-not $Inventory.CommitmentTiers) { return $null }
    $rungs = @($Inventory.CommitmentTiers.rungsGbPerDay)
    $next = $rungs | Where-Object { $_ -le $dailyAvg } | Select-Object -Last 1
    if ($next) {
        return New-Finding -Evidence "$((Get-GapWindow $Inventory).Days)-day average ingest is about $(Format-BlueprintGb $dailyAvg) GB a day on PerGB2018; the $(Format-BlueprintCount $next) GB a day commitment tier is a candidate." -Detail @{ DailyAvgGb = $dailyAvg; NextRung = $next }
    }
    return $null
}
