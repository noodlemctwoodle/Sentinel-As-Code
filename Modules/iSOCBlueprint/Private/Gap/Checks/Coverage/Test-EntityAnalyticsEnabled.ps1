#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-COV-08: Entity analytics not enabled

.DESCRIPTION
    Gap check for rule SAC-COV-08 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Coverage/Test-EntityAnalyticsEnabled.ps1
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
# SAC-COV-08, Entity analytics not enabled
# ------------------------------------------------------------
function Test-EntityAnalyticsEnabled {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # Two signals: identity providers on the EntityAnalytics settings
    # resource, and IdentityInfo rows. Either capture missing is unknown.
    if ($Inventory.RawFiles -notcontains 'settings.json' -or $Inventory.RawFiles -notcontains 'ueba-data-presence.json') { return $null }
    $providers = @(Get-PropOrDefault $Inventory.Settings 'EntityAnalytics.properties.entityProviders' @() | Where-Object { $_ })
    if ($providers.Count -gt 0) { return $null }
    $identity = @($Inventory.UebaDataPresence | Where-Object { $null -ne $_ -and [string](Get-PropOrDefault $_ 'TableName' '') -eq 'IdentityInfo' }) | Select-Object -First 1
    $rows = if ($identity) { ConvertTo-GapInt (Get-PropOrDefault $identity 'Count14d' (Get-PropOrDefault $identity 'Count' 0)) } else { 0 }
    if ($rows -gt 0) { return $null }
    return New-Finding -Evidence 'Entity analytics has no identity provider configured and IdentityInfo received no rows in the last 14 days, so incidents carry no account or group context.' -Detail @{ Providers = @(); IdentityInfoRows = 0 }
}
