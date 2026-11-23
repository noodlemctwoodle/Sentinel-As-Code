#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-TI-02: Enabled rule queries the retired ThreatIntelligenceIndicator table

.DESCRIPTION
    Gap check for rule SAC-TI-02 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/ThreatIntel/Test-RulesOnLegacyThreatIntelTable.ps1
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
# SAC-TI-02, Enabled rule queries the retired ThreatIntelligenceIndicator table
# ------------------------------------------------------------
function Test-RulesOnLegacyThreatIntelTable {
    <#
    .SYNOPSIS
        Gap check SAC-TI-02: Enabled rule queries the retired ThreatIntelligenceIndicator table

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (@($Inventory.RuleTableReferences).Count -eq 0) { return $null }
    $hits = @($Inventory.RuleTableReferences | Where-Object {
        $null -ne $_ -and
        (ConvertTo-GapBool (Get-PropOrDefault $_ 'Enabled' $false)) -and
        (@(Get-PropOrDefault $_ 'Tables' @()) -contains 'ThreatIntelligenceIndicator')
    })
    if ($hits.Count -eq 0) { return $null }
    $names = @($hits | ForEach-Object { Get-EvidenceName $_ 'RuleName', 'RuleId' 'Unnamed rule' })
    return New-Finding -Evidence "$(Format-BlueprintPlural $hits.Count 'enabled rule') $(Select-GapWording $hits.Count 'queries' 'query') ThreatIntelligenceIndicator, which stopped receiving indicators on 31 Jul 2025: $($names -join '; '). $(Select-GapWording $hits.Count 'It matches' 'They match') against an expiring indicator set and will go quiet without any error." -Detail @{ Count = $hits.Count; Rules = $names }
}
