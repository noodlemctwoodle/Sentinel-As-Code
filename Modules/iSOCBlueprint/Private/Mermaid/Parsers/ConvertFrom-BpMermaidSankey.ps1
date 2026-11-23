#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertFrom-BpMermaidSankey

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Parsers/ConvertFrom-BpMermaidSankey.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Mermaid chart parsing
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertFrom-BpMermaidSankey {
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
