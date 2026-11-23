#Requires -Version 7.6

<#
.SYNOPSIS
    The list items of a section block.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Sections/Get-SectionListItem.ps1
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

function Get-SectionListItem {
    <#
    .SYNOPSIS
        The items of a section's list block, with nested lists flattened in
        reading order.

    .DESCRIPTION
        Each item is written as HTML through ConvertTo-SectionRunsHtml, and the
        items of a list nested in an item follow that item.

    .PARAMETER List
        A list block of the section model, whose items each hold text and
        optional nested blocks.

    .OUTPUTS
        [string] The HTML of each item, in reading order.
    #>
    [CmdletBinding()]
    param($List)
    foreach ($item in @($List.items)) {
        ConvertTo-SectionRunsHtml @($item.text)
        foreach ($b in @($item.blocks)) { if ($b -and [string]$b.type -eq 'list') { Get-SectionListItem $b } }
    }
}
