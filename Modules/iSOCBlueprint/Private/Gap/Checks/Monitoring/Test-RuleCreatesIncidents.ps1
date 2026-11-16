#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-MON-01: Enabled rule does not create incidents

.DESCRIPTION
    Gap check for rule SAC-MON-01 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Monitoring/Test-RuleCreatesIncidents.ps1
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
# SAC-MON-01, Enabled rule does not create incidents
# ------------------------------------------------------------
function Test-RuleCreatesIncidents {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $rules = @(Get-GapEnabledQueryRule $Inventory)
    if ($rules.Count -eq 0) { return $null }
    # createIncident defaults to true when the block is absent, so only an
    # explicit false counts.
    $alertOnly = @($rules | Where-Object {
        $ic = Get-PropOrDefault $_ 'properties.incidentConfiguration' $null
        ($null -ne $ic) -and ($ic.PSObject.Properties.Name -contains 'createIncident') -and (-not (ConvertTo-GapBool $ic.createIncident))
    })
    if ($alertOnly.Count -eq 0) { return $null }
    $names = @($alertOnly | ForEach-Object { Get-GapRuleLabel $_ })
    $sample = $names -join '; '
    return New-Finding -Evidence "$(Format-BlueprintPlural $alertOnly.Count 'enabled Scheduled/NRT rule') $(Select-GapWording $alertOnly.Count 'raises' 'raise') alerts without creating incidents: $sample." -Detail @{ Count = $alertOnly.Count; Rules = $names }
}
