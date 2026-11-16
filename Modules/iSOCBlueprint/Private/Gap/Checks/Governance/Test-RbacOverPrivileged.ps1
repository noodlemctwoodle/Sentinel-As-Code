#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-GOV-06: Owner/Contributor at workspace scope

.DESCRIPTION
    Gap check for rule SAC-GOV-06 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Governance/Test-RbacOverPrivileged.ps1
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
# SAC-GOV-06, Owner/Contributor at workspace scope
# ------------------------------------------------------------
function Test-RbacOverPrivileged {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $bad = @($Inventory.RbacWorkspace | Where-Object {
        $role = Get-PropOrDefault $_ 'RoleDefinitionName' ''
        $role -in @('Owner','Contributor')
    })
    if ($bad.Count -gt 0) {
        return New-Finding -Evidence "$(Format-BlueprintPlural $bad.Count 'Owner/Contributor role assignment') at workspace scope." -Detail @{ Count = $bad.Count }
    }
    return $null
}
