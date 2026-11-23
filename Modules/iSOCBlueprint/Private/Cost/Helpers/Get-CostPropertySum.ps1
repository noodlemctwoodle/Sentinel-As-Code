#Requires -Version 7.6

<#
.SYNOPSIS
    Sum a property over a list, 0 for an empty one.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Cost/Helpers/Get-CostPropertySum.ps1
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

function Get-CostPropertySum {
    <#
    .SYNOPSIS
        Sum a property over a list, 0 for an empty one.

    .DESCRIPTION
        Measure-Object returns nothing to read a Sum from for an empty list,
        so the sum is taken by hand.

    .PARAMETER Items
        The list; $null items are skipped.

    .PARAMETER Property
        The property to add up.

    .OUTPUTS
        [double]
    #>
    [CmdletBinding()]
    param($Items, [string] $Property)

    $t = 0.0
    foreach ($i in @($Items)) { if ($null -ne $i) { $t += [double]$i.$Property } }
    $t
}
