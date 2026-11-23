#Requires -Version 7.6

<#
.SYNOPSIS
    Split a Mermaid bracketed list into its items.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Helpers/ConvertFrom-BpMermaidList.ps1
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

function ConvertFrom-BpMermaidList {
    <#
    .SYNOPSIS
        Split a Mermaid bracketed list into its items: [a, "b c", 3] gives
        a, b c and 3.

    .PARAMETER Text
        The list text, with or without the square brackets. Items are
        separated by commas; a double-quoted item keeps its commas and loses
        its quotes, and any other item is trimmed.

    .OUTPUTS
        [string[]] The items, in order.
    #>
    [CmdletBinding()]
    param([string] $Text)
    $inner = $Text.Trim().TrimStart('[').TrimEnd(']')
    return @([regex]::Matches($inner, '"([^"]*)"|([^,\s][^,]*)') | ForEach-Object {
            if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value.Trim() }
        })
}
