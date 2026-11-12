#Requires -Version 7.6

<#
.SYNOPSIS
    The list items of a section block.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Sections/Get-SectionListItems.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SectionListItems {
    # A list's items, nested lists flattened in reading order.
    param($List)
    foreach ($item in @($List.items)) {
        ConvertTo-SectionRunsHtml @($item.text)
        foreach ($b in @($item.blocks)) { if ($b -and [string]$b.type -eq 'list') { Get-SectionListItems $b } }
    }
}
