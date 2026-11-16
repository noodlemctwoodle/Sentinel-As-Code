#Requires -Version 7.6

<#
.SYNOPSIS
    A KQL result cell as an integer, 0 when missing or not a number.

.DESCRIPTION
    KQL result cells arrive as strings from Invoke-AzOperationalInsightsQuery
    and as typed values from fixture files, so every numeric read goes through
    ConvertTo-GapInt or ConvertTo-GapDouble and every flag through ConvertTo-GapBool.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Conversion/ConvertTo-GapInt.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function ConvertTo-GapInt {
    param([object]$Value)
    if ($null -eq $Value) { return 0 }
    $d = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
        return [int][math]::Round($d)
    }
    return 0
}
