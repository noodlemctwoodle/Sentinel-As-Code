#Requires -Version 7.6

<#
.SYNOPSIS
    Show the workspace region as the portal names it.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-WorkspaceRegion.ps1
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

# The region and the SKU as the portal and the dashboard name them. WithCode
# keeps the programmatic name beside it, in a code span, for the identity
# tables where someone may need to match it to the API or a template.
function Format-WorkspaceRegion {
    param($Region, [switch]$WithCode)
    $r = [string]$Region
    if (-not $r) { return '' }
    $name = Get-BlueprintRegionName $r
    if ($WithCode -and $name -cne $r) { return "$name (``$r``)" }
    if ($WithCode) { return "``$r``" }
    return $name
}
