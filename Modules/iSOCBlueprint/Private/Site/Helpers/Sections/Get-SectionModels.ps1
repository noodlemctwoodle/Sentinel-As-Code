#Requires -Version 7.6

<#
.SYNOPSIS
    Read every section model (sections/*.json) of a workspace folder.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Sections/Get-SectionModels.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SectionModels {
    <#
    .SYNOPSIS
        The run's sections from the section model (sections/index.json and
        sections/<id>.json), in reading order. A snapshot rendered before
        the section model existed has only NN-name.md files; those are
        converted on the fly with the same converter the renderer uses.
    #>
    param([Parameter(Mandatory)] [string] $Source)
    $dir = Join-Path $Source 'sections'
    $indexPath = Join-Path $dir 'index.json'
    if (Test-Path -LiteralPath $indexPath) {
        $index = Get-Content -LiteralPath $indexPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable -Depth 64
        foreach ($entry in @($index.sections)) {
            $path = Join-Path $dir ([string]$entry.file)
            if (-not (Test-Path -LiteralPath $path)) { $buildWarnings.Add("sections/$($entry.file) is listed in sections/index.json but missing."); continue }
            Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable -Depth 64
        }
        return
    }
    $md = @(Get-ChildItem -LiteralPath $Source -Filter '*.md' | Where-Object { $_.BaseName -match '^\d+-' } | Sort-Object Name)
    if ($md.Count) { $buildWarnings.Add("No sections/ in $Source (rendered before the section model); converted the $($md.Count) Markdown sections instead.") }
    foreach ($f in $md) {
        ConvertTo-BlueprintSection -Markdown (Get-Content -LiteralPath $f.FullName -Raw -Encoding utf8) -Id $f.BaseName
    }
}
