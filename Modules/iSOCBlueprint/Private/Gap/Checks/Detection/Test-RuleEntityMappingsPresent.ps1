#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-DET-03: Enabled rule has no entity mappings

.DESCRIPTION
    Gap check for rule SAC-DET-03 (Resources/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Detection/Test-RuleEntityMappingsPresent.ps1
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
# SAC-DET-03, Enabled rule has no entity mappings
# ------------------------------------------------------------
function Test-RuleEntityMappingsPresent {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $rules = @(Get-GapEnabledQueryRule $Inventory)
    if ($rules.Count -eq 0) { return $null }
    $unmapped = @($rules | Where-Object {
        @(Get-PropOrDefault $_ 'properties.entityMappings' @() | Where-Object { $null -ne $_ }).Count -eq 0
    })
    if ($unmapped.Count -eq 0) { return $null }
    $names = @($unmapped | ForEach-Object { Get-GapRuleLabel $_ })
    $sample = $names -join '; '
    return New-Finding -Evidence "$(Format-BlueprintCount $unmapped.Count) of $(Format-BlueprintPlural $rules.Count 'enabled Scheduled/NRT rule') $(Select-GapWording $unmapped.Count 'has' 'have') no entity mappings: $sample." -Detail @{ Count = $unmapped.Count; Total = $rules.Count; Rules = $names }
}
