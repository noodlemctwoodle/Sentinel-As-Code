#Requires -Version 7.6

<#
.SYNOPSIS
    Write the lead of the top-findings sentence.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-TopFindingsLead.ps1
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

# The lead of the top-findings sentence: how many of how many are shown.
function Format-TopFindingsLead([int]$Shown, [int]$Total) {
    $of = Format-BlueprintPlural $Total 'finding'
    if ($Total -eq 1) { return 'The one finding,' }
    if ($Shown -ge $Total) { return "All $of, each" }
    if ($Shown -eq 1) { return "The most severe of $of," }
    return "The $Shown most severe of $of, each"
}
