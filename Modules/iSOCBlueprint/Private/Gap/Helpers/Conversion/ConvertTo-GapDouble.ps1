#Requires -Version 7.6

<#
.SYNOPSIS
    A KQL result cell as a double, 0.0 when missing or not a number.

.DESCRIPTION
    KQL result cells arrive as strings from Invoke-AzOperationalInsightsQuery
    and as typed values from fixture files, so every numeric read goes through
    ConvertTo-GapInt or ConvertTo-GapDouble and every flag through ConvertTo-GapBool.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Conversion/ConvertTo-GapDouble.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function ConvertTo-GapDouble {
    <#
    .SYNOPSIS
        A KQL result cell as a double, 0.0 when missing or not a number.

    .DESCRIPTION
        The cell's text is parsed as a float with the invariant culture.
        $null and text that does not parse give 0.0.

    .PARAMETER Value
        The cell to read.

    .OUTPUTS
        [double]
    #>
    [CmdletBinding()]
    param([object]$Value)
    if ($null -eq $Value) { return 0.0 }
    $d = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
        return $d
    }
    return 0.0
}
