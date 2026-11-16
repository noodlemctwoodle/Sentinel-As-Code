#Requires -Version 7.6

<#
.SYNOPSIS
    The folder name a run writes to under its workspace's folder: today's date.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Path/Get-iSOCBlueprintRunFolderName.ps1
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

function Get-iSOCBlueprintRunFolderName {
    <#
    .SYNOPSIS
        The folder a run writes to under its workspace's folder: today's
        date, yyyy-MM-dd, in UTC. One folder a day, so a run does not
        overwrite the last and the dashboard can look back day by day.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
}
