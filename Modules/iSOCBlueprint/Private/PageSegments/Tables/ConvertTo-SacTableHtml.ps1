#Requires -Version 7.6

<#
.SYNOPSIS
    SharePoint editor table markup for one table block, capping the number of body rows.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Tables/ConvertTo-SacTableHtml.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, SharePoint page conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function ConvertTo-SacTableHtml {
    <#
    .SYNOPSIS
        SharePoint editor table markup for one table block, capping the
        number of body rows.

    .PARAMETER Table
        A table block from the section model.

    .PARAMETER MaxRows
        Maximum body rows to keep. Extra rows are replaced by one note row.

    .PARAMETER FindingsListUrl
        Site-relative URL of the findings list.

    .PARAMETER CsvUrl
        Where the whole table is as CSV, for the note under a cut table.

    .OUTPUTS
        [pscustomobject] Html (string) and Truncated (int, rows dropped).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] $Table,
        [Parameter(Mandatory)] [int] $MaxRows,
        [Parameter(Mandatory)] [string] $FindingsListUrl,
        [string] $CsvUrl
    )

    $out = [System.Text.StringBuilder]::new()
    [void]$out.Append('<div class="canvasRteResponsiveTable"><div class="tableWrapper"><table title="Table"><tbody>')

    $columns = @($Table.columns)
    $headers = @($columns | ForEach-Object { ConvertTo-SacRunsHtml -Runs @($_.text) -FindingsListUrl $FindingsListUrl })
    # The renderer uses '| | |' headers for key/value tables. An all-empty
    # header row would show as a blank bold band.
    if (@($headers | Where-Object { $_.Trim() }).Count) {
        [void]$out.Append('<tr>')
        foreach ($h in $headers) { [void]$out.Append("<td><strong>$h</strong></td>") }
        [void]$out.Append('</tr>')
    }

    $rows = @($Table.rows)
    $dropped = [math]::Max(0, $rows.Count - $MaxRows)
    foreach ($row in ($rows | Select-Object -First $MaxRows)) {
        [void]$out.Append('<tr>')
        foreach ($cell in @($row)) { [void]$out.Append('<td>' + (ConvertTo-SacRunsHtml -Runs @($cell) -FindingsListUrl $FindingsListUrl) + '</td>') }
        [void]$out.Append('</tr>')
    }
    if ($dropped -gt 0) {
        $span = [math]::Max($columns.Count, 1)
        $csvText = if ($CsvUrl) { "Every row is in <a href=`"$CsvUrl`">this table as a CSV file</a>, which opens in Excel, and in" } else { 'The full table, with a filter, is in' }
        [void]$out.Append("<tr><td colspan=`"$span`"><em>$dropped more rows not shown here. $csvText this section on the <a href=`"~site/SitePages/Dashboard.aspx`">dashboard</a>'s Sections tab$(if ($CsvUrl) { ', with a filter' }).</em></td></tr>")
    }
    [void]$out.Append('</tbody></table></div></div>')
    return [pscustomobject]@{ Html = $out.ToString(); Truncated = $dropped }
}
