#Requires -Version 7.6

<#
.SYNOPSIS
    Loads the functions that convert a Blueprint section into SharePoint page
    segments.

.DESCRIPTION
    Dot-source this file to define ConvertTo-SharePointPageSegments and the
    functions it uses. They live one per file under
    Modules/iSOCBlueprint/Private/PageSegments:

      ConvertTo-SharePointPageSegments.ps1   the converter, with the full
                                             description of what a page becomes
      Names/    page names, section titles and link text
      Html/     runs, blocks, links and file mentions as page HTML
      Tables/   a table as HTML, and as the CSV for a cut table
      Charts/   a chart as web part data, and its fallback HTML
      Data/     the file name pattern and the tables URL

.NOTES
    File:         Modules/iSOCBlueprint/Engine/SharePoint/Private/ConvertTo-SharePointPageSegments.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-08
    Version:      0.5.0
    Last Updated: 2026-11-13
    Requires:     PowerShell 7.6+

    This file loads functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# The functions and values (the module's own Private/PageSegments, three
# folders up from here), defined in the caller's scope.
$pageSegmentsRoot = Join-Path $PSScriptRoot '..' '..' '..' 'Private' 'PageSegments'
foreach ($pageSegmentsFile in Get-ChildItem -LiteralPath $pageSegmentsRoot -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
    . $pageSegmentsFile.FullName
}
Remove-Variable -Name pageSegmentsFile, pageSegmentsRoot -WhatIf:$false
