#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertTo-BlueprintDouble

.NOTES
    File:         Modules/iSOCBlueprint/Private/Format/Numbers/ConvertTo-BlueprintDouble.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.1
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
        A number from a number or a numeric string (invariant culture), or
        $null when it is neither.
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
