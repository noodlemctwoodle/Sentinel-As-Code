#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-GOV-03: No deletion-protection lock on the workspace

.DESCRIPTION
    Gap check for rule SAC-GOV-03 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Governance/Test-WorkspaceLockPresent.ps1
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
# SAC-GOV-03, No deletion-protection lock on the workspace
# ------------------------------------------------------------
function Test-WorkspaceLockPresent {
    <#
    .SYNOPSIS
        Gap check SAC-GOV-03: No deletion-protection lock on the workspace

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    $locks = @($Inventory.WorkspaceLocks)
    $relevant = @($locks | Where-Object {
            $level = Get-PropOrDefault $_ 'properties.level' ''
            $level -in @('CanNotDelete', 'ReadOnly')
        })
    if ($relevant.Count -gt 0) { return $null }
    return New-Finding -Evidence 'No CanNotDelete or ReadOnly lock on the workspace. Accidental or malicious deletion would lose all detection rules, watchlists, hunting queries, and historical incident data.'
}
