#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-PLT-05: Workspace replication disabled

.DESCRIPTION
    Gap check for rule SAC-PLT-05 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Platform/Test-ReplicationEnabled.ps1
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
# SAC-PLT-05, Workspace replication disabled
# ------------------------------------------------------------
function Test-ReplicationEnabled {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $enabled = Get-PropOrDefault $Inventory.Workspace 'properties.replication.enabled' $false
    if (-not $enabled) {
        return New-Finding -Evidence 'Workspace replication is disabled.'
    }
    return $null
}
