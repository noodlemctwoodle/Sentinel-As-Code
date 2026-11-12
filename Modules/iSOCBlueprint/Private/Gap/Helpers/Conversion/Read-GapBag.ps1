#Requires -Version 7.6

<#
.SYNOPSIS
    A KQL dynamic bag as a name to integer map.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Conversion/Read-GapBag.ps1
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

# A KQL dynamic bag (ByClassification and friends) as a name -> int map.
function Read-GapBag {
    param([object]$Value)
    $bag = @{}
    if ($null -eq $Value) { return $bag }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $bag }
        try { $Value = $Value | ConvertFrom-Json -Depth 8 } catch { return $bag }
        if ($null -eq $Value) { return $bag }
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($k in $Value.Keys) { $bag[[string]$k] = ConvertTo-GapInt $Value[$k] }
        return $bag
    }
    foreach ($p in $Value.PSObject.Properties) { $bag[$p.Name] = ConvertTo-GapInt $p.Value }
    return $bag
}
