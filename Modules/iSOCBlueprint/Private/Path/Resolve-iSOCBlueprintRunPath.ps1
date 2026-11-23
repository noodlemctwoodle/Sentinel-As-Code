#Requires -Version 7.6

<#
.SYNOPSIS
    A run's folder, given it or its workspace's folder.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Path/Resolve-iSOCBlueprintRunPath.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, paths
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Resolve-iSOCBlueprintRunPath {
    <#
    .SYNOPSIS
        A run's folder, given it or its workspace's folder. A workspace
        folder that holds day folders (yyyy-MM-dd) resolves to the newest
        day with an inventory; any other folder is returned as it is.

    .PARAMETER Path
        A run's folder, or a workspace folder holding day folders.

    .OUTPUTS
        [string] The absolute path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Path)

    $full = Resolve-iSOCBlueprintPath -Path $Path
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { return $full }
    foreach ($marker in '_raw', 'sections', 'run-context.json') {
        if (Test-Path -LiteralPath (Join-Path $full $marker)) { return $full }
    }
    $days = @(Get-ChildItem -LiteralPath $full -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and ((Test-Path -LiteralPath (Join-Path $_.FullName '_raw')) -or (Test-Path -LiteralPath (Join-Path $_.FullName 'sections'))) } |
            Sort-Object Name -Descending)
    if ($days.Count) { return $days[0].FullName }
    return $full
}
