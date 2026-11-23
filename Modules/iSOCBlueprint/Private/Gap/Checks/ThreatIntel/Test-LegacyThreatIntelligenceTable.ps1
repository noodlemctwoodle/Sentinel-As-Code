#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-TI-01: Legacy ThreatIntelligenceIndicator table still in use

.DESCRIPTION
    Gap check for rule SAC-TI-01 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/ThreatIntel/Test-LegacyThreatIntelligenceTable.ps1
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
# SAC-TI-01, Legacy ThreatIntelligenceIndicator table still in use
# ------------------------------------------------------------
function Test-LegacyThreatIntelligenceTable {
    <#
    .SYNOPSIS
        Gap check SAC-TI-01: Legacy ThreatIntelligenceIndicator table still in use

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    if (-not $Inventory.TablesWithData) { return $null }
    $legacy = @($Inventory.TablesWithData | Where-Object {
            (Get-PropOrDefault $_ 'DataType' '') -eq 'ThreatIntelligenceIndicator' -and
            [double](Get-PropOrDefault $_ 'BillableLast30d' 0) -gt 0
        } | Select-Object -First 1)
    if ($legacy.Count -eq 0) { return $null }
    $gb30 = [double](Get-PropOrDefault $legacy[0] 'BillableLast30d' 0)
    # Detect whether the workspace has ALSO started receiving into the new
    # ThreatIntelIndicators table, if yes the finding evidence calls out
    # that the migration is half done; if no, fresh ingestion is broken.
    $newPresent = @($Inventory.TablesWithData | Where-Object {
            (Get-PropOrDefault $_ 'DataType' '') -eq 'ThreatIntelIndicators' -and
            [double](Get-PropOrDefault $_ 'BillableLast30d' 0) -gt 0
        }).Count -gt 0
    $statusNote = if ($newPresent) {
        'New ThreatIntelIndicators table is also active, partial migration; ensure all detections, hunting queries and workbooks read from the new tables.'
    } else {
        'No data observed in the new ThreatIntelIndicators / ThreatIntelObjects tables, TI ingestion may be broken since the 31 Jul 2025 cutoff.'
    }
    return New-Finding -Evidence "ThreatIntelligenceIndicator (legacy) carries $(Format-BlueprintGb $gb30) GB in the last $(Format-GapDays (Get-GapWindow $Inventory).Days). $statusNote" -Detail @{ LegacyGb30d = $gb30; NewTablePresent = $newPresent }
}
