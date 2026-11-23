#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 10-data-connectors.md (part 2 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/DataConnectors/Write-BlueprintDataConnectorsSectionPart2.ps1
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
function Write-BlueprintDataConnectorsSectionPart2 {
    <#
    .SYNOPSIS
        Build the figures for and write 10-data-connectors.md (part 2 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $catalogueBlock = $Context.catalogueBlock
    $ccfRows = $Context.ccfRows
    $connectorCatalogue = $Context.connectorCatalogue
    $connectorRows = $Context.connectorRows
    $connectors = $Context.connectors
    $effectiveRows = $Context.effectiveRows
    $healthRows = $Context.healthRows
    $kindCounts = $Context.kindCounts
    $kindPieRows = $Context.kindPieRows
    $unificationRows = $Context.unificationRows

    $connectorBody = @"
$(Format-Banner -Title 'Data Connectors')

## Connector mix

``````mermaid
pie showData title Connectors by kind
$($kindPieRows -join [Environment]::NewLine)
``````

$(Format-BlueprintPlural $connectors.Count 'connector') deployed across $(Format-BlueprintPlural $kindCounts.Count 'distinct kind').

## Classic connectors

$(Format-BlueprintTable -Items $connectorRows -Columns 'Title','Kind','DataTypes','State','Data7d')

## Codeless Connector Framework definitions

$(Format-BlueprintTable -Items $ccfRows -Columns 'Name','Title','Publisher')

## Effective connectors (synthesised view)

Modern Sentinel workspaces ingest most of their data through DCRs and diagnostic settings that don't register against the Sentinel ``dataConnectors`` endpoint. This table fuses every ingestion source the captured inventory can attribute, with precedence rules to avoid double-counting:

1. **Classic**: a classic data-connector explicitly covers the target table.
2. **CCF**: a Codeless Connector Framework definition. Listed by name; table claim depends on connector implementation.
3. **DCR**: derived from each data flow's ``outputStream`` (Microsoft-/Custom- prefixes stripped). Skipped when the table is already classic-claimed.
4. **Diagnostic**: derived from enabled diagnostic-setting log categories. Skipped when already claimed.
5. **Active-table**: a remaining table receiving billable data (>0 GB in the last 24h) that no captured ingestion mechanism explains. Surfaces as a visibility signal.

See ``Docs/Modules/iSOCBlueprint/Sentinel-Blueprint.md`` for the design note.

**Catalogue connector** is the data connector the connector catalogue credits with the table: the row's own connector for a classic connector, otherwise the connectors that list the table when there are at most three (marked when connected), otherwise how many connectors share it.

$(Format-BlueprintTable -Items $effectiveRows -Columns 'Source','Identifier','Table','CatalogueConnector','Last24hGB','LastIngested')

## Connected connectors against the catalogue

Each data connector in the workspace matched to the connector catalogue: the Content Hub data connectors and the tables each one writes, taken from the Azure-Sentinel repository (catalogue of $(if ($connectorCatalogue) { Format-BlueprintDate $connectorCatalogue.Version } else { 'n/a' })). **Silent** means none of the tables the catalogue lists for the connector received data in the last {recent}, free tables included ([SAC-PLT-10]). The catalogue takes a connector's tables from the connector's own mapping where Microsoft publishes one, otherwise from every table its solution's content reads, so a quiet table in the list is not always one the connector writes; a connector with data in any of its tables counts as receiving data.

$catalogueBlock

## Connector health (24h activity)

Last ingested and 24-hour billable volume per **classic** data-connector's data type, joined against the workspace ``Usage`` summary. Rows with a blank Table column have no known data-type-to-table mapping in the renderer; cross-reference [83-data-collection.md](83-data-collection.md) for DCRs and [81-table-plans-retention.md](81-table-plans-retention.md) for the full per-table view.

$(Format-BlueprintTable -Items $healthRows -Columns 'Connector','DataType','Table','LastIngested','BillableLast24hGB')

## Defender XDR unification

How far this workspace is on the unified Sentinel and Defender model: the XDR connector and its data types, the advanced-hunting tables actually streaming, the legacy incident-creation rules that the unified queue makes redundant, and the Defender for Cloud connectors.

$(Format-BlueprintTable -Items $unificationRows -Columns 'Check','Value','Meaning')

[Connector reference (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/data-connectors-reference) · [Connector health monitoring](https://learn.microsoft.com/azure/sentinel/monitor-data-connectors-health)
"@

    Write-BlueprintSection '10-data-connectors.md' $connectorBody
}
