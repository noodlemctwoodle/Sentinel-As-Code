#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-TI-05: Threat intelligence relies on a single feed

.DESCRIPTION
    Gap check for rule SAC-TI-05 (Resources/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/ThreatIntel/Test-ThreatIntelSingleFeed.ps1
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
# SAC-TI-05, Threat intelligence relies on a single feed
# ------------------------------------------------------------
function Test-ThreatIntelSingleFeed {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # Connector inventory is the primary signal; without it the check
    # would report "no feed" on every failed capture.
    if ($Inventory.RawFiles -notcontains 'data-connectors-classic.json') { return $null }
    $tiKinds = @('MicrosoftThreatIntelligence', 'ThreatIntelligenceTaxii', 'ThreatIntelligence', 'ThreatIntelligenceUploadIndicatorsAPI', 'PremiumMicrosoftDefenderForThreatIntelligence')
    $feeds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($c in @($Inventory.DataConnectors)) {
        $kind = [string](Get-PropOrDefault $c 'kind' '')
        if ($kind -and $tiKinds -contains $kind) { [void]$feeds.Add($kind) }
    }
    # Indicators from a non-Microsoft source count as a feed even when the
    # connector that brought them in is not in the classic list (TAXII and
    # upload-API sources show up here by name).
    foreach ($row in @($Inventory.ThreatIntelCounts)) {
        $src = [string](Get-PropOrDefault $row 'SourceSystem' '')
        if ($src -and $src -notmatch '^(Microsoft|Azure Sentinel)') { [void]$feeds.Add("source: $src") }
    }
    if ($feeds.Count -gt 1) { return $null }
    $evidence = if ($feeds.Count -eq 0) {
        "No threat intelligence feed is connected and no indicators were seen in the last $(Format-GapDays (Get-GapWindow $Inventory).Days)."
    } else {
        "Threat intelligence comes from a single feed ($(@($feeds) -join ''))."
    }
    return New-Finding -Evidence "$evidence Every TI-based detection depends on that one source." -Detail @{ Feeds = @($feeds) }
}
