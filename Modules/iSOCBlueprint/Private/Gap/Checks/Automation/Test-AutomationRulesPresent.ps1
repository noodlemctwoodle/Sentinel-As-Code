#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-AUT-01: No automation rules defined

.DESCRIPTION
    Gap check for rule SAC-AUT-01 (Resources/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Automation/Test-AutomationRulesPresent.ps1
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
# SAC-AUT-01, No automation rules defined
# ------------------------------------------------------------
function Test-AutomationRulesPresent {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $count = @($Inventory.AutomationRules).Count
    if ($count -gt 0) { return $null }
    return New-Finding -Evidence 'No automation rules defined, every incident requires manual triage.'
}
