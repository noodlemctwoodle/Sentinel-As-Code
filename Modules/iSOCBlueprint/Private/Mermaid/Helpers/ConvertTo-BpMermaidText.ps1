#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertTo-BpMermaidText

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Helpers/ConvertTo-BpMermaidText.ps1
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

function ConvertTo-BpMermaidText {
    # Mermaid label text: drop wrapping quotes, turn <br/> into a newline.
    param([AllowEmptyString()] [AllowNull()] [string] $Text)
    if ($null -eq $Text) { return $null }
    $t = $Text.Trim()
    if ($t.Length -ge 2 -and $t.StartsWith('"') -and $t.EndsWith('"')) { $t = $t.Substring(1, $t.Length - 2) }
    return ($t -replace '<br\s*/?>', "`n")
}
