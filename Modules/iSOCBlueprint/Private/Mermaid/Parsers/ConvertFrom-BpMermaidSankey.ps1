#Requires -Version 7.6

<#
.SYNOPSIS
    Parse the body of a Mermaid sankey chart into its links.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Parsers/ConvertFrom-BpMermaidSankey.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Mermaid chart parsing
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertFrom-BpMermaidSankey {
    <#
    .SYNOPSIS
        Parse the body of a Mermaid sankey chart into its links.

    .DESCRIPTION
        Each line is three comma-separated fields: source, target and value.
        A field can be double-quoted, with "" for a quote inside it. A line
        without exactly three fields, or whose third is not a number, is
        skipped.

    .PARAMETER Body
        The diagram's lines after its header line.

    .OUTPUTS
        [ordered] kind ('sankey'), title ($null) and data: links (source,
        target and value).
    #>
    [CmdletBinding()]
    param([string[]] $Body)
    $links = foreach ($l in $Body) {
        $t = $l.Trim()
        if (-not $t) { continue }
        $fields = @([regex]::Matches($t, '"((?:[^"]|"")*)"|([^,]+)') | ForEach-Object {
                if ($_.Groups[1].Success) { $_.Groups[1].Value.Replace('""', '"') } else { $_.Groups[2].Value.Trim() }
            })
        if ($fields.Count -ne 3) { continue }
        $v = ConvertTo-BpNumber $fields[2]
        if ($null -eq $v) { continue }
        [ordered]@{ source = $fields[0]; target = $fields[1]; value = $v }
    }
    return [ordered]@{ kind = 'sankey'; title = $null; data = [ordered]@{ links = @($links) } }
}
