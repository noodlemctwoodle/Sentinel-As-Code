#Requires -Version 7.6

<#
.SYNOPSIS
    The prioritised list of Gap criteria with a running projected score.

.DESCRIPTION
    The roadmap lists every Gap criterion ordered by how much the overall
    score would rise if it were met, then by effort (Low first), then by
    id, with a running projected score.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Maturity/Reporting/New-MaturityRoadmap.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Maturity Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function New-MaturityRoadmap {
    <#
    .SYNOPSIS
        Order every Gap criterion by the overall lift it would give.

    .PARAMETER Area
        The assessed areas (those with a score).

    .PARAMETER Window
        The run's window, for the impact text.

    .PARAMETER OverallScore
        The overall score the projection starts from; null counts as 0.

    .OUTPUTS
        The roadmap entries in priority order, each with priority and
        projectedScore.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]] $Area,
        [Parameter(Mandatory = $true)] $Window,
        [Parameter(Mandatory = $false)] [AllowNull()] $OverallScore
    )

    $roadmapRaw = @(foreach ($a in $Area) {
        foreach ($c in @($a.criteria | Where-Object status -eq 'Gap')) {
            $areaLift = [math]::Round(5.0 * $c.weight / $a.weightKnown, 2)
            [pscustomobject]@{
                criterionId = $c.id
                area        = $a.id
                areaName    = $a.name
                name        = $c.name
                kind        = $c.kind
                evidence    = $c.evidence
                impact      = Format-MaturityWindow -Text ([string]$c.impact) -Window $Window
                guidance    = $c.guidance
                effort      = $c.effort
                csf         = $c.csf
                areaLift    = $areaLift
                overallLift = [math]::Round($areaLift / $Area.Count, 3)
            }
        }
    })
    $ordered = @($roadmapRaw | Sort-Object -Property @{ Expression = 'overallLift'; Descending = $true }, @{ Expression = { $script:MaturityEffortRank[$_.effort] } }, @{ Expression = 'criterionId' })
    $running = if ($null -ne $OverallScore) { [double]$OverallScore } else { 0.0 }
    $priority = 0
    $roadmap = @(foreach ($entry in $ordered) {
        $priority++
        $running = [math]::Min(5.0, $running + $entry.overallLift)
        $entry | Add-Member -NotePropertyName priority -NotePropertyValue $priority -PassThru |
                 Add-Member -NotePropertyName projectedScore -NotePropertyValue ([math]::Round($running, 2)) -PassThru
    })
    return $roadmap
}
