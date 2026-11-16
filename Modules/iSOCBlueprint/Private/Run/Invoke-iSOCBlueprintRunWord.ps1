#Requires -Version 7.6

<#
.SYNOPSIS
    Write the Word report for a New-iSOCBlueprint run.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Run/Invoke-iSOCBlueprintRunWord.ps1
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

function Invoke-iSOCBlueprintRunWord {
    <#
    .SYNOPSIS
        Write the .docx (Export-iSOCBlueprintWord) when the formats include
        Word.

    .PARAMETER Run
        The run's shared state: the values New-iSOCBlueprint was called with
        and what each step has produced so far. Steps read and add to it.
        Adds Document: the report's path, or $null when Word was not asked for.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Run)

    $Run.Document = $null
    if ($Run.Format -contains 'Word') {
        $docPath = if ($Run.NoDateFolder) { Join-Path $Run.Root "$($Run.WorkspaceName).docx" } else { Join-Path $Run.Workspace "$($Run.WorkspaceName).docx" }
        $Run.Document = Export-iSOCBlueprintWord -Path $Run.Workspace -OutputPath $docPath -Title "$($Run.WorkspaceName) - iSOC Blueprint"
    }
}
