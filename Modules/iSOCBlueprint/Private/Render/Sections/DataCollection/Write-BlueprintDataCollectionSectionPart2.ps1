#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 83-data-collection.md (part 2 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/DataCollection/Write-BlueprintDataCollectionSectionPart2.ps1
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
function Write-BlueprintDataCollectionSectionPart2 {
    <#
    .SYNOPSIS
        Build the figures for and write 83-data-collection.md (part 2 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $dceRows = $Context.dceRows
    $dcrOutOfScopeRows = $Context.dcrOutOfScopeRows
    $dcrRows = $Context.dcrRows
    $dstClassLine = $Context.dstClassLine
    $dstEdges = $Context.dstEdges
    $dstNodes = $Context.dstNodes
    $hasArchive = $Context.hasArchive
    $hasAuxiliary = $Context.hasAuxiliary
    $hasBasic = $Context.hasBasic
    $hasDataLake = $Context.hasDataLake
    $hasDownstream = $Context.hasDownstream
    $m = $Context.m
    $n = $Context.n
    $sourceEdges = $Context.sourceEdges
    $srcLines = $Context.srcLines
    $topologyVisualLine = $Context.topologyVisualLine
    $WorkspaceName = $Context.WorkspaceName
    $wspEdges = $Context.wspEdges
    $wspNodes = $Context.wspNodes

    $dcBody = @"
$(Format-Banner -Title "Data Collection Rules and Endpoints")

## Workspace topology

Every captured ingestion source, grouped into product families with the number of distinct sources feeding each; then the workspace, its analytics rules and the table plans it uses; then where its data goes. A plan or destination shows as in use only when the capture supports it: the Data Lake only when the tenant is enrolled, the Defender XDR portal only when the Microsoft 365 Defender connector is enabled.

``````mermaid
flowchart LR
$topologyVisualLine
    subgraph SRC["Connected sources"]
        direction TB
$($srcLines -join [Environment]::NewLine)
    end

    subgraph WSP["Sentinel workspace"]
        direction TB
$($wspNodes -join [Environment]::NewLine)
    end
$(if ($hasDownstream) { @"

    subgraph DST["Downstream"]
        direction TB
$($dstNodes -join [Environment]::NewLine)
    end
"@ })

$($sourceEdges -join [Environment]::NewLine)
$($wspEdges -join [Environment]::NewLine)
$(if ($hasDownstream) { $dstEdges -join [Environment]::NewLine })

    classDef src fill:#1a3b5b,stroke:#37a,color:#dfd
    classDef wsp fill:#5b3a1a,stroke:#a73,color:#fed
    classDef dst fill:#1a3b1a,stroke:#3a3,color:#dfd
    class $((@('WS','RUL','INC') + @(if ($hasBasic){'BAS'}) + @(if ($hasAuxiliary){'AUX'}) + @(if ($hasDataLake){'DL'}) + @(if ($hasArchive){'ARC'})) -join ',') wsp
$dstClassLine
``````

## DCRs

Only DCRs whose ``destinations.logAnalytics`` includes this workspace appear here. DCRs that live in this subscription but route to other workspaces are excluded from the primary table (see *Other DCRs in subscription* below).

$(Format-BlueprintTable -Items $dcrRows -Columns 'Name','Kind','Streams','HasTransform')

$(if ($dcrOutOfScopeRows.Count -gt 0) { @"

## Other DCRs in subscription (targeting different workspaces)

These DCRs were captured at subscription scope but their LA destinations point at workspaces other than ``$WorkspaceName``. Useful for cleanup audits (orphaned DCRs from decommissioned workspaces, mis-routed DCRs after a workspace migration, etc.), not relevant to this workspace's ingestion.

$(Format-BlueprintTable -Items $dcrOutOfScopeRows -Columns 'Name','Kind','TargetsWs')
"@ })

## DCEs

$(Format-BlueprintTable -Items $dceRows -Columns 'Name','Location')

[Data collection rules (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview) · [Transformations](https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-transformations)
"@
    Write-BlueprintSection '83-data-collection.md' $dcBody
}
