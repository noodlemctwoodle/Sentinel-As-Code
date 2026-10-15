#Requires -Version 7.2

<#
.SYNOPSIS
    Loader for the iSOCBlueprint module.

.DESCRIPTION
    Dot-sources the private helpers and then the public commands, one file
    per command, and exports the public ones. The Blueprint itself (the
    collector, the renderer, the Word and SharePoint steps) lives under
    Engine/ as scripts with the same layout they had in Tools/Blueprint;
    the public commands call them through Invoke-iSOCBlueprintEngine.

.NOTES
    File:         Modules/iSOCBlueprint/iSOCBlueprint.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.1
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on each command's own help block. The module's
    shipped version is ModuleVersion in iSOCBlueprint.psd1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:iSOCBlueprintRoot = $PSScriptRoot
$script:iSOCBlueprintEngineRoot = Join-Path $PSScriptRoot 'Engine'

foreach ($folder in 'Private', 'Public') {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' -File | Sort-Object Name) {
        . $file.FullName
    }
}

# New-iSOCBlueprint prints its own summary when a run ends, so its result
# shows only where the run went; every property is still on the object.
Update-TypeData -TypeName 'iSOCBlueprint.Blueprint' -DefaultDisplayPropertySet 'WorkspaceName', 'Path' -Force

$public = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File | ForEach-Object BaseName)
Export-ModuleMember -Function $public
