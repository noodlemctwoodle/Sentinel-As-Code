#Requires -Version 7.6

<#
.SYNOPSIS
    Copy the parameters a caller was actually given into a worker's parameter table.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Path/Copy-iSOCBlueprintParameter.ps1
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

function Copy-iSOCBlueprintParameter {
    <#
    .SYNOPSIS
        Copy the parameters a caller was actually given into a worker
        function's parameter table, renaming where the worker uses another name.

    .DESCRIPTION
        Only bound parameters are copied, so anything the caller left out
        keeps the worker's own default.

    .PARAMETER BoundParameters
        The calling command's $PSBoundParameters.

    .PARAMETER Into
        The worker's parameter table to add to.

    .PARAMETER Name
        Parameters to copy under the same name.

    .PARAMETER Rename
        Parameters to copy under another name: public name to worker name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $BoundParameters,
        [Parameter(Mandatory)] [hashtable] $Into,
        [string[]] $Name = @(),
        [hashtable] $Rename = @{}
    )

    foreach ($key in $Name) {
        if ($BoundParameters.Keys -contains $key) { $Into[$key] = $BoundParameters[$key] }
    }
    foreach ($key in $Rename.Keys) {
        if ($BoundParameters.Keys -contains $key) { $Into[$Rename[$key]] = $BoundParameters[$key] }
    }
}
