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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-WorkspaceRegion {
    <#
    .SYNOPSIS
        Show the workspace region as the portal names it.

    .DESCRIPTION
        Returns an empty string when Region is empty. The name comes from
        Get-BlueprintRegionName. WithCode keeps the programmatic name beside it, in
        a code span, for the identity tables where someone may need to match it to
        the API or a template.

    .PARAMETER Region
        The region code.

    .PARAMETER WithCode
        Add the region code, in code formatting, after the name. When the name is
        the same as the code only the code is shown.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
    param($Region, [switch]$WithCode)
    $r = [string]$Region
    if (-not $r) { return '' }
    $name = Get-BlueprintRegionName $r
    if ($WithCode -and $name -cne $r) { return "$name (``$r``)" }
    if ($WithCode) { return "``$r``" }
    return $name
}
