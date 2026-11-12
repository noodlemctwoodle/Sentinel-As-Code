#Requires -Version 7.6

<#
.SYNOPSIS
    Read a KQL dynamic bag as an ordered name-to-count map.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Overview/ConvertTo-BlueprintBag.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

# A KQL dynamic bag (ByClassification and friends) as an ordered name ->
# count map, whether it arrived as JSON text or as an object.
function ConvertTo-BlueprintBag {
    param($Value)
    $bag = [ordered]@{}
    if ($null -eq $Value) { return $bag }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $bag }
        try { $Value = $Value | ConvertFrom-Json } catch { return $bag }
        if ($null -eq $Value) { return $bag }
    }
    foreach ($prop in $Value.PSObject.Properties) { $bag[$prop.Name] = [long](ConvertTo-BlueprintNumber $prop.Value) }
    return $bag
}
