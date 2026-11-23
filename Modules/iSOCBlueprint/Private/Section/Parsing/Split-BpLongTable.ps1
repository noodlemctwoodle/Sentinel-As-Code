#Requires -Version 7.6

<#
.SYNOPSIS
    Cut every pipe table longer than $script:BpTableChunkRows rows into chunks Markdig can parse.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Parsing/Split-BpLongTable.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Split-BpLongTable {
    <#
    .SYNOPSIS
        Cut every pipe table longer than $script:BpTableChunkRows rows into
        chunks Markdig can parse.

    .DESCRIPTION
        Each chunk after the first repeats the table's header and separator
        lines and follows a $script:BpTableContinues line, which
        Join-BpTableChunk uses to join the chunks back into one table.
        Lines inside a fenced code block are left alone, and so are tables
        that fit; Markdown with no long table comes back unchanged.

    .PARAMETER Markdown
        The section's Markdown.

    .OUTPUTS
        [string] The Markdown, with long tables cut.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Markdown)

    $lines = $Markdown -split '\r?\n'
    $out = [System.Collections.Generic.List[string]]::new()
    $inFence = $false
    $cut = $false
    $i = 0
    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        if ($line -match '^\s*(```|~~~)') { $inFence = -not $inFence; $out.Add($line); $i++; continue }
        $isTable = -not $inFence -and $line -match '^\|' -and ($i + 1) -lt $lines.Count -and
            $lines[$i + 1] -match '^\|(\s*:?-+:?\s*\|)+\s*$'
        if (-not $isTable) { $out.Add($line); $i++; continue }

        $header = $line
        $separator = $lines[$i + 1]
        $j = $i + 2
        $body = [System.Collections.Generic.List[string]]::new()
        while ($j -lt $lines.Count -and $lines[$j] -match '^\|') { $body.Add($lines[$j]); $j++ }
        if ($body.Count -gt $script:BpTableChunkRows) { $cut = $true }
        for ($start = 0; $start -lt [Math]::Max($body.Count, 1); $start += $script:BpTableChunkRows) {
            if ($start -gt 0) {
                $out.Add('')
                $out.Add($script:BpTableContinues)
                $out.Add('')
            }
            $out.Add($header)
            $out.Add($separator)
            $end = [Math]::Min($start + $script:BpTableChunkRows, $body.Count)
            for ($k = $start; $k -lt $end; $k++) { $out.Add($body[$k]) }
        }
        $i = $j
    }
    if (-not $cut) { return $Markdown }
    return ($out -join "`n")
}
