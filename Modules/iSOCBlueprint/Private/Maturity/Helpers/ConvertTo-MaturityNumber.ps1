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
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Maturity Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function ConvertTo-MaturityNumber {
    <#
    .SYNOPSIS
        Parse a number that may arrive as a string (KQL cells) or a typed
        value (fixtures). Returns 0 when it cannot be parsed.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)] [AllowNull()] $Value)
    if ($null -eq $Value) { return 0.0 }
    if ($Value -is [bool]) { return $(if ($Value) { 1.0 } else { 0.0 }) }
    $d = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return 0.0
}
