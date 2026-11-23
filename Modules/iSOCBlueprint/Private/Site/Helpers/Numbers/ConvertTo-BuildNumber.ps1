#Requires -Version 7.6

<#
.SYNOPSIS
    Parse a number that may arrive as text; 0 when it cannot.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Numbers/ConvertTo-BuildNumber.ps1
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

# ---- Health-check ports: estate, effectiveness, run health, maturity ----
function ConvertTo-BuildNumber {
    <#
    .SYNOPSIS
        Parse a number that may arrive as text; 0 when it cannot.

    .DESCRIPTION
        KQL result cells arrive as strings and fixtures carry typed values, so
        every number is parsed with the invariant culture rather than cast. A
        null or unparseable value gives 0.0.

    .PARAMETER Value
        The number, or the text to parse. Null gives 0.0.

    .OUTPUTS
        [double] The parsed number, or 0.0.
    #>
    [OutputType([double])]
    [CmdletBinding()]
    param($Value)
    if ($null -eq $Value) { return 0.0 }
    $d = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
        return $d
    }
    return 0.0
}
