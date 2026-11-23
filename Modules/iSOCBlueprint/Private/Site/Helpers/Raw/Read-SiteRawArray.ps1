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
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Read-SiteRawArray {
    <#
    .SYNOPSIS
        Read one _raw JSON file as an array, empty when it is absent or empty.

    .DESCRIPTION
        An empty array is returned when the file is missing or empty, never the
        one-element array holding $null that @(Read-SiteRaw x) gives, whose
        Count is 1 and which yields a phantom all-null row. The result is
        returned wrapped so that PowerShell does not unroll it. Same contract as
        Read-BlueprintRawArray in the renderer (Private/Render).

    .PARAMETER Name
        The file name within the raw folder, passed to Read-SiteRaw.

    .OUTPUTS
        [object[]] The items of the file, or an empty array.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)

    $value = Read-SiteRaw $Name
    if ($null -eq $value) { return , @() }
    return , @($value)
}
