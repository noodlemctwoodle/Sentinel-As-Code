#Requires -Version 7.6

<#
.SYNOPSIS
    The enabled Scheduled and NRT analytics rules in the inventory.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Inventory/Get-GapEnabledQueryRule.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Get-GapEnabledQueryRule {
    <#
    .SYNOPSIS
        The enabled Scheduled and NRT analytics rules in the inventory.

    .DESCRIPTION
        These are the only kinds whose query, entity mappings and incident
        settings are authored by the workspace owner.

    .PARAMETER Inventory
        The gap inventory; its AlertRules are read.

    .OUTPUTS
        The matching rules as an array, empty when none match.
    #>
    [CmdletBinding()]
    param([object]$Inventory)
    return @($Inventory.AlertRules | Where-Object {
            $null -ne $_ -and
            ((Get-PropOrDefault $_ 'kind' '') -in @('Scheduled', 'NRT')) -and
            (ConvertTo-GapBool (Get-PropOrDefault $_ 'properties.enabled' $false))
        })
}
