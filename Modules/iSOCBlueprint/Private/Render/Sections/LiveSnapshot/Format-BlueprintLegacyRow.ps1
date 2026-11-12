#Requires -Version 7.6

<#
.SYNOPSIS
    Build one row of the legacy-features table.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/LiveSnapshot/Format-BlueprintLegacyRow.ps1
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

# Legacy and deprecated features still in use, one row each, read from the
# same captures their pages use. A capture missing from an older snapshot
# shows as Not captured rather than as not in use.
function Format-BlueprintLegacyRow([string]$Feature, $Count, [bool]$Captured, [string]$Evidence, [string]$Where) {
    [pscustomobject]@{
        Feature  = $Feature
        Status   = $(if (-not $Captured) { 'Not captured' } elseif ([double]$Count -gt 0) { 'In use' } else { 'Not in use' })
        Evidence = $(if ($Captured) { $Evidence } else { '' })
        Where    = $Where
    }
}
