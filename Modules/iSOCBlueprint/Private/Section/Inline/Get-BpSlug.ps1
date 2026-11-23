#Requires -Version 7.6

<#
.SYNOPSIS
    Make the anchor GitHub gives a Markdown heading

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/Get-BpSlug.ps1
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

function Get-BpSlug {
    <#
    .SYNOPSIS
        Make the anchor GitHub gives a Markdown heading: lower case,
        punctuation dropped, spaces turned into hyphens.

    .DESCRIPTION
        The text is lower-cased with the invariant culture, characters other
        than letters, decimal digits, whitespace, underscores and hyphens are
        dropped, and each whitespace character becomes a hyphen.

    .PARAMETER Text
        The heading text.

    .OUTPUTS
        [string] The anchor.
    #>
    [CmdletBinding()]
    param([string] $Text)
    $s = $Text.ToLowerInvariant() -replace '[^\p{L}\p{Nd}\s_-]', '' -replace '\s', '-'
    return $s
}
