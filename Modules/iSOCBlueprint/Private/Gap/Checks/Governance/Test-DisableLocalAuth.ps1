#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-GOV-07: disableLocalAuth

.DESCRIPTION
    Gap check for rule SAC-GOV-07 (Resources/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Governance/Test-DisableLocalAuth.ps1
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
# SAC-GOV-07, disableLocalAuth
# ------------------------------------------------------------
function Test-DisableLocalAuth {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $disabled = Get-PropOrDefault $Inventory.Workspace 'properties.features.disableLocalAuth' $false
    if (-not $disabled) {
        return New-Finding -Evidence 'features.disableLocalAuth is false, workspace shared keys are accepted for ingestion.'
    }
    return $null
}
