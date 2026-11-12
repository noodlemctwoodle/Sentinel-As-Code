#Requires -Version 7.6

<#
.SYNOPSIS
    Read one _raw JSON file as an array, empty when absent.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Raw/Read-SiteRawArray.ps1
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

function Read-SiteRawArray {
    <#
    .SYNOPSIS
        Array-shaped reader: an empty array when the file is missing or
        empty, never the one-element-null array that @(Read-SiteRaw x) gives
        (whose Count is 1 and which yields a phantom all-null row). Same
        contract as Read-SiteRawArray in Convert-SentinelInventoryToMarkdown.ps1.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)

    $value = Read-SiteRaw $Name
    if ($null -eq $value) { return , @() }
    return , @($value)
}
