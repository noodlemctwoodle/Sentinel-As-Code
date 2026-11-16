#Requires -Version 7.6

<#
.SYNOPSIS
    Loads the collector's capture reporting: the notes it writes as it runs
    and the capture summary at the end.

.DESCRIPTION
    Dot-source this file to define Write-CaptureSummary and the functions it
    uses. They live one per file under
    Modules/iSOCBlueprint/Private/CaptureSummary:

      Write-CaptureSummary.ps1   the entry point, with the description of the
                                 three outcomes and how each is shown
      Issues/    sorting a failed capture, its message and status, and the
                 note and partial-read issue the collector writes as it runs
      Helpers/   message wrapping and the record count of a captured file

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Write-CaptureSummary.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.3.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file loads functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# The capture reporting functions (the module's own Private/CaptureSummary,
# two folders up from here), defined in the caller's scope.
$captureSummaryRoot = Join-Path $PSScriptRoot '..' '..' 'Private' 'CaptureSummary'
foreach ($captureSummaryFile in Get-ChildItem -LiteralPath $captureSummaryRoot -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
    . $captureSummaryFile.FullName
}
Remove-Variable -Name captureSummaryFile, captureSummaryRoot -WhatIf:$false
