#Requires -Version 7.6

<#
.SYNOPSIS
    Count the items in a value that may be null, a scalar or a collection.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Numbers/Measure-Count.ps1
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

function Measure-Count {
    <# Count items in a list or value-wrapped payload, tolerant of $null. #>
    param($Data)
    if ($null -eq $Data) { return 0 }
    if ($Data -is [System.Array]) { return @($Data | Where-Object { $null -ne $_ }).Count }
    if ($Data.PSObject.Properties.Name -contains 'value') { return @($Data.value).Count }
    return @($Data).Count
}
