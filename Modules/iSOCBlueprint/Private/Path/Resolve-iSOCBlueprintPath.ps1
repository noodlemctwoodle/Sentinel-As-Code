#Requires -Version 7.6

<#
.SYNOPSIS
    An absolute file-system path for a path a user gave, or a default.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Path/Resolve-iSOCBlueprintPath.ps1
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

function Resolve-iSOCBlueprintPath {
    <#
    .SYNOPSIS
        An absolute file-system path for a path a user gave, or a default.

    .PARAMETER Path
        The path given, relative or absolute. May be empty.

    .PARAMETER Default
        Used when Path is empty, relative to the current directory.

    .OUTPUTS
        [string] The absolute path, or $null when both are empty. The path
        need not exist.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] [AllowEmptyString()] [string] $Path,
        [AllowNull()] [AllowEmptyString()] [string] $Default
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = $Default }
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}
