#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertTo-BpNumber

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Helpers/ConvertTo-BpNumber.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Mermaid chart parsing
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function ConvertTo-BpNumber {
    param([string] $Text)
    $n = 0.0
    if ([double]::TryParse($Text.Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)) {
        return $n
    }
    return $null
}
