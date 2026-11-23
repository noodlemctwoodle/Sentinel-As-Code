#Requires -Version 7.6

<#
.SYNOPSIS
    Turn a run's link target into a site URL, or $null when the link should become plain text.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Html/ConvertTo-SacSiteLink.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint page conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-SacSiteLink {
    <#
    .SYNOPSIS
        Turn a run's link target into a site URL, or $null when the link
        should become plain text.

    .PARAMETER Run
        One text run from the section model, with href and target.

    .PARAMETER FindingsListUrl
        Site-relative URL of the findings list.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Run,
        [Parameter(Mandatory)] [string] $FindingsListUrl
    )
    $target = $Run.target
    switch ([string]$target.kind) {
        'external' { return [string]$Run.href }
        'finding' { return "~site/$FindingsListUrl/AllItems.aspx?FilterField1=FindingId&amp;FilterValue1=$([string]$target.id)" }
        'section' {
            # SharePoint makes its own heading anchors, so the anchor is dropped;
            # the contents page has no page of its own.
            if ([string]$target.section -eq 'index') { return $null }
            return "~site/SitePages/$(Get-SacPageName -FileName ([string]$target.section)).aspx"
        }
        default { return $null }
    }
}
