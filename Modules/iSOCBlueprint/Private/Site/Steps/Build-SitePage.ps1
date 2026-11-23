#Requires -Version 7.6

<#
.SYNOPSIS
    Turn every section model into page documents and dashboard sections.

.DESCRIPTION
    A step of the SharePoint site build. Steps run in order and pass their results
    to later ones through the build context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Steps/Build-SitePage.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Build-SitePage {
    <#
    .SYNOPSIS
        Turn every section model into page documents and dashboard sections.

    .PARAMETER Context
        The build context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the build context.
    $buildWarnings = $Context.buildWarnings
    $headlineByNum = $Context.headlineByNum
    $id = $Context.id
    $MaxTableRows = $Context.MaxTableRows
    $Source = $Context.Source
    $tableRows = $Context.tableRows
    $Title = $Context.Title

    $sections = @()
    $siteSections = @()
    $pageDocs = @()
    $chartCount = 0
    # Tables cut on their page, whole, as CSV: file name and text.
    $tableFiles = [System.Collections.Generic.List[object]]::new()

    $allSectionModels = @(Get-SectionModel -Source $Source)
    # Every section's title first, so a link to a later section can show it.
    $script:SacSectionTitles = @{}
    foreach ($s in $allSectionModels) {
        if ($s -and $s.id -and $null -ne $s.order) { $script:SacSectionTitles[[string]$s.id] = Get-SacSectionTitle -Title ([string]$s.title) }
    }
    foreach ($sec in $allSectionModels) {
        if ($null -eq $sec.order) { continue }
        $id = [string]$sec.id
        $num = [int]$sec.order
        $family = Get-SectionFamily -Number $num
        $pageName = Get-SacPageName -FileName $id

        $converted = ConvertTo-SharePointPageSegment -Section $sec -FindingsListUrl $script:FindingsListUrl -MaxTableRows $MaxTableRows
        foreach ($w in $converted.Warnings) { $buildWarnings.Add($w) }
        foreach ($t in @($converted.Tables)) { if ($t) { $tableFiles.Add($t) } }
        $segments = @($converted.Segments)
        $chartCount += @($segments | Where-Object { $_.type -eq 'chart' }).Count

        $secTitle = if ($converted.Title) { $converted.Title } else { ($id -replace '^\d+-', '' -replace '-', ' ') }
        $hash = Get-ContentHash -Text (([ordered]@{ title = $secTitle; segments = $segments }) | ConvertTo-Json -Depth 32 -Compress)

        $blocks = ConvertTo-SectionBlock -Section $sec
        $tableRows = 0
        foreach ($b in $blocks) { if ($b.t -eq 'table') { $tableRows += @($b.rows).Count } }

        $sections += [ordered]@{
            num       = $num
            file      = "sections/$id.json"
            page      = $pageName
            title     = $secTitle
            family    = $family
            headline  = if ($headlineByNum.ContainsKey($num)) { $headlineByNum[$num] } else { '' }
            tableRows = $tableRows
            blocks    = $blocks
        }
        $siteSections += [ordered]@{ num = $num; file = "sections/$id.json"; page = $pageName; title = $secTitle; family = $family; hash = $hash }
        $pageDocs += [ordered]@{ name = $pageName; file = "sections/$id.json"; num = $num; title = $secTitle; family = $family; hash = $hash; segments = $segments }
    }

    if ($sections.Count -eq 0) {
        $buildWarnings.Add("No sections under $Source. Run ConvertTo-iSOCBlueprint first; the site will have a dashboard and findings but no section pages.")
    }

    # Left in the build context for later steps.
    $Context.chartCount = $chartCount
    $Context.pageDocs = $pageDocs
    $Context.sections = $sections
    $Context.siteSections = $siteSections
    $Context.tableFiles = $tableFiles
}
