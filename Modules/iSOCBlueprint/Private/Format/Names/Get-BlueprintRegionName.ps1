#Requires -Version 7.6

<#
.SYNOPSIS
    An Azure region by the name the portal shows: uksouth reads UK South. A region not in the list is returned as given.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Format/Names/Get-BlueprintRegionName.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Blueprint text formatting
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-BlueprintRegionName {
    <#
    .SYNOPSIS
        An Azure region by the name the portal shows: uksouth reads UK
        South. A region not in the list is returned as given.

    .PARAMETER Region
        The region's programmatic name (any case, spaces ignored).

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    param([AllowNull()] [AllowEmptyString()] [string] $Region)
    if (-not $Region) { return [string]$Region }
    $key = ($Region -replace '\s', '').ToLowerInvariant()
    if ($script:BlueprintRegionName.ContainsKey($key)) { return $script:BlueprintRegionName[$key] }
    $Region
}
