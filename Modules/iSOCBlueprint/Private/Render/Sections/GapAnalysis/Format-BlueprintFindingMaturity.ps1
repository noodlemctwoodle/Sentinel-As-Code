#Requires -Version 7.6

<#
.SYNOPSIS
    Show the maturity criteria linked to a finding.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/GapAnalysis/Format-BlueprintFindingMaturity.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-BlueprintFindingMaturity([string]$Id) {
    $links = if ($findingMaturity.ContainsKey($Id)) { @($findingMaturity[$Id]) } else { @() }
    if ($links.Count -eq 0) { return 'not scored. This is a hygiene or cost check; it does not move the maturity score.' }
    return ((@($links | ForEach-Object {
        $state = if ($_.Status) { ", now $($_.Status)" } else { '' }
        $gain = if ($null -ne $_.Lift -and $_.Lift -gt 0) {
            $by = Format-BlueprintNumber $_.Lift
            if ($_.Shared) { "; closing all of its findings lifts the overall score by +$by" } else { "; closing it lifts the overall score by +$by" }
        } else { '' }
        $how = if ($_.Shared) { 'one of the findings behind' } else { 'decides' }
        "$how [$($_.CriterionId)](91-maturity-assessment.md#criteria) $($_.Name) ($($_.AreaName))$state$gain"
    })) -join '; ') + '.'
}
