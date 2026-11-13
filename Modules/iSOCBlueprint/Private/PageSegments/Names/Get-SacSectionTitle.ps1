#Requires -Version 7.6

<#
.SYNOPSIS
    Clean a section title for use as a page title.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Names/Get-SacSectionTitle.ps1
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

function Get-SacSectionTitle {
    <#
    .SYNOPSIS
        Clean a section title for use as a page title.

    .DESCRIPTION
        Removes the '(TOC x.y)' suffix some renderer titles carry, which is a
        cross-reference to the formal configuration document and noise in a
        page title.

    .PARAMETER Title
        The section title.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Title)

    return ($Title -replace '\s*\(TOC[^)]*\)\s*$', '').Trim()
}
