#Requires -Version 7.6

<#
.SYNOPSIS
    A count with thousands separators: 13858711766 reads 13,858,711,766.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Format/Numbers/Format-BlueprintCount.ps1
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

function Format-BlueprintCount {
    <#
    .SYNOPSIS
        A count with thousands separators: 13858711766 reads 13,858,711,766.

    .PARAMETER Value
        A number or numeric string. A fraction is rounded to a whole number.

    .OUTPUTS
        [string]; the input as text when it is not a number, '' for $null.
    #>
    [CmdletBinding()]
    param([AllowNull()] $Value)
    $d = ConvertTo-BlueprintDouble $Value
    if ($null -eq $d) { return $(if ($null -eq $Value) { '' } else { [string]$Value }) }
    [math]::Round($d, [System.MidpointRounding]::AwayFromZero).ToString('#,0', $script:BlueprintInvariant)
}
