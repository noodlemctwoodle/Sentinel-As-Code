#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 91-maturity-assessment.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/MaturityAssessment/Write-BlueprintMaturityAssessmentSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintMaturityAssessmentSection {
    <#
    .SYNOPSIS
        Build the figures for and write 91-maturity-assessment.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $m = $Context.m
    $maturity = $Context.maturity
    $maturityBasis = $Context.maturityBasis
    $maturityOk = $Context.maturityOk
    $maturityScope = $Context.maturityScope
    $n = $Context.n

    # Section 91 — Maturity assessment, from _raw/maturity.json. Engine:
    # Private/Maturity/Get-SentinelMaturity.ps1; methodology and criteria:
    # Docs/Modules/iSOCBlueprint/Sentinel-Maturity-Model.md.
    $maturityBody = if (-not $maturityOk) {
        @"
$(Format-Banner -Title "Maturity Assessment")

_The maturity assessment was not produced in this run (``_raw/maturity.json`` is absent or empty). The collector writes it after the gap analysis; when that capture fails this page stays empty rather than scoring a workspace it cannot see._
"@
    } else {
        $mAreas = @($maturity.areas)
        $areaAxis = ($mAreas | ForEach-Object { "`"$($_.id)`"" }) -join ', '
        $areaBars = ($mAreas | ForEach-Object { if ($null -eq $_.score) { 0 } else { $_.score } }) -join ', '
        $areaRows = @($mAreas | ForEach-Object {
                [pscustomobject]@{
                    Id          = $_.id
                    Area        = $_.name
                    Score       = if ($null -eq $_.score) { 'n/a' } else { Format-BlueprintNumber $_.score }
                    Level       = if ($null -eq $_.level) { 'Not assessed' } else { "$($_.level) $($_.levelName)" }
                    Evaluated   = "$($_.met) met of $($_.evaluated)"
                    Unknown     = $_.unknown
                    Confidence  = $_.confidence
                    GapToTarget = if ($null -eq $_.score) {
                        'n/a'
                    } elseif ($_.level -ge $maturity.targetLevel) { 'met' } else { Format-BlueprintNumber ($maturity.targetLevel - $_.score) }
                }
            })
        $roadmapRows = @(@($maturity.roadmap) | ForEach-Object {
                [pscustomobject]@{
                    Priority  = $_.priority
                    Criterion = "$($_.criterionId) $($_.name)"
                    Area      = $_.area
                    Effort    = $_.effort
                    Lift      = (Format-BlueprintNumber $_.overallLift)
                    Projected = (Format-BlueprintNumber $_.projectedScore)
                    Guidance  = $_.guidance
                }
            })
        $quickWinLines = if (@($maturity.quickWins).Count -gt 0) {
            (@($maturity.quickWins) |
                ForEach-Object { "- **$($_.criterionId)** $($_.name) ($($_.area), lift $(Format-BlueprintNumber $_.overallLift)): $($_.guidance)" }) -join
            [Environment]::NewLine
        } else { '_No Low-effort gaps remain; the rest of the roadmap is Medium or High effort._' }
        $csfRows = @(@($maturity.csf.functions) | ForEach-Object {
                [pscustomobject]@{ Function = "$($_.id) $($_.name)"; Criteria = $_.criteria; Met = $_.met; Gap = $_.gap; Unknown = $_.unknown }
            })
        $criteriaRows = @($mAreas | ForEach-Object {
                $areaId = $_.id
                @($_.criteria) | ForEach-Object {
                    [pscustomobject]@{
                        Id        = $_.id
                        Area      = $areaId
                        Kind      = $_.kind
                        Criterion = $_.name
                        Status    = $_.status
                        Effort    = $_.effort
                        Evidence  = $_.evidence
                    }
                }
            })
        $outOfScopeLines = (@($maturity.outOfScope) | ForEach-Object { "- **$($_.area)**: $($_.reason)" }) -join [Environment]::NewLine
        # The scale, with the score band each level covers and the target marked.
        $scaleRows = @(@($maturity.levels) | ForEach-Object {
                $lv = [int]$_.level
                [pscustomobject]@{
                    Level  = $lv
                    Name   = $_.name
                    Scores = $(if ($lv -ge 5) { '5.00' } else { "$lv.00 to $lv.99" })
                    Target = $(if ($lv -eq [int]$maturity.targetLevel) { 'Target' } else { '' })
                }
            })
        # Every open gap with what it costs the SOC today and what closes it.
        $openGapRows = @($mAreas | ForEach-Object {
                $areaId = $_.id
                @($_.criteria) | Where-Object { $_.status -eq 'Gap' } | ForEach-Object {
                    [pscustomobject]@{ Id = $_.id; Area = $areaId; Criterion = $_.name; Effort = $_.effort; Impact = $_.impact; Guidance = $_.guidance }
                }
            })
        $overallText = if ($null -eq $maturity.overall.score) {
            'not assessed'
        } else { "$(Format-BlueprintNumber $maturity.overall.score) / 5 ($($maturity.overall.levelName))" }
        @"
$(Format-Banner -Title "Maturity Assessment")

> **$($maturity.methodology.name)** v$($maturity.methodology.version), criteria v$($maturity.methodology.criteriaVersion). $(if ($maturityBasis) { "$maturityBasis " })$($maturity.methodology.scaleNote)
$(if ($maturityScope) { "
> **Scope:** $maturityScope
" })

The maturity assessment and the [gap analysis](90-gap-analysis.md) are one assessment: the findings there are the evidence behind many of the criteria here, and each finding says which criterion it decides.

**Overall:** $overallText  ·  **Target:** $($maturity.targetLevel) ($($maturity.targetLevelName))  ·  **Areas below target:** $(@($maturity.areasBelowTarget).Count) of $($mAreas.Count)  ·  **Criteria:** $($maturity.totals.met) met · $($maturity.totals.gap) gaps · $($maturity.totals.unknown) unknown

Unknown criteria are those whose input was not captured or could not be measured in this run; they never count against the workspace. Confidence says how much of an area could be evaluated. The scoring, and every criterion's source, is in [Sentinel-Maturity-Model.md](https://github.com/noodlemctwoodle/Sentinel-As-Code/blob/main/Docs/Modules/iSOCBlueprint/Sentinel-Maturity-Model.md).

## Area scores

``````mermaid
---
config:
  xyChart:
    width: 1200
    height: 420
---
xychart-beta
    title "Maturity by area (0 to 5, target $($maturity.targetLevel))"
    x-axis [$areaAxis]
    y-axis "Score" 0 --> 5
    bar [$areaBars]
``````

## Areas

$(Format-BlueprintTable -Items $areaRows -Columns 'Id','Area','Score','Level','Evaluated','Unknown','Confidence','GapToTarget')

## Maturity scale

An area's score is five times the weighted share of its evaluated criteria that are met; its level is the whole-number part of the score. Criteria that could not be evaluated are left out rather than counted as gaps.

$(Format-BlueprintTable -Items $scaleRows -Columns 'Level','Name','Scores','Target')

## Open gaps and their impact

Every criterion that is not met, with what the gap costs the SOC today and the change that closes it. The roadmap below orders the same gaps by the lift each one gives.

$(Format-BlueprintTable -Items $openGapRows -Columns 'Id','Area','Criterion','Effort','Impact','Guidance' -EmptyMessage '_No open gaps: every evaluated criterion is met._')

## Roadmap

Every gap ($(@($maturity.roadmap).Count) in all), ordered by how much closing it lifts the overall score, then by effort (Low first). ``Projected`` is the overall score after this entry and every one above it.

$(Format-BlueprintTable -Items $roadmapRows -Columns 'Priority','Criterion','Area','Effort','Lift','Projected','Guidance')

## Quick wins

Every Low-effort entry on the roadmap, in roadmap order.

$quickWinLines

## NIST CSF 2.0 rollup

$(Format-BlueprintTable -Items $csfRows -Columns 'Function','Criteria','Met','Gap','Unknown')

Subcategory identifiers are from the NIST Cybersecurity Framework 2.0 (NIST CSWP 29); the mapping and the outcome paraphrases are this project's own.

## Criteria

$(Format-BlueprintTable -Items $criteriaRows -Columns 'Id','Area','Kind','Criterion','Status','Effort','Evidence')

## Out of scope

$outOfScopeLines
"@
    }
    Write-BlueprintSection '91-maturity-assessment.md' $maturityBody
}
