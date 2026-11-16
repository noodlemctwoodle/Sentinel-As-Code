#Requires -Version 7.6

<#
.SYNOPSIS
    A workspace SKU as the dashboard's Overview names it: CapacityReservation reads Commitment tier. An SKU not in the list is returned as given.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Format/Names/Get-BlueprintSkuName.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Blueprint text formatting
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-BlueprintSkuName {
    <#
    .SYNOPSIS
        A workspace SKU as the dashboard's Overview names it:
        CapacityReservation reads Commitment tier. An SKU not in the list
        is returned as given.

    .PARAMETER Sku
        The SKU name from the workspace's properties.sku.name.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    param([AllowNull()] [AllowEmptyString()] [string] $Sku)
    if (-not $Sku) { return [string]$Sku }
    foreach ($k in $script:BlueprintSkuName.Keys) { if ($k -ieq $Sku) { return $script:BlueprintSkuName[$k] } }
    $Sku
}
