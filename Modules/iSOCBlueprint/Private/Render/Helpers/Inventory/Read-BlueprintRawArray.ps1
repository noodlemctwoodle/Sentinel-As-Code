#Requires -Version 7.6

<#
.SYNOPSIS
    Read one JSON file from _raw/ as an array.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Inventory/Read-BlueprintRawArray.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Read-BlueprintRawArray {
    <#
    .SYNOPSIS
        Read one JSON file from _raw/ as an array.

    .DESCRIPTION
        The array-shaped reader: use it when the caller intends to iterate the
        result via ForEach-Object. Returns an empty array when the underlying file
        is missing or empty, rather than the one-element-null-array a naive
        array-wrap of Read-BlueprintRaw produces. The phantom all-null row that
        iterating a one-element-null-array yields (and PowerShell's own quirk that
        returns 0 for the Count property of a null reference) is the bug this helper
        prevents.

    .PARAMETER Name
        The file name under $script:RawRoot.

    .OUTPUTS
        [object[]], empty when there is no data.
    #>
    [OutputType([object[]])]
    [CmdletBinding()]
    param([string]$Name)
    $value = Read-BlueprintRaw $Name
    if ($null -eq $value) { return , @() }
    return @($value)
}
