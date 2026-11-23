#Requires -Version 7.6

<#
.SYNOPSIS
    A number with thousands separators and a fixed number of decimal places: 1963.4 reads 1,963.40 at two places.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Format/Numbers/Format-BlueprintNumber.ps1
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

function Format-BlueprintNumber {
    <#
    .SYNOPSIS
        A number with thousands separators and a fixed number of decimal
        places: 1963.4 reads 1,963.40 at two places.

    .PARAMETER Value
        A number or numeric string.

    .PARAMETER Decimals
        Decimal places, 0 to 6. Defaults to 2.

    .OUTPUTS
        [string]; the input as text when it is not a number, '' for $null.
    #>
    [CmdletBinding()]
    param([AllowNull()] $Value, [ValidateRange(0, 6)] [int] $Decimals = 2)
    $d = ConvertTo-BlueprintDouble $Value
    if ($null -eq $d) { return $(if ($null -eq $Value) { '' } else { [string]$Value }) }
    $fmt = if ($Decimals -gt 0) { '#,0.' + ('0' * $Decimals) } else { '#,0' }
    [math]::Round($d, $Decimals, [System.MidpointRounding]::AwayFromZero).ToString($fmt, $script:BlueprintInvariant)
}
