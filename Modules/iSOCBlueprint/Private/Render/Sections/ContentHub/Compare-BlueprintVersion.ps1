#Requires -Version 7.6

<#
.SYNOPSIS
    Compare two dotted versions numerically.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/ContentHub/Compare-BlueprintVersion.ps1
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

# Dotted versions compare numerically (3.0.10 is newer than 3.0.9); a
# version [version] cannot read compares as text.
function Compare-BlueprintVersion([string]$A, [string]$B) {
    $va = $null; $vb = $null
    if ([version]::TryParse($A, [ref]$va) -and [version]::TryParse($B, [ref]$vb)) { return $va.CompareTo($vb) }
    return [string]::CompareOrdinal($A, $B)
}
