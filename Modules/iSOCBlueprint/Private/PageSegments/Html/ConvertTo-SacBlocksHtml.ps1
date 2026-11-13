#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertTo-SacBlocksHtml

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Html/ConvertTo-SacBlocksHtml.ps1
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

function ConvertTo-SacBlocksHtml {
    # HTML for blocks that stay inside one Text web part (lists, notes, tables).
    # A table cut at MaxTableRows is added whole to Tables as CSV, named from
    # the heading above it.
    param([object[]] $Blocks, [string] $FindingsListUrl, [int] $MaxTableRows, [string] $Id, [System.Collections.Generic.List[string]] $Warnings, [System.Collections.Generic.List[object]] $Tables, [string] $Heading = '')
    $sb = [System.Text.StringBuilder]::new()
    foreach ($b in @($Blocks)) {
        if ($null -eq $b) { continue }
        switch ([string]$b.type) {
            'heading' {
                $lvl = [int]$b.level
                $tag = if ($lvl -le 2) { 'h2' } elseif ($lvl -eq 3) { 'h3' } else { 'h4' }
                [void]$sb.Append("<$tag>" + (ConvertTo-SacRunsHtml -Runs @($b.text) -FindingsListUrl $FindingsListUrl) + "</$tag>")
            }
            'paragraph' { [void]$sb.Append('<p>' + (ConvertTo-SacRunsHtml -Runs @($b.text) -FindingsListUrl $FindingsListUrl) + '</p>') }
            'list' {
                $tag = if ($b.ordered) { 'ol' } else { 'ul' }
                $start = if ($b.ordered -and $b.start) { " start=`"$([int]$b.start)`"" } else { '' }
                [void]$sb.Append("<$tag$start>")
                foreach ($item in @($b.items)) {
                    [void]$sb.Append('<li>' + (ConvertTo-SacRunsHtml -Runs @($item.text) -FindingsListUrl $FindingsListUrl))
                    if (@($item.blocks).Count) { [void]$sb.Append((ConvertTo-SacBlocksHtml -Blocks @($item.blocks) -FindingsListUrl $FindingsListUrl -MaxTableRows $MaxTableRows -Id $Id -Warnings $Warnings -Tables $Tables -Heading $Heading)) }
                    [void]$sb.Append('</li>')
                }
                [void]$sb.Append("</$tag>")
            }
            'note' { [void]$sb.Append('<blockquote>' + (ConvertTo-SacBlocksHtml -Blocks @($b.blocks) -FindingsListUrl $FindingsListUrl -MaxTableRows $MaxTableRows -Id $Id -Warnings $Warnings -Tables $Tables -Heading $Heading) + '</blockquote>') }
            'table' {
                $csvUrl = $null
                $csvFile = $null
                if ($null -ne $Tables -and @($b.rows).Count -gt $MaxTableRows) {
                    $csvFile = Get-SacTableFileName -Id $Id -Heading $Heading -Taken @($Tables | ForEach-Object { $_.file })
                    $Tables.Add([ordered]@{ file = $csvFile; heading = $Heading; rows = @($b.rows).Count; csv = (ConvertTo-SacTableCsv -Table $b) })
                    $csvUrl = "$script:SacTablesUrl/$csvFile"
                }
                $t = ConvertTo-SacTableHtml -Table $b -MaxRows $MaxTableRows -FindingsListUrl $FindingsListUrl -CsvUrl $csvUrl
                if ($t.Truncated -gt 0) { $Warnings.Add("$Id : a table was capped at $MaxTableRows rows ($($t.Truncated) not shown)$(if ($csvFile) { "; every row is in tables/$csvFile" }).") }
                [void]$sb.Append($t.Html)
            }
            'code' { [void]$sb.Append('<pre>' + (ConvertTo-SacHtmlText ([string]$b.text)) + '</pre>') }
            'chart' { $Warnings.Add("$Id : a chart nested in a list or note is not shown.") }
            default { }
        }
    }
    return $sb.ToString()
}
