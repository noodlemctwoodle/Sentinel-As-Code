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
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Read-BlueprintRawArray([string]$Name) {
    # Array-shaped reader. Use this when the caller intends to iterate the
    # result via ForEach-Object. Returns an empty array when the underlying
    # file is missing or empty, rather than the one-element-null-array a
    # naive array-wrap of Read-Raw produces. The phantom all-null row that
    # iterating a one-element-null-array yields (and PowerShells own quirk
    # that returns 0 for the Count property of a null reference) is the bug
    # this helper prevents.
    $value = Read-BlueprintRaw $Name
    if ($null -eq $value) { return ,@() }
    return @($value)
}
