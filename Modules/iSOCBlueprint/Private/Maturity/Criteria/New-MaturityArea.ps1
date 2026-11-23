#Requires -Version 7.6

<#
.SYNOPSIS
    Resolve one capability area's criteria and score it.

.DESCRIPTION
    An area's score is 5 times the weight of its Met criteria over the weight
    of its Met and Gap criteria; Unknown never counts against a workspace.
    The level is the whole-number part of the score.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Maturity/Criteria/New-MaturityArea.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Maturity Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function New-MaturityArea {
    <#
    .SYNOPSIS
        One area of the assessment: its resolved criteria, score, level and
        confidence.

    .PARAMETER Area
        The area entry from maturity-criteria.json.

    .PARAMETER Criteria
        Every criterion in the document; those naming this area are used.

    .PARAMETER Metrics
        The table from New-MaturityMetrics.

    .PARAMETER OutcomeById
        Gap rule outcomes by rule id, from Read-MaturityOutcome.

    .PARAMETER EvidenceById
        Gap finding evidence by rule id, from Read-MaturityOutcome.

    .PARAMETER Window
        The run's window, from Read-MaturityWindow.

    .PARAMETER LevelNames
        Level number to level name.

    .PARAMETER ConfidenceGood
        Evaluated criteria needed for Good confidence.

    .PARAMETER ConfidenceModerate
        Evaluated criteria needed for Moderate confidence.

    .OUTPUTS
        One [pscustomobject], an entry of the assessment's areas.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] $Area,
        [Parameter(Mandatory = $true)] [AllowNull()] $Criteria,
        [Parameter(Mandatory = $true)] $Metrics,
        [Parameter(Mandatory = $true)] [hashtable] $OutcomeById,
        [Parameter(Mandatory = $true)] [hashtable] $EvidenceById,
        [Parameter(Mandatory = $true)] $Window,
        [Parameter(Mandatory = $true)] [hashtable] $LevelNames,
        [Parameter(Mandatory = $true)] [int] $ConfidenceGood,
        [Parameter(Mandatory = $true)] [int] $ConfidenceModerate
    )

    $areaId = [string]$Area.id
    $resolved = @(foreach ($c in @($Criteria | Where-Object { [string]$_.area -eq $areaId })) {
        $r = Resolve-MaturitySource -Source $c.source -Metrics $Metrics -OutcomeById $OutcomeById -EvidenceById $EvidenceById
        $template = switch ($r.Status) {
            'Met' { Get-MaturityPropertyValue $c 'evidence.met' $null }
            'Gap' { Get-MaturityPropertyValue $c 'evidence.gap' $null }
            default { $null }
        }
        $evidence = Format-MaturityWindow -Text (Format-MaturityEvidence -Template $template -Metric $r.Metric) -Window $Window
        if (-not $evidence) { $evidence = $r.Evidence }
        if (-not $evidence) {
            $evidence = switch ($r.Status) {
                'Met' { "$($r.Rule) passed." }
                'Gap' { "$($r.Rule) fired." }
                default { 'Not evaluated in this run.' }
            }
        }
        [pscustomobject]@{
            id       = [string]$c.id
            kind     = [string]$c.kind
            name     = [string]$c.name
            status   = $r.Status
            evidence = $evidence
            weight   = [double]$c.weight
            effort   = [string]$c.effort
            impact   = Format-MaturityWindow -Text ([string]$c.impact) -Window $Window
            guidance = [string]$c.guidance
            csf      = @($c.csf | ForEach-Object { [string]$_ })
            source   = $c.source
            metric   = $r.Metric
            rule     = $r.Rule
        }
    })
    $known = @($resolved | Where-Object { $_.status -in 'Met', 'Gap' })
    # Measure-Object returns nothing for an empty input, so sum by hand.
    $sumKnown = 0.0; $sumMet = 0.0
    foreach ($k in $known) {
        $sumKnown += $k.weight
        if ($k.status -eq 'Met') { $sumMet += $k.weight }
    }
    $score = $null; $level = $null
    if ($known.Count -gt 0 -and $sumKnown -gt 0) {
        $score = [math]::Round(5.0 * [double]$sumMet / [double]$sumKnown, 2)
        $level = [int][math]::Floor($score)
    }
    $confidence = if ($known.Count -eq 0) { 'Not assessed' }
                  elseif ($known.Count -ge $ConfidenceGood) { 'Good' }
                  elseif ($known.Count -ge $ConfidenceModerate) { 'Moderate' }
                  else { 'Indicative' }
    [pscustomobject]@{
        id          = $areaId
        name        = [string]$Area.name
        description = [string](Get-MaturityPropertyValue $Area 'description' '')
        score       = $score
        level       = $level
        levelName   = $(if ($null -ne $level) { $LevelNames[$level] } else { 'Not assessed' })
        met         = @($resolved | Where-Object status -eq 'Met').Count
        gap         = @($resolved | Where-Object status -eq 'Gap').Count
        unknown     = @($resolved | Where-Object status -eq 'Unknown').Count
        evaluated   = $known.Count
        confidence  = $confidence
        weightKnown = [double]$sumKnown
        criteria    = $resolved
    }
}
