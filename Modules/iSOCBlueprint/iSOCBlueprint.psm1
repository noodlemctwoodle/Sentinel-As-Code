#Requires -Version 7.6

<#
.SYNOPSIS
    Loader for the iSOCBlueprint module.

.DESCRIPTION
    Dot-sources the private helpers and then the public commands, one file
    per command, and exports the public ones. The Blueprint itself (the
    collector, the renderer, the Word and SharePoint steps) is functions
    under Private/, one per file, that the public commands call directly.
    Engine/ now holds only the static files they read: resources, schemas,
    templates, the reference document and the loader shims that remain.

.NOTES
    File:         Modules/iSOCBlueprint/iSOCBlueprint.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.2.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on each command's own help block. The module's
    shipped version is ModuleVersion in iSOCBlueprint.psd1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:iSOCBlueprintRoot = $PSScriptRoot
$script:iSOCBlueprintEngineRoot = Join-Path $PSScriptRoot 'Engine'

foreach ($folder in 'Private', 'Public') {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
        . $file.FullName
    }
}

# New-iSOCBlueprint prints its own summary when a run ends, so its result
# shows only where the run went; every property is still on the object.
Update-TypeData -TypeName 'iSOCBlueprint.Blueprint' -DefaultDisplayPropertySet 'WorkspaceName', 'Path' -Force

$public = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File | ForEach-Object BaseName)
Export-ModuleMember -Function $public
