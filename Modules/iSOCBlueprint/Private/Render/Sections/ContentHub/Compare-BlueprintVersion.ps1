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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Compare-BlueprintVersion {
    <#
    .SYNOPSIS
        Compare two dotted versions numerically.

    .DESCRIPTION
        Dotted versions compare numerically (3.0.10 is newer than 3.0.9); a version
        that [version] cannot read compares as text, ordinally.

    .PARAMETER A
        The first version.

    .PARAMETER B
        The second version.

    .OUTPUTS
        [int]: negative when A is lower, zero when equal, positive when A is higher.
    #>
    [CmdletBinding()]
    param([string]$A, [string]$B)
    $va = $null; $vb = $null
    if ([version]::TryParse($A, [ref]$va) -and [version]::TryParse($B, [ref]$vb)) { return $va.CompareTo($vb) }
    return [string]::CompareOrdinal($A, $B)
}
