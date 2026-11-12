#Requires -Version 7.6

<#
.SYNOPSIS
    Format a MITRE technique for a table cell.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/MitreCoverage/Format-MitreTechniqueCell.ps1
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

function Format-MitreTechniqueCell {
    param([string]$Id, [bool]$Sub = $false)
    if (-not $Id) { return '' }
    $name = $techNameById[$Id]
    $urlId = if ($Sub) { $Id.Replace('.', '/') } else { $Id }
    if ($name) {
        return "[${Id}: $name](https://attack.mitre.org/techniques/$urlId/)"
    }
    return "[$Id](https://attack.mitre.org/techniques/$urlId/)"
}
