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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Measure-Count {
    <#
    .SYNOPSIS
        Count the items in a value that may be null, a scalar or a collection.

    .DESCRIPTION
        Null gives 0. An array counts its items that are not null. An object
        with a value property counts the items of that property (a value-wrapped
        payload). Anything else counts as the items of @($Data).

    .PARAMETER Data
        The value to count: null, an array, an object with a value property, or
        a single item.

    .OUTPUTS
        [int] The number of items.
    #>
    [CmdletBinding()]
    param($Data)
    if ($null -eq $Data) { return 0 }
    if ($Data -is [System.Array]) { return @($Data | Where-Object { $null -ne $_ }).Count }
    if ($Data.PSObject.Properties.Name -contains 'value') { return @($Data.value).Count }
    return @($Data).Count
}
