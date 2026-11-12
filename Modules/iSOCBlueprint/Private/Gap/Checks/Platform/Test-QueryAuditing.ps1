#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-PLT-12: Query auditing (LAQueryLogs) not enabled

.DESCRIPTION
    Gap check for rule SAC-PLT-12 (Resources/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Platform/Test-QueryAuditing.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# ------------------------------------------------------------
# SAC-PLT-12, Query auditing (LAQueryLogs) not enabled
# ------------------------------------------------------------
function Test-QueryAuditing {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if ($Inventory.RawFiles -notcontains 'la-query-logs.json') { return $null }
    $row = @($Inventory.LaQueryLogs | Where-Object { $null -ne $_ }) | Select-Object -First 1
    $count = if ($row) { ConvertTo-GapInt (Get-PropOrDefault $row 'QueryCount' 0) } else { 0 }
    if ($count -gt 0) { return $null }
    return New-Finding -Evidence "LAQueryLogs recorded no queries in the last $(Format-GapDays (Get-GapWindow $Inventory).Days): query auditing is not enabled on the workspace, so nobody can see who searched which data." -Detail @{ QueryCount7d = $count }
}
