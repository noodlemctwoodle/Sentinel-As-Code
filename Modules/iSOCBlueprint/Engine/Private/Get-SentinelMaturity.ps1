#Requires -Version 7.6

<#
.SYNOPSIS
    Loads the Sentinel-As-Code maturity assessment.

.DESCRIPTION
    Dot-source this file to define Get-SentinelMaturity and the functions it
    uses. They live one per file under Modules/iSOCBlueprint/Private/Maturity:

      Get-SentinelMaturity.ps1   the entry point, with the scoring method
                                 described in its file help
      Metrics/                   New-MaturityMetrics, the values criteria read
      Criteria/                  the criteria document check, source
                                 resolution and per-area scoring
      Reporting/                 the roadmap and the NIST CSF rollup
      Helpers/                   property reads, number parsing and the
                                 evidence and window text
      Data/                      the effort order the roadmap sorts by

    The criteria live in Resources/maturity-criteria.json.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Get-SentinelMaturity.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-09
    Version:      0.6.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file loads functions rather than running. Per-parameter detail
    lives on each function's own help block.

    Credit and thanks: the criterion set and the roadmap idea are based
    on the Sentinel health-check script by thinkndle, kindly given to
    the Sentinel-As-Code project. Thank you, thinkndle, for sharing your
    work so generously; it shaped much of the Blueprint's health,
    coverage and maturity reporting. The scoring, the Unknown handling
    and the area taxonomy are this project's own.
#>

# Counts, GB and plurals written as the dashboard writes them.
. (Join-Path $PSScriptRoot 'Format-BlueprintText.ps1')
# Recent hunts and bookmarks (metric bookmarksRecent), shared with SAC-HNT-01.
. (Join-Path $PSScriptRoot 'Get-HuntingActivity.ps1')
if (-not (Get-Command -Name Get-TableFamily -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-TableFamily.ps1')
}
if (-not (Get-Command -Name Get-SearchRestoreTable -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-SearchRestoreTable.ps1')
}

# The maturity functions (the module's own Private/Maturity, two folders up
# from here), defined in the caller's scope.
$maturityRoot = Join-Path $PSScriptRoot '..' '..' 'Private' 'Maturity'
foreach ($maturityFile in Get-ChildItem -LiteralPath $maturityRoot -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
    . $maturityFile.FullName
}
Remove-Variable -Name maturityFile, maturityRoot -WhatIf:$false
