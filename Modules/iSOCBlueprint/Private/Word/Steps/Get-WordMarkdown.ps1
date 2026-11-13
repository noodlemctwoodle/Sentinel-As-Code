#Requires -Version 7.6

<#
.SYNOPSIS
    Collect the Markdown files, drop the excluded ones and put the front files first.

.DESCRIPTION
    A step of the Word report conversion. Steps run in order and pass their results
    to later ones through the conversion context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Word/Steps/Get-WordMarkdown.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Word report
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-WordMarkdown {
    <#
    .SYNOPSIS
        Collect the Markdown files, drop the excluded ones and put the front files first.

    .PARAMETER Context
        The conversion context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the conversion context.
    $ExcludeFile = $Context.ExcludeFile
    $FrontFile = $Context.FrontFile
    $OutputPath = $Context.OutputPath
    $ReferenceDoc = $Context.ReferenceDoc
    $sourceFull = $Context.sourceFull
    $Title = $Context.Title

    # ---------------------------------------------------------------------------
    # Collect + order the Markdown
    # ---------------------------------------------------------------------------

    $allMd = @(Get-ChildItem -LiteralPath $sourceFull -Recurse -File -Filter *.md | Sort-Object FullName)
    if ($allMd.Count -eq 0) {
        Write-WordLog "No .md files found under: $sourceFull" -Level Warning
        exit 0
    }

    # Drop excluded files (matched by name at the source root) - e.g. the
    # index/TOC page that the real --toc replaces.
    $excluded = @()
    if ($ExcludeFile.Count -gt 0) {
        $excluded = @($allMd | Where-Object { $_.DirectoryName -eq $sourceFull -and ($ExcludeFile -contains $_.Name) })
        if ($excluded.Count -gt 0) {
            $allMd = @($allMd | Where-Object { $excluded -notcontains $_ })
        }
    }

    # Float front files (matched by name, at the source root) to the top,
    # preserving the -FrontFile order. Everything else keeps path order.
    $front = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $FrontFile) {
        $match = $allMd | Where-Object { $_.Name -ieq $name -and $_.DirectoryName -eq $sourceFull } | Select-Object -First 1
        if ($match) { $front.Add($match) }
    }
    $ordered = @($front) + @($allMd | Where-Object { $front -notcontains $_ })
    $mdPaths = @($ordered | ForEach-Object { $_.FullName })

    # Resource path = every directory under Source, so assets/*.png resolves
    # wherever the asset store lives (root- or subfolder-level).
    $dirs = @($sourceFull) + @((Get-ChildItem -LiteralPath $sourceFull -Recurse -Directory).FullName)
    $resourcePath = $dirs -join [System.IO.Path]::PathSeparator

    Write-WordLog "  Source:    $sourceFull"
    Write-WordLog "  Output:    $OutputPath"
    Write-WordLog "  Title:     $Title"
    Write-WordLog "  Markdown:  $($mdPaths.Count) file(s)"
    if ($excluded.Count -gt 0) { Write-WordLog "  Excluded:  $((($excluded | ForEach-Object { $_.Name }) -join ', '))" }
    if ($front.Count -gt 0) { Write-WordLog "  Front:     $((($front | ForEach-Object { $_.Name }) -join ', '))" }
    Write-WordLog "  Style ref: $(if ($ReferenceDoc) { Split-Path $ReferenceDoc -Leaf } else { 'pandoc default (plain tables)' })"

    # Left in the conversion context for later steps.
    $Context.mdPaths = $mdPaths
    $Context.resourcePath = $resourcePath
}
