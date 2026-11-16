#Requires -Version 7.6

<#
.SYNOPSIS
    Return the asset files on the site that this bundle no longer uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SyncPlan/Assets/Get-AssetPrunePlan.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, SharePoint sync planning
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-AssetPrunePlan {
    <#
    .SYNOPSIS
        Return the asset files on the site that this bundle no longer uses.

    .PARAMETER DesiredFiles
        File names this bundle uploads into the folder.

    .PARAMETER ExistingFiles
        File names currently in the folder on the site.

    .OUTPUTS
        [string[]] Names to remove.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $DesiredFiles,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ExistingFiles
    )

    $wanted = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in $DesiredFiles) { [void]$wanted.Add($f) }
    return @($ExistingFiles | Where-Object { -not $wanted.Contains($_) } | Sort-Object)
}
