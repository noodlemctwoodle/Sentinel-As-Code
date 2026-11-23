#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-AUT-05: Playbook MI lacks Sentinel Responder role

.DESCRIPTION
    Gap check for rule SAC-AUT-05 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Automation/Test-PlaybookMiHasResponder.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# ------------------------------------------------------------
# SAC-AUT-05, Playbook MI lacks Sentinel Responder role
# ------------------------------------------------------------
function Test-PlaybookMiHasResponder {
    <#
    .SYNOPSIS
        Gap check SAC-AUT-05: Playbook MI lacks Sentinel Responder role

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.PlaybookMiAssignments -or @($Inventory.PlaybookMiAssignments).Count -eq 0) {
        return $null
    }
    $bad = @($Inventory.PlaybookMiAssignments | Where-Object {
        $roles = Get-PropOrDefault $_ 'WorkspaceRoles' @()
        -not ($roles -contains 'Microsoft Sentinel Responder')
    })
    if ($bad.Count -gt 0) {
        return New-Finding -Evidence "$(Format-BlueprintPlural $bad.Count 'playbook managed identity' 'playbook managed identities') missing Microsoft Sentinel Responder." -Detail @{ Count = $bad.Count }
    }
    return $null
}
