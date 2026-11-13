#Requires -Version 7.6

<#
.SYNOPSIS
    Get-BpSlug

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/Get-BpSlug.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-BpSlug {
    # GitHub's heading anchor: lower case, punctuation dropped, spaces to '-'.
    param([string] $Text)
    $s = $Text.ToLowerInvariant() -replace '[^\p{L}\p{Nd}\s_-]', '' -replace '\s', '-'
    return $s
}
