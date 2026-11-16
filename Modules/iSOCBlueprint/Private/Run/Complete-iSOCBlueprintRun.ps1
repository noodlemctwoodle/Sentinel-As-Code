#Requires -Version 7.6

<#
.SYNOPSIS
    Print a New-iSOCBlueprint run's summary and return what it produced.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Run/Complete-iSOCBlueprintRun.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, one-command run
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Complete-iSOCBlueprintRun {
    <#
    .SYNOPSIS
        Print the run summary and return the run's result.

    .PARAMETER Run
        The run's shared state: the values New-iSOCBlueprint was called with
        and what each step has produced so far. Steps read and add to it.

    .OUTPUTS
        [pscustomobject] iSOCBlueprint.Blueprint: WorkspaceName, Path, Format,
        SectionsPath, MarkdownPath, WordDocument, SiteBundle and SiteUrl.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [hashtable] $Run)

    Write-iSOCBlueprintRunSummary -Path $Run.Workspace -Elapsed $Run.Timer.Elapsed -Collected (-not $Run.SkipCollection) -WordDocument $Run.Document -SiteBundle $Run.Bundle -SiteUrl $Run.Published

    [pscustomobject]@{
        PSTypeName    = 'iSOCBlueprint.Blueprint'
        WorkspaceName = $Run.WorkspaceName
        Path          = $Run.Workspace
        Format        = $Run.Format
        SectionsPath  = if ($Run.WantJson) { Join-Path $Run.Workspace 'sections' } else { $null }
        MarkdownPath  = if ($Run.WantMarkdown) { $Run.Workspace } else { $null }
        WordDocument  = $Run.Document
        SiteBundle    = $Run.Bundle
        SiteUrl       = $Run.Published
    }
}
