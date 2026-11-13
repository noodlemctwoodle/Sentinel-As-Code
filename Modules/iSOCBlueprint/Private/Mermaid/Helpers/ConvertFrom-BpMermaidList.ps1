#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertFrom-BpMermaidList

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Helpers/ConvertFrom-BpMermaidList.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, Mermaid chart parsing
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function ConvertFrom-BpMermaidList {
    # "[a, "b c", 3]" -> @('a', 'b c', '3')
    param([string] $Text)
    $inner = $Text.Trim().TrimStart('[').TrimEnd(']')
    return @([regex]::Matches($inner, '"([^"]*)"|([^,\s][^,]*)') | ForEach-Object {
            if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value.Trim() }
        })
}
