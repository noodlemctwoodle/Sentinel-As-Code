#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-COV-05: UEBA disabled

.DESCRIPTION
    Gap check for rule SAC-COV-05 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Coverage/Test-UebaEnabled.ps1
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
# SAC-COV-05, UEBA disabled
# ------------------------------------------------------------
function Test-UebaEnabled {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $ueba = Get-PropOrDefault $Inventory.Settings 'Ueba'

    # Data-presence inference: when UEBA is producing rows in any of its
    # tables, treat the workspace as "effectively on" regardless of whether
    # the settings resource was written. The portal toggle leaves the
    # configuration resource absent, so a settings-only check produces a
    # false positive on the common case. The producing-data signal is
    # captured separately by the exporter as ueba-data-presence.json.
    $presence = @()
    if ($Inventory.PSObject.Properties.Name -contains 'UebaDataPresence') {
        $presence = @($Inventory.UebaDataPresence)
    }
    $producingCount = 0
    foreach ($row in $presence) {
        if (-not $row) { continue }
        $c = Get-PropOrDefault $row 'Count'
        if ($null -ne $c) {
            $n = 0
            if ([int]::TryParse([string]$c, [ref]$n)) { $producingCount += $n }
        }
    }
    if ($producingCount -gt 0) { return $null }

    if ($null -eq $ueba) {
        return New-Finding -Evidence "No Ueba setting resource found on the workspace and no rows observed in BehaviorAnalytics / IdentityInfo / UserPeerAnalytics in the last $(Format-GapDays (Get-GapWindow $Inventory).Days)."
    }
    $enabled = Get-PropOrDefault $ueba 'properties.dataSources'
    if (-not $enabled -or $enabled.Count -eq 0) {
        return New-Finding -Evidence "UEBA is configured but no data sources are enabled, and no rows observed in BehaviorAnalytics / IdentityInfo / UserPeerAnalytics in the last $(Format-GapDays (Get-GapWindow $Inventory).Days)." -Detail $ueba
    }
    return $null
}
