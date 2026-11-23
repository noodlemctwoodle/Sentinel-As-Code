#Requires -Version 7.6

<#
.SYNOPSIS
    Text web part HTML for a chart, used when the chart web part is not available on the site: the chart's data as a table, or its title.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Charts/ConvertTo-SacChartFallbackHtml.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint page conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-SacChartFallbackHtml {
    <#
    .SYNOPSIS
        Text web part HTML for a chart, used when the chart web part is not
        available on the site: the chart's data as a table, or its title.

    .PARAMETER Chart
        A chart segment's chart (kind, title, data).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] $Chart)

    $sb = [System.Text.StringBuilder]::new()
    if ($Chart.title) { [void]$sb.Append('<p><strong>' + (ConvertTo-SacHtmlText ([string]$Chart.title)) + '</strong></p>') }
    # @() keeps a one-row chart a list of rows rather than one row's cells.
    $rows = @(switch ([string]$Chart.kind) {
        'pie' { foreach ($s in @($Chart.data.slices)) { , @([string]$s.label, [string]$s.value) } }
        'sankey' { foreach ($l in @($Chart.data.links)) { , @("$($l.source) to $($l.target)", [string]$l.value) } }
        'incident-lifecycle' {
            $d = $Chart.data
            foreach ($f in @(
                @('Raised', 'raised'), @('New', 'new'), @('Active', 'active'), @('Closed', 'closed'), @('Closed without acknowledgement', 'unacknowledged')
            )) {
                $v = if ($d -is [System.Collections.IDictionary]) {
                    $d[$f[1]]
                } elseif ($d -and $d.PSObject.Properties[$f[1]]) { $d.PSObject.Properties[$f[1]].Value } else { $null }
                if ($null -ne $v) { , @($f[0], [string]$v) }
            }
        }
        'xy' {
            $labels = @($Chart.data.xAxis.labels)
            for ($i = 0; $i -lt $labels.Count; $i++) {
                , @([string]$labels[$i], ((@($Chart.data.series) | ForEach-Object { [string]@($_.values)[$i] }) -join ' / '))
            }
        }
        default { }
    })
    if ($rows.Count) {
        [void]$sb.Append('<div class="canvasRteResponsiveTable"><div class="tableWrapper"><table title="Table"><tbody>')
        foreach ($r in $rows) { [void]$sb.Append('<tr><td>' + (ConvertTo-SacHtmlText $r[0]) + '</td><td>' + (ConvertTo-SacHtmlText $r[1]) + '</td></tr>') }
        [void]$sb.Append('</tbody></table></div></div>')
    }
    else {
        [void]$sb.Append('<p><em>This chart is drawn by the iSOC Blueprint chart web part, which is not on this site yet.</em></p>')
    }
    return $sb.ToString()
}
