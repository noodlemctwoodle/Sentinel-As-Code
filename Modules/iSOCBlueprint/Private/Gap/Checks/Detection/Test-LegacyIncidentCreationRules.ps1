#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-DET-08: Legacy Microsoft incident-creation rules still enabled

.DESCRIPTION
    Gap check for rule SAC-DET-08 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Detection/Test-LegacyIncidentCreationRules.ps1
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
# SAC-DET-08, Legacy Microsoft incident-creation rules still enabled
# ------------------------------------------------------------
function Test-LegacyIncidentCreationRules {
    <#
    .SYNOPSIS
        Gap check SAC-DET-08: Legacy Microsoft incident-creation rules still enabled

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'The name is the published CheckName on every finding and is dispatched by name from best-practices.json.')]
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    $legacy = @($Inventory.AlertRules | Where-Object {
            $null -ne $_ -and
            ((Get-PropOrDefault $_ 'kind' '') -eq 'MicrosoftSecurityIncidentCreation') -and
            (ConvertTo-GapBool (Get-PropOrDefault $_ 'properties.enabled' $false))
        })
    if ($legacy.Count -eq 0) { return $null }
    $xdrIncidents = @($Inventory.DataConnectors | Where-Object {
            $null -ne $_ -and
            ((Get-PropOrDefault $_ 'kind' '') -eq 'MicrosoftThreatProtection') -and
            ((Get-PropOrDefault $_ 'properties.dataTypes.incidents.state' '') -eq 'enabled')
        }).Count -gt 0
    $names = @($legacy | ForEach-Object { Get-GapRuleLabel $_ })
    $these = Select-GapWording $legacy.Count 'this rule' 'these rules'
    $note = if ($xdrIncidents) {
        "The Defender XDR connector already syncs incidents, so $these can create duplicate incidents for the same alerts."
    } else {
        "The Defender XDR connector is not syncing incidents; enable that first so alert-to-incident creation moves to XDR before $these $(Select-GapWording $legacy.Count 'is' 'are') retired."
    }
    return New-Finding -Evidence "$(Format-BlueprintPlural $legacy.Count 'enabled Microsoft incident-creation rule'): $($names -join '; '). $note" -Detail @{ Count = $legacy.Count; Rules = $names; XdrIncidentsConnected = $xdrIncidents }
}
