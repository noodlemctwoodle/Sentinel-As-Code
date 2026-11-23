#Requires -Version 7.6

<#
.SYNOPSIS
    Escape text for HTML.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Output/ConvertTo-HtmlText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-HtmlText {
    <#
    .SYNOPSIS
        Escape text for HTML.

    .DESCRIPTION
        Replaces &, <, > and " with their entities. Empty or null text gives an
        empty string.

    .PARAMETER Text
        The text to escape.

    .OUTPUTS
        [string] The escaped text.
    #>
    [CmdletBinding()]
    param([string] $Text)
    if (-not $Text) { return '' }
    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}
