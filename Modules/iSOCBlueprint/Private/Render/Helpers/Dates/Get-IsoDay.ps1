#Requires -Version 7.6

<#
.SYNOPSIS
    Return the UTC yyyy-MM-dd of a date-like value.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Dates/Get-IsoDay.ps1
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

function Get-IsoDay {
    <#
    .SYNOPSIS
        Return the UTC yyyy-MM-dd of a date-like value.

    .DESCRIPTION
        The form a sort or a machine-readable field wants, never page text. A null
        value gives an empty string; a value that does not parse comes back as
        given, as a string.

    .PARAMETER Value
        A [datetime] or date text, read through ConvertTo-UtcDateTime.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
    param($Value)
    if ($null -eq $Value) { return '' }
    $utc = ConvertTo-UtcDateTime $Value
    if ($null -eq $utc) { return [string]$Value }
    return $utc.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
}
