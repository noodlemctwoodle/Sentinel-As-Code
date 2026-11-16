#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-GOV-05: Service principal with Owner/Contributor at workspace scope

.DESCRIPTION
    Gap check for rule SAC-GOV-05 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Governance/Test-ServicePrincipalOverPrivileged.ps1
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
# SAC-GOV-05, Service principal with Owner/Contributor at workspace scope
# ------------------------------------------------------------
function Test-ServicePrincipalOverPrivileged {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.RbacWorkspace) { return $null }
    $bad = @($Inventory.RbacWorkspace | Where-Object {
        $role = Get-PropOrDefault $_ 'RoleDefinitionName' ''
        $type = Get-PropOrDefault $_ 'ObjectType' ''
        ($role -in @('Owner','Contributor')) -and ($type -eq 'ServicePrincipal')
    })
    if ($bad.Count -eq 0) { return $null }
    # A principal Azure cannot name (deleted, or not readable by the
    # collector) still has its object id, which finds it in Entra ID.
    $names = ($bad | ForEach-Object {
            $oid = [string](Get-PropOrDefault $_ 'ObjectId' '')
            Get-EvidenceName $_ 'DisplayName', 'SignInName' $(if ($oid) { "Unnamed service principal, object id $oid (deleted or not readable)" } else { 'Unnamed service principal' })
        }) -join '; '
    return New-Finding -Evidence "$(Format-BlueprintPlural $bad.Count 'service principal') $(Select-GapWording $bad.Count 'holds' 'hold') Owner or Contributor at workspace scope: $names." -Detail @{ Count = $bad.Count }
}
