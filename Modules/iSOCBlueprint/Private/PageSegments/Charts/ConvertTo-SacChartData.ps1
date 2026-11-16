#Requires -Version 7.6

<#
.SYNOPSIS
    A chart's data for the chart web part. A flowchart node's link is mapped the way a text
    run's is: a site URL ('~site/...'), or none when the target has no page on the site. A
    finding card links to the findings list filtered to its finding. Other kinds pass through.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Charts/ConvertTo-SacChartData.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, SharePoint page conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function ConvertTo-SacChartData {
    <#
    .SYNOPSIS
        A chart's data for the chart web part. A flowchart node's link is
        mapped the way a text run's is: a site URL ('~site/...'), or none
        when the target has no page on the site. A finding card links to the
        findings list filtered to its finding. Other kinds pass through.

    .PARAMETER Chart
        A chart block from the section model.

    .PARAMETER FindingsListUrl
        Site-relative URL of the findings list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Chart,
        [Parameter(Mandatory)] [string] $FindingsListUrl
    )
    if ([string]$Chart.kind -eq 'finding-cards' -and $null -ne $Chart.data) {
        $cards = $Chart.data | ConvertTo-Json -Depth 32 | ConvertFrom-Json -AsHashtable -Depth 32
        foreach ($c in @($cards.cards)) {
            if (-not $c) { continue }
            $href = if ($c['id']) {
                ConvertTo-SacSiteLink -Run @{ href = $c['href']; target = @{ kind = 'finding'; id = [string]$c['id'] } } -FindingsListUrl $FindingsListUrl
            } else { $null }
            $c['href'] = $(if ($href) { $href.Replace('&amp;', '&') } else { $null })
        }
        return $cards
    }
    if ([string]$Chart.kind -ne 'flowchart' -or $null -eq $Chart.data) { return $Chart.data }
    # A copy, so the section model itself is left as it was read.
    $data = $Chart.data | ConvertTo-Json -Depth 32 | ConvertFrom-Json -AsHashtable -Depth 32
    foreach ($n in @($data.nodes)) {
        if ($null -eq $n) { continue }
        $href = $null
        if ($n['href'] -and $n['target']) { $href = ConvertTo-SacSiteLink -Run $n -FindingsListUrl $FindingsListUrl }
        # The web part escapes attribute values itself, so the URL is raw.
        $n['href'] = $(if ($href) { $href.Replace('&amp;', '&') } else { $null })
    }
    return $data
}
