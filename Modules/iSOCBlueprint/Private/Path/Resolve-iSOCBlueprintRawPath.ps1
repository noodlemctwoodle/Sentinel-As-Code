#Requires -Version 7.6

<#
.SYNOPSIS
    The _raw folder of an inventory, given the workspace folder or the _raw folder itself.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Path/Resolve-iSOCBlueprintRawPath.ps1
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

function Resolve-iSOCBlueprintRawPath {
    <#
    .SYNOPSIS
        The _raw folder of an inventory, given the workspace folder or the
        _raw folder itself.

    .PARAMETER Path
        A run's folder (holding _raw/), a workspace folder holding day
        folders (the newest day is used), or a _raw folder.

    .OUTPUTS
        [string] The absolute path of the _raw folder. Throws when neither
        shape is found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Path)

    $full = Resolve-iSOCBlueprintRunPath -Path $Path
    $raw = Join-Path $full '_raw'
    if (Test-Path -LiteralPath $raw -PathType Container) { return $raw }
    if (Test-Path -LiteralPath (Join-Path $full 'run-context.json') -PathType Leaf) { return $full }
    throw "No Blueprint inventory at '$Path'. Give the workspace folder that holds _raw/, or the _raw folder itself (it contains run-context.json)."
}
