#Requires -Version 7.6

<#
.SYNOPSIS
    A total over the lookback as a 30-day figure.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Window/ConvertTo-GapPer30Days.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# A total over the lookback as a 30-day figure.
function ConvertTo-GapPer30Days([double]$Value, $Inventory) { $Value * 30.0 / (Get-GapWindow $Inventory).Days }
