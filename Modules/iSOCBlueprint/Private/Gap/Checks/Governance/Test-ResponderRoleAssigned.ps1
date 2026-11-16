#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-GOV-04: Zero Microsoft Sentinel Responder assignments

.DESCRIPTION
    Gap check for rule SAC-GOV-04 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Governance/Test-ResponderRoleAssigned.ps1
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
# SAC-GOV-04, Zero Microsoft Sentinel Responder assignments
# ------------------------------------------------------------
function Test-ResponderRoleAssigned {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.RbacWorkspace) { return $null }
    $hasResponder = @($Inventory.RbacWorkspace | Where-Object {
        (Get-PropOrDefault $_ 'RoleDefinitionName' '') -eq 'Microsoft Sentinel Responder'
    }).Count -gt 0
    if ($hasResponder) { return $null }
    return New-Finding -Evidence 'No identity holds the Microsoft Sentinel Responder role at workspace scope. Analysts cannot act on incidents through least-privilege access.'
}
