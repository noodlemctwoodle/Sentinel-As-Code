#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-03: Daily cap not configured

.DESCRIPTION
    Gap check for rule SAC-LOG-03 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-DailyCapConfigured.ps1
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
# SAC-LOG-03, Daily cap not configured
# ------------------------------------------------------------
function Test-DailyCapConfigured {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $cap = Get-PropOrDefault $Inventory.Workspace 'properties.workspaceCapping.dailyQuotaGb' -1
    if ($null -eq $cap -or $cap -eq -1) {
        return New-Finding -Evidence 'workspaceCapping.dailyQuotaGb is unset (-1 = unlimited).' -Detail @{ DailyQuotaGb = $cap }
    }
    return $null
}
