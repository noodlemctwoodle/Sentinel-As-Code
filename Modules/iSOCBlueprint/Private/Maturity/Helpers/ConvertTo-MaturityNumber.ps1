#Requires -Version 7.6

<#
.SYNOPSIS
    Parse a number that may arrive as a string or a typed value.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Maturity/Helpers/ConvertTo-MaturityNumber.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.3
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Maturity Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-MaturityNumber {
    <#
    .SYNOPSIS
        Parse a number that may arrive as a string (KQL cells) or a typed value
        (fixtures).

    .DESCRIPTION
        Null and a value that cannot be parsed give 0.0. A boolean gives 1.0 for
        true and 0.0 for false. Text is parsed with the invariant culture.

    .PARAMETER Value
        The number, or the text or boolean to convert.

    .OUTPUTS
        [double] The number.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)] [AllowNull()] $Value)
    if ($null -eq $Value) { return 0.0 }
    if ($Value -is [bool]) { return $(if ($Value) { 1.0 } else { 0.0 }) }
    $d = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
        return $d
    }
    return 0.0
}
