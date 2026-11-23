#Requires -Version 7.6

<#
.SYNOPSIS
    Read one meter category's unit price, 0 when it has none.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Cost/Helpers/Get-CostUnitPrice.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, cost estimate
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-CostUnitPrice {
    <#
    .SYNOPSIS
        Read one meter category's unit price, 0 when it has none.

    .PARAMETER Prices
        The unit prices by category id.

    .PARAMETER Key
        The category id.

    .OUTPUTS
        [double]
    #>
    [OutputType([double])]
    [CmdletBinding()]
    param($Prices, [string] $Key)

    if ($Prices.ContainsKey($Key) -and $Prices[$Key]) { [double]$Prices[$Key] } else { 0.0 }
}
