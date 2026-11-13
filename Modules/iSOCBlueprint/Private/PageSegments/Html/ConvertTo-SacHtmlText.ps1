#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertTo-SacHtmlText

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Html/ConvertTo-SacHtmlText.ps1
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

function ConvertTo-SacHtmlText {
    param([AllowEmptyString()] [AllowNull()] [string] $Text)
    if (-not $Text) { return '' }
    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}
