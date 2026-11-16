#Requires -Version 7.6

<#
.SYNOPSIS
    Sentinel-As-Code maturity assessment. Scores a workspace 0 to 5 across
    eleven capability areas from the gap-engine outcomes and the _raw
    captures, and builds a prioritised roadmap to a target level.

.DESCRIPTION
    Pure data-in/data-out, testable end-to-end with fixture files. The work is\n    shared out across the files beside this one: New-MaturityMetrics\n    computes the metrics, Resolve-MaturitySource and New-MaturityArea score the\n    criteria, New-MaturityRoadmap orders the gaps and Get-MaturityCsfRollup\n    counts the NIST CSF coverage.

    The criteria live in Resources/maturity-criteria.json. Each criterion
    names a source that resolves to one of three statuses:

        Met      the practice is in place or the coverage is present
        Gap      it is not
        Unknown  the input was not captured, so no judgement is made

    Source kinds:
        gapRule  a gap rule outcome: Passed is Met, Fired is Gap, anything
                 else (Errored, Undefined, not evaluated) is Unknown
        metric   a value from New-MaturityMetrics compared with op/value;
                 a null metric (its file was not captured) is Unknown
        allOf    Gap if any source is Gap, else Unknown if any is Unknown,
                 else Met
        anyOf    Met if any source is Met, else Unknown if any is Unknown,
                 else Gap

    An area's score is 5 times the weight of its Met criteria over the
    weight of its Met and Gap criteria; Unknown never counts against a
    workspace. The level is the whole-number part of the score. Confidence
    reflects how many criteria could be evaluated. The overall score is the
    mean of the area scores.

    The roadmap lists every Gap criterion ordered by how much the overall
    score would rise if it were met, then by effort (Low first), then by
    id, with a running projected score. Quick wins are every Low-effort
    entry, in roadmap order. The NIST CSF 2.0 rollup counts criteria per
    function and per referenced subcategory.

    Usage:
        $maturity = Get-SentinelMaturity -InputRoot './SecurityDocs/myws/_raw' `
                                         -ResourcesRoot './Modules/iSOCBlueprint/Resources/Data' `
                                         -CriteriaPath './Modules/iSOCBlueprint/Resources/Data/maturity-criteria.json' `
                                         -GapOutcomes $gapOutcomes -TargetLevel 3

    When -GapOutcomes is not supplied the engine reads gap-checks.json from
    InputRoot; when neither exists every gapRule criterion is Unknown.

    A criterion's evidence text is a template. {metric} is the metric as a
    count with thousands separators (a fraction to one place); {metric:gb}
    is it in GB to two places and {metric:1dp} to one place. {rule|rules}
    is the singular for a metric of one and the plural otherwise, so a
    template never writes "rule(s)". {lookback} and {recent} name the
    run's window.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Maturity/Get-SentinelMaturity.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-09
    Version:      0.6.2
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.

    Credit and thanks: the criterion set and the roadmap idea are based
    on the Sentinel health-check script by thinkndle, kindly given to
    the Sentinel-As-Code project. Thank you, thinkndle, for sharing your
    work so generously; it shaped much of the Blueprint's health,
    coverage and maturity reporting. The scoring, the Unknown handling
    and the area taxonomy are this project's own.
#>

function Get-SentinelMaturity {
    <#
    .SYNOPSIS
        Run the maturity assessment over a _raw folder.

    .PARAMETER InputRoot
        The _raw folder written by Export-iSOCBlueprintInventory.

    .PARAMETER ResourcesRoot
        Modules/iSOCBlueprint/Resources/Data.

    .PARAMETER CriteriaPath
        Path to maturity-criteria.json.

    .PARAMETER GapOutcomes
        The per-rule outcomes from Get-SentinelGap -OutcomeCollector. When
        omitted, gap-checks.json in InputRoot is read instead.

    .PARAMETER TargetLevel
        Level (1 to 5) the workspace is aiming for. Default 3.

    .OUTPUTS
        One [pscustomobject], the content of _raw/maturity.json.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $InputRoot,
        [Parameter(Mandatory = $true)] [string] $ResourcesRoot,
        [Parameter(Mandatory = $true)] [string] $CriteriaPath,
        [Parameter(Mandatory = $false)] [AllowNull()] [object[]] $GapOutcomes,
        [Parameter(Mandatory = $false)] [ValidateRange(1, 5)] [int] $TargetLevel = 3
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path $InputRoot))     { throw "Input root not found: $InputRoot" }
    if (-not (Test-Path $ResourcesRoot)) { throw "Resources root not found: $ResourcesRoot" }
    if (-not (Test-Path $CriteriaPath))  { throw "Criteria file not found: $CriteriaPath" }

    $doc = Get-Content $CriteriaPath -Raw | ConvertFrom-Json -Depth 16
    $metrics = New-MaturityMetrics -InputRoot $InputRoot -ResourcesRoot $ResourcesRoot
    $window = Read-MaturityWindow -InputRoot $InputRoot
    Test-MaturityCriteriaDocument -Document $doc -MetricNames @($metrics.Keys)

    $lookups = Read-MaturityOutcome -InputRoot $InputRoot -GapOutcomes $GapOutcomes

    $levelNames = @{}
    foreach ($l in @($doc.levels)) { $levelNames[[int]$l.level] = [string]$l.name }
    $confidenceGood = [int](Get-MaturityPropertyValue $doc 'confidence.good' 6)
    $confidenceModerate = [int](Get-MaturityPropertyValue $doc 'confidence.moderate' 4)

    $areas = @(foreach ($area in @($doc.areas)) {
        New-MaturityArea -Area $area -Criteria $doc.criteria -Metrics $metrics `
            -OutcomeById $lookups.OutcomeById -EvidenceById $lookups.EvidenceById -Window $window `
            -LevelNames $levelNames -ConfidenceGood $confidenceGood -ConfidenceModerate $confidenceModerate
    })

    $assessed = @($areas | Where-Object { $null -ne $_.score })
    $overallScore = $null; $overallLevel = $null
    if ($assessed.Count -gt 0) {
        $overallScore = [math]::Round((($assessed | Measure-Object -Property score -Average).Average), 2)
        $overallLevel = [int][math]::Floor($overallScore)
    }

    $roadmap = @(New-MaturityRoadmap -Area $assessed -Window $window -OverallScore $overallScore)
    $quickWins = @($roadmap | Where-Object effort -eq 'Low')

    $below = @($assessed | Where-Object { $_.level -lt $TargetLevel } | ForEach-Object {
        [pscustomobject]@{ id = $_.id; name = $_.name; score = $_.score; level = $_.level; gapToTarget = [math]::Round($TargetLevel - $_.score, 2) }
    })

    $allCriteria = @($areas | ForEach-Object { $_.criteria })
    $csf = Get-MaturityCsfRollup -Document $doc -Criteria $allCriteria
    $functions = $csf.Functions
    $subcategories = $csf.Subcategories

    return [pscustomobject]@{
        methodology      = [pscustomobject]@{
            name            = [string]$doc.methodology.name
            version         = [string]$doc.methodology.version
            criteriaVersion = [string]$doc.version
            scaleNote       = Format-MaturityWindow -Text ([string](Get-MaturityPropertyValue $doc 'methodology.scaleNote' '')) -Window $window
            basis           = [string](Get-MaturityPropertyValue $doc 'methodology.basis' '')
            scope           = Format-MaturityWindow -Text ([string](Get-MaturityPropertyValue $doc 'methodology.scope' '')) -Window $window
            lookbackDays    = $window.Days
        }
        generatedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
        targetLevel      = $TargetLevel
        targetLevelName  = $levelNames[$TargetLevel]
        targetMet        = ($assessed.Count -gt 0 -and $below.Count -eq 0)
        areasBelowTarget = $below
        overall          = [pscustomobject]@{
            score     = $overallScore
            level     = $overallLevel
            levelName = $(if ($null -ne $overallLevel) { $levelNames[$overallLevel] } else { 'Not assessed' })
        }
        levels           = @($doc.levels | ForEach-Object { [pscustomobject]@{ level = [int]$_.level; name = [string]$_.name } })
        areas            = @($areas | ForEach-Object {
            [pscustomobject]@{
                id = $_.id; name = $_.name; description = $_.description; score = $_.score; level = $_.level; levelName = $_.levelName
                met = $_.met; gap = $_.gap; unknown = $_.unknown; evaluated = $_.evaluated; confidence = $_.confidence
                criteria = @($_.criteria | ForEach-Object {
                    [pscustomobject]@{ id = $_.id; kind = $_.kind; name = $_.name; status = $_.status; evidence = $_.evidence; weight = $_.weight; effort = $_.effort; impact = $_.impact; guidance = $_.guidance; csf = $_.csf; source = $_.source }
                })
            }
        })
        roadmap          = $roadmap
        quickWins        = $quickWins
        csf              = [pscustomobject]@{
            source        = [string](Get-MaturityPropertyValue $doc 'csf.source' '')
            functions     = $functions
            subcategories = $subcategories
        }
        outOfScope       = @(Get-MaturityPropertyValue $doc 'outOfScope' @())
        totals           = [pscustomobject]@{
            criteria = $allCriteria.Count
            met      = @($allCriteria | Where-Object status -eq 'Met').Count
            gap      = @($allCriteria | Where-Object status -eq 'Gap').Count
            unknown  = @($allCriteria | Where-Object status -eq 'Unknown').Count
        }
        metrics          = [pscustomobject]$metrics
    }
}
