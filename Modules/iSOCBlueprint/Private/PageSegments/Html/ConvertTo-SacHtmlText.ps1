#Requires -Version 7.6

<#
.SYNOPSIS
    Escape text for HTML: ampersands, angle brackets and double quotes become entities.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Html/ConvertTo-SacHtmlText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint page conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-SacHtmlText {
    <#
    .SYNOPSIS
        Escape text for HTML: ampersands, angle brackets and double quotes
        become entities.

    .PARAMETER Text
        The text to escape. Empty or $null gives an empty string.

    .OUTPUTS
        [string] The escaped text.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()] [AllowNull()] [string] $Text)
    if (-not $Text) { return '' }
    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}
