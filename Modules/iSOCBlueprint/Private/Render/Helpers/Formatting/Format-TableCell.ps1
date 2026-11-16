#Requires -Version 7.6

<#
.SYNOPSIS
    Format one table cell, with thousands separators for numbers.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-TableCell.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

# A number cell the way every other figure on the page is written: a whole
# number with thousands separators, a fraction to two decimals. Only a .NET
# numeric type is formatted (text, already formatted or an identifier, passes
# through as it is), except in a GB column, which formats numeric text too.
function Format-TableCell($Value, [bool]$Identifier, [bool]$Gb = $false) {
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return Format-DateUtc $Value }
    if ($Gb -and -not $Identifier -and $Value -isnot [bool]) { return Format-BlueprintGb $Value }
    $isNumber = ($Value -is [decimal]) -or
        ($Value.GetType().IsPrimitive -and $Value -isnot [bool] -and $Value -isnot [char] -and $Value -isnot [IntPtr] -and $Value -isnot [UIntPtr])
    if ($isNumber -and -not $Identifier) {
        $d = [double]$Value
        if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { return [string]$Value }
        if ($d -eq [math]::Truncate($d)) { return Format-BlueprintCount $d }
        return Format-BlueprintNumber -Value $d -Decimals 2
    }
    return [string]$Value
}
