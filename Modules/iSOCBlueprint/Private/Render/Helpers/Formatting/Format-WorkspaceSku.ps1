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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-WorkspaceSku {
    <#
    .SYNOPSIS
        Show the workspace SKU as the portal names it.

    .DESCRIPTION
        Returns an empty string when Sku is empty. The name comes from
        Get-BlueprintSkuName. WithCode keeps the programmatic name beside it, in a
        code span, for the identity tables where someone may need to match it to the
        API or a template.

    .PARAMETER Sku
        The SKU code.

    .PARAMETER WithCode
        Add the SKU code, in code formatting, after the name. When the name is the
        same as the code only the code is shown.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
    param($Sku, [switch]$WithCode)
    $k = [string]$Sku
    if (-not $k) { return '' }
    $name = Get-BlueprintSkuName $k
    if ($WithCode -and $name -cne $k) { return "$name (``$k``)" }
    if ($WithCode) { return "``$k``" }
    return $name
}
