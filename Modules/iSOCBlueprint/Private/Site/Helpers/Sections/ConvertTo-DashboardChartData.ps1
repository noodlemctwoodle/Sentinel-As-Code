#Requires -Version 7.6

<#
.SYNOPSIS
    A section chart in the shape the dashboard draws.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Sections/ConvertTo-DashboardChartData.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-DashboardChartData {
    <#
    .SYNOPSIS
        A chart's data in the shape the dashboard draws.

    .DESCRIPTION
        A flowchart node that links to a section or a finding gets an
        in-dashboard address (/#sac-section-NN or /#sac-finding-ID), which the
        dashboard opens in its Report tab or findings view. A web link is kept,
        and a node with any other target, or none, has no link. A finding-cards
        chart links each card that has an id to its finding the same way. The
        data is copied through JSON first, so the chart itself is not changed.
        Any other kind returns its data as it is.

    .PARAMETER Chart
        The chart block, read for its kind and data.

    .OUTPUTS
        The chart's data: a hashtable copy for a flowchart or finding-cards
        chart, otherwise the chart's own data.
    #>
    [CmdletBinding()]
    param($Chart)
    if ([string]$Chart.kind -eq 'finding-cards' -and $null -ne $Chart.data) {
        $cards = $Chart.data | ConvertTo-Json -Depth 32 | ConvertFrom-Json -AsHashtable -Depth 32
        foreach ($c in @($cards.cards)) { if ($c) { $c['href'] = $(if ($c['id']) { "/#sac-finding-$([string]$c['id'])" } else { $null }) } }
        return $cards
    }
    if ([string]$Chart.kind -ne 'flowchart' -or $null -eq $Chart.data) { return $Chart.data }
    $data = $Chart.data | ConvertTo-Json -Depth 32 | ConvertFrom-Json -AsHashtable -Depth 32
    foreach ($n in @($data.nodes)) {
        if ($null -eq $n) { continue }
        $href = $null
        $target = $n['target']
        if ($n['href'] -and $target) {
            switch ([string]$target['kind']) {
                'section' { if ([string]$target['section'] -match '^(\d+)') { $href = "/#sac-section-$([int]$Matches[1])" } }
                'finding' { $href = "/#sac-finding-$([string]$target['id'])" }
                'external' { $href = [string]$n['href'] }
            }
        }
        $n['href'] = $href
    }
    return $data
}
