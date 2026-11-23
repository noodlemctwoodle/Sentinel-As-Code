#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-DET-15: Watchlist read by enabled rules not updated in 90 days

.DESCRIPTION
    Gap check for rule SAC-DET-15 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Detection/Test-WatchlistsStale.ps1
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
# SAC-DET-15, Watchlist read by enabled rules not updated in 90 days
# ------------------------------------------------------------
function Test-WatchlistsStale {
    <#
    .SYNOPSIS
        Gap check SAC-DET-15: Watchlist read by enabled rules not updated in 90 days

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not ($Inventory.PSObject.Properties.Name -contains 'Watchlists') -or $null -eq $Inventory.Watchlists) { return $null }
    $use = Get-WatchlistRuleUse -Rules @($Inventory.AlertRules)
    $stale = @(Get-WatchlistFreshness -Watchlists @($Inventory.Watchlists) -RuleUse $use | Where-Object Status -EQ 'Stale, used by rules' | Sort-Object AgeDays -Descending)
    if ($stale.Count -eq 0) { return $null }
    $names = ($stale | ForEach-Object { "$(Get-EvidenceName $_ 'Name', 'Alias' 'Unnamed watchlist') ($(Format-BlueprintPlural $_.AgeDays 'day'), $(Format-BlueprintPlural $_.EnabledRules 'rule'))" }) -join '; '
    return New-Finding -Evidence "$(Format-BlueprintPlural $stale.Count 'watchlist') read by enabled analytics rules $(Select-GapWording $stale.Count 'has' 'have') not been updated in $(Format-BlueprintPlural $script:WatchlistStaleDays 'day') or more: $names." -Detail @{ Count = $stale.Count }
}
