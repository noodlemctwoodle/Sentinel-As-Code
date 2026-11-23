#Requires -Version 7.6

<#
.SYNOPSIS
    A total over the lookback as a 30-day figure.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Window/ConvertTo-GapPer30Day.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function ConvertTo-GapPer30Day {
    <#
    .SYNOPSIS
        A total over the lookback as a 30-day figure.

    .DESCRIPTION
        The total is scaled by 30 over the lookback's length in days
        (Get-GapWindow), so a threshold set per 30 days holds whatever the
        lookback.

    .PARAMETER Value
        The total over the lookback.

    .PARAMETER Inventory
        The gap inventory, which carries the lookback window.

    .OUTPUTS
        [double]
    #>
    [CmdletBinding()]
    param([double]$Value, $Inventory)
    $Value * 30.0 / (Get-GapWindow $Inventory).Days
}
