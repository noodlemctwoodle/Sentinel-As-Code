#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 27-threat-intelligence.md (part 2 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/ThreatIntelligence/Write-BlueprintThreatIntelligenceSectionPart2.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintThreatIntelligenceSectionPart2 {
    <#
    .SYNOPSIS
        Build the figures for and write 27-threat-intelligence.md (part 2 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $taxiiRows = $Context.taxiiRows
    $tiFeedRows = $Context.tiFeedRows
    $tiHeadline = $Context.tiHeadline
    $tiHealthBlock = $Context.tiHealthBlock
    $tiKqlSourceRows = $Context.tiKqlSourceRows
    $tiMigration = $Context.tiMigration
    $tiObjectsBlock = $Context.tiObjectsBlock
    $tiPieBlock = $Context.tiPieBlock
    $tiRows = $Context.tiRows
    $tiTableRows = $Context.tiTableRows
    $tiTypeBlock = $Context.tiTypeBlock

    Write-BlueprintSection '27-threat-intelligence.md' (@"
$(Format-Banner -Title 'Threat Intelligence  (TOC 4.17)')

Indicator counts and most-recent ingestion timestamp by source, last {lookback}. Indicator detail is intentionally NOT exported to keep the report aggregate-only.

$tiHeadline
$tiPieBlock

$(Format-BlueprintTable -Items @($tiRows | ForEach-Object { [pscustomobject]@{ SourceSystem = $_.SourceSystem; IndicatorCount = (Format-BlueprintCount $_.IndicatorCount); LastIngested = (Format-DateUtc $_.LastIngested) } }) -Columns 'SourceSystem','IndicatorCount','LastIngested')

## Table migration status

$tiMigration

$(Format-BlueprintTable -Items $tiTableRows -Columns 'Table','Records30d','Records7d','FirstSeen','LastSeen','Status')

## Indicator health (last {lookback-d})

Each indicator in ``ThreatIntelIndicators`` at its latest state. Deleted and revoked indicators no longer match; an indicator past its ``ValidUntil`` date is kept for history but should not drive new alerts.

$tiHealthBlock

## Indicators by source (last {lookback-d})

Records and distinct indicators per source system, from the indicator tables themselves (current and retired).

$(Format-BlueprintTable -Items $tiKqlSourceRows -Columns 'SourceSystem','Records','Indicators','LastSeen')
$tiTypeBlock
$tiObjectsBlock

## Feeds

Where indicators come from. One feed is a single point of failure for every TI detection; [SAC-TI-05] fires when there is at most one.

### Threat intelligence connectors

$(Format-BlueprintTable -Items $tiFeedRows -Columns 'Kind','Name')

### TAXII clients

TAXII 2.x collections the workspace polls, from the threat intelligence TAXII client list. Not every service returns this list; the connectors above remain the reliable feed signal.

$(Format-BlueprintTable -Items $taxiiRows -Columns 'Name','Collection','Polling','Server','Description' -EmptyMessage (Get-BlueprintEmptyMessage 'taxii-clients.json' '_No TAXII clients returned._'))

[Microsoft Sentinel Threat Intelligence (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/understand-threat-intelligence)
"@)
}
