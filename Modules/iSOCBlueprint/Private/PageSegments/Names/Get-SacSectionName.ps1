#Requires -Version 7.6

<#
.SYNOPSIS
    A section's title for a link to it: '90-gap-analysis' -> 'Gap Analysis' (its title), or 'Gap analysis' when the title is unknown.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Names/Get-SacSectionName.ps1
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

function Get-SacSectionName {
    <#
    .SYNOPSIS
        A section's title for a link to it: '90-gap-analysis' -> 'Gap
        Analysis' (its title), or 'Gap analysis' when the title is unknown.

    .PARAMETER SectionId
        The section id, the file name without .md.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $SectionId)

    if ($script:SacSectionTitles -and $script:SacSectionTitles.ContainsKey($SectionId)) { return [string]$script:SacSectionTitles[$SectionId] }
    $words = (($SectionId -replace '^\d+-', '') -replace '-', ' ').Trim()
    if (-not $words) { return $SectionId }
    return $words.Substring(0, 1).ToUpperInvariant() + $words.Substring(1)
}
