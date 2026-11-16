#Requires -Version 7.6

<#
.SYNOPSIS
    Load the bundle (site descriptor, findings, page documents) and print what is about to be published.

.DESCRIPTION
    A step of the SharePoint site publish. Steps run in order and pass their results
    to later ones through the publish context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Publish/Steps/Import-PublishBundle.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Import-PublishBundle {
    <#
    .SYNOPSIS
        Load the bundle (site descriptor, findings, page documents) and print what is about to be published.

    .PARAMETER Context
        The publish context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the publish context.
    $AppPackagePath = $Context.AppPackagePath
    $Bundle = $Context.Bundle
    $SiteUrl = $Context.SiteUrl

    $Bundle = (Resolve-Path -LiteralPath $Bundle).Path
    $sitePath = Join-Path $Bundle 'site.json'
    if (-not (Test-Path -LiteralPath $sitePath)) { throw "No site.json in '$Bundle'. Run New-iSOCBlueprintSite first." }
    $site = Get-Content -LiteralPath $sitePath -Raw | ConvertFrom-Json -Depth 32
    $findingsDoc = Get-Content -LiteralPath (Join-Path $Bundle 'findings.json') -Raw | ConvertFrom-Json -Depth 32
    $pageDocs = @{}
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $Bundle 'pages') -Filter '*.json' -ErrorAction SilentlyContinue) {
        $doc = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json -Depth 32
        $pageDocs[[string]$doc.name] = $doc
    }
    if ($AppPackagePath -and -not (Test-Path -LiteralPath $AppPackagePath)) { throw "App package not found: $AppPackagePath" }
    # The CSVs of the tables cut on their pages; a bundle built before them has none.
    $siteTables = @(if ($site.PSObject.Properties['tables']) { @($site.tables) | Where-Object { $_ } | ForEach-Object { [string]$_ } })

    Write-Host "iSOC Blueprint publish" -ForegroundColor Cyan
    Write-Host "  Site      : $SiteUrl"
    Write-Host "  Bundle    : $Bundle ($($pageDocs.Count) pages, $(@($site.diagrams).Count) diagrams, $($siteTables.Count) table CSVs, $(@($findingsDoc.items).Count) findings)"
    Write-Host "  Workspace : $($site.workspace.name)"
    if ($WhatIfPreference) { Write-Host '  Mode      : WhatIf (read and plan only)' -ForegroundColor Yellow }

    # Left in the publish context for later steps.
    $Context.Bundle = $Bundle
    if (Get-Variable -Name 'doc' -Scope 0 -ErrorAction Ignore) { $Context.doc = $doc }
    $Context.findingsDoc = $findingsDoc
    $Context.pageDocs = $pageDocs
    $Context.site = $site
    $Context.siteTables = $siteTables
}
