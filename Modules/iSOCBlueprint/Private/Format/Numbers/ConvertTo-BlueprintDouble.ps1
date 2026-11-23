#Requires -Version 7.6

<#
.SYNOPSIS
    Convert a number or numeric string to a double, or $null when it is neither

.NOTES
    File:         Modules/iSOCBlueprint/Private/Format/Numbers/ConvertTo-BlueprintDouble.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Blueprint text formatting
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-BlueprintDouble {
    <#
    .SYNOPSIS
        Convert a number or numeric string to a double, or $null when it is
        neither.

    .DESCRIPTION
        A double, int, long, decimal or single is returned as a double. Any
        other value is trimmed as a string and parsed with the invariant
        culture; an empty or unparseable string gives $null.

    .PARAMETER Value
        The number or numeric string. $null gives $null.

    .OUTPUTS
        [double] The number, or $null.
    #>
    [CmdletBinding()]
    param([AllowNull()] $Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [double] -or $Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or $Value -is [single]) { return [double]$Value }
    $s = ([string]$Value).Trim()
    if (-not $s) { return $null }
    $d = 0.0
    if ([double]::TryParse($s, [System.Globalization.NumberStyles]::Float, $script:BlueprintInvariant, [ref]$d)) { return $d }
    $null
}
