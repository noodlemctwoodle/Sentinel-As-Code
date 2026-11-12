#Requires -Version 7.6

<#
.SYNOPSIS
    Show the workspace SKU as the portal names it.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-WorkspaceSku.ps1
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

function Format-WorkspaceSku {
    param($Sku, [switch]$WithCode)
    $k = [string]$Sku
    if (-not $k) { return '' }
    $name = Get-BlueprintSkuName $k
    if ($WithCode -and $name -cne $k) { return "$name (``$k``)" }
    if ($WithCode) { return "``$k``" }
    return $name
}
