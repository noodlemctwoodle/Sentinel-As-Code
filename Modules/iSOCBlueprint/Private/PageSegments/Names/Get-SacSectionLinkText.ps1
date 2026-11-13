#Requires -Version 7.6

<#
.SYNOPSIS
    The text a link to another section shows: the section's title when the Markdown wrote its file name, otherwise the text as written.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Names/Get-SacSectionLinkText.ps1
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

function Get-SacSectionLinkText {
    <#
    .SYNOPSIS
        The text a link to another section shows: the section's title when
        the Markdown wrote its file name, otherwise the text as written.

    .PARAMETER Text
        The link text.

    .PARAMETER SectionId
        The section the link points at.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [AllowNull()] [string] $Text, [Parameter(Mandatory)] [AllowEmptyString()] [string] $SectionId)

    if ([string]$Text -match '^\s*(?:\./)?\d{2}-[a-z0-9-]+\.md(?:#\S*)?\s*$') { return Get-SacSectionName -SectionId $SectionId }
    return [string]$Text
}
