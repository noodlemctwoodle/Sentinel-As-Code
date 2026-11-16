#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-DET-07: Content Hub solution updates available

.DESCRIPTION
    Gap check for rule SAC-DET-07 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Detection/Test-ContentHubUpdatesAvailable.ps1
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
# SAC-DET-07, Content Hub solution updates available
# ------------------------------------------------------------
function Test-ContentHubUpdatesAvailable {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.ContentPackages -or -not $Inventory.ContentProductPackages) { return $null }
    $latest = @{}
    foreach ($p in $Inventory.ContentProductPackages) {
        $id = Get-PropOrDefault $p 'properties.contentId' ''
        $v = Get-PropOrDefault $p 'properties.version' ''
        if ($id -and $v) { $latest[$id] = $v }
    }
    $stale = @($Inventory.ContentPackages | Where-Object {
        $id = Get-PropOrDefault $_ 'properties.contentId' ''
        $installed = Get-PropOrDefault $_ 'properties.version' ''
        $id -and $installed -and $latest.ContainsKey($id) -and ($latest[$id] -ne $installed)
    })
    if ($stale.Count -gt 0) {
        return New-Finding -Evidence "$(Format-BlueprintPlural $stale.Count 'installed Content Hub solution') $(Select-GapWording $stale.Count 'has' 'have') a newer version available." -Detail @{ Count = $stale.Count }
    }
    return $null
}
