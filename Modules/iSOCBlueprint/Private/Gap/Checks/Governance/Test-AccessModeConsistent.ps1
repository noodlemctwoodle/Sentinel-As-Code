#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-GOV-08: Access mode consistency

.DESCRIPTION
    Gap check for rule SAC-GOV-08 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Governance/Test-AccessModeConsistent.ps1
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
# SAC-GOV-08, Access mode consistency
# ------------------------------------------------------------
function Test-AccessModeConsistent {
    <#
    .SYNOPSIS
        Gap check SAC-GOV-08: Access mode consistency

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    # Informational, surface the flag value so the reviewer can confirm it matches intent.
    $flag = Get-PropOrDefault $Inventory.Workspace 'properties.features.enableLogAccessUsingOnlyResourcePermissions' $null
    if ($null -eq $flag) {
        return New-Finding -Evidence 'enableLogAccessUsingOnlyResourcePermissions is unset, confirm whether resource-context or workspace-context access is intended.'
    }
    return $null
}
