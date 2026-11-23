#Requires -Version 7.6

<#
.SYNOPSIS
    Convert a section's Markdown to the section model and write its JSON.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Output/Write-BlueprintSectionModel.ps1
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

function Write-BlueprintSectionModel {
    <#
    .SYNOPSIS
        Convert a section's Markdown to the section model and write its JSON.

    .DESCRIPTION
        Writes sections/<id>.json, where the id is the file name without its
        extension, and adds an entry to $script:SectionIndex. The contents page
        (index.md) has no model, so nothing is written for it: sections/index.json
        lists the sections. The first call reads run-context.json to fill
        $script:SectionMeta (workspace, generated time and Blueprint version).

    .PARAMETER FileName
        The page file name, such as 90-gap-analysis.md.

    .PARAMETER Markdown
        The page Markdown to convert.
    #>
    [CmdletBinding()]
    param([string]$FileName, [string]$Markdown)
    if ($FileName -eq 'index.md') { return }
    if (-not $script:SectionMeta) {
        $rc = Read-BlueprintRaw 'run-context.json'
        $script:SectionMeta = [ordered]@{
            workspace        = $script:WorkspaceName
            generatedUtc     = $(
                if ($rc -and $rc.StartedAtUtc) { ([datetime]$rc.StartedAtUtc).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
            )
            blueprintVersion = $(if ($rc -and $rc.BlueprintVersion) { [string]$rc.BlueprintVersion } else { $null })
        }
    }
    $id = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $model = ConvertTo-BlueprintSection -Markdown $Markdown -Id $id -Meta $script:SectionMeta
    $model | ConvertTo-Json -Depth 64 | Set-Content -Path (Join-Path $script:SectionsRoot "$id.json") -Encoding utf8
    $script:SectionIndex.Add([ordered]@{ id = $id; order = $model.order; title = $model.title; file = "$id.json" })
    Write-Verbose "rendered sections/$id.json"
}
