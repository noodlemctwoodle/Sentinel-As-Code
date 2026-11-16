#Requires -Version 7.6

<#
.SYNOPSIS
    Build the maturity model and the headline figure for each section.

.DESCRIPTION
    A step of the SharePoint site build. Steps run in order and pass their results
    to later ones through the build context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Steps/Build-SiteMaturity.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Build-SiteMaturity {
    <#
    .SYNOPSIS
        Build the maturity model and the headline figure for each section.

    .PARAMETER Context
        The build context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the build context.
    $costModel = $Context.costModel
    $counts = $Context.counts
    $findings = $Context.findings
    $incidents30d = $Context.incidents30d
    $incSummaryRow = $Context.incSummaryRow
    $lookbackDays = $Context.lookbackDays
    $maturityOk = $Context.maturityOk
    $maturityRaw = $Context.maturityRaw
    $mitre = $Context.mitre
    $mitreCovered = $Context.mitreCovered
    $ruleRefs = $Context.ruleRefs
    $uncoveredTotal = $Context.uncoveredTotal
    $resourcesFolder = $Context.resourcesFolder

    # Maturity: the page carries evidence and guidance; the dashboard keeps the
    # scores, the criteria statuses, the roadmap and the rollup.
    $maturityModel = $null
    if ($maturityOk) {
        # What the score is based on and what it covers; an older collector's
        # maturity.json has neither, so read them from the criteria file.
        $basis = [string]$maturityRaw.methodology.basis
        $scope = [string]$maturityRaw.methodology.scope
        $criteriaFile = Join-Path $resourcesFolder 'Data/maturity-criteria.json'
        if ((-not $basis -or -not $scope) -and (Test-Path -LiteralPath $criteriaFile)) {
            $criteriaMethod = (Get-Content -LiteralPath $criteriaFile -Raw | ConvertFrom-Json).methodology
            if (-not $basis) { $basis = [string]$criteriaMethod.basis }
            if (-not $scope) { $scope = [string]$criteriaMethod.scope }
        }
        $maturityModel = [ordered]@{
            methodology      = [ordered]@{ name = [string]$maturityRaw.methodology.name; version = [string]$maturityRaw.methodology.version; basis = $basis; scope = $scope }
            targetLevel      = [int]$maturityRaw.targetLevel
            targetLevelName  = [string]$maturityRaw.targetLevelName
            targetMet        = [bool]$maturityRaw.targetMet
            overall          = [ordered]@{ score = $maturityRaw.overall.score; level = $maturityRaw.overall.level; levelName = [string]$maturityRaw.overall.levelName }
            levels           = @(@($maturityRaw.levels) | ForEach-Object { [ordered]@{ level = [int]$_.level; name = [string]$_.name } })
            areasBelowTarget = @(@($maturityRaw.areasBelowTarget) | ForEach-Object { [string]$_.id })
            areas            = @(foreach ($a in @($maturityRaw.areas)) {
                [ordered]@{ id = $a.id; name = $a.name; score = $a.score; level = $a.level; levelName = $a.levelName; met = $a.met; gap = $a.gap; unknown = $a.unknown; evaluated = $a.evaluated; confidence = $a.confidence }
            })
            criteria         = @(foreach ($a in @($maturityRaw.areas)) { foreach ($c in @($a.criteria)) {
                [ordered]@{ id = $c.id; area = $a.id; kind = $c.kind; name = $c.name; status = $c.status; effort = $c.effort; impact = $c.impact; evidence = $c.evidence; guidance = $(if ($c.PSObject.Properties['guidance']) { [string]$c.guidance } else { '' }) }
            } })
            roadmap          = @(@($maturityRaw.roadmap) | ForEach-Object {
                [ordered]@{ priority = $_.priority; criterionId = $_.criterionId; area = $_.area; name = $_.name; effort = $_.effort; overallLift = $_.overallLift; projectedScore = $_.projectedScore; guidance = $_.guidance }
            })
            quickWins        = @(@($maturityRaw.quickWins) | ForEach-Object { [ordered]@{ criterionId = $_.criterionId; area = $_.area; name = $_.name; guidance = $_.guidance; overallLift = $_.overallLift } })
            csf              = [ordered]@{
                source    = [string]$maturityRaw.csf.source
                functions = @(@($maturityRaw.csf.functions) | ForEach-Object { [ordered]@{ id = $_.id; name = $_.name; criteria = $_.criteria; met = $_.met; gap = $_.gap; unknown = $_.unknown } })
            }
            totals           = [ordered]@{ criteria = $maturityRaw.totals.criteria; met = $maturityRaw.totals.met; gap = $maturityRaw.totals.gap; unknown = $maturityRaw.totals.unknown }
        }
    }

    # ---------------------------------------------------------------------------
    # Sections: dashboard blocks and native page segments
    # ---------------------------------------------------------------------------

    $headlineByNum = @{
        10 = "$($counts.connectors) connectors"
        20 = "$($counts.rulesEnabled) enabled / $($counts.rulesTotal)"
        25 = "$mitreCovered / $($mitre.Count) tactics"
        30 = "$($counts.hunting) hunting queries"
        40 = "$($counts.workbooks) workbooks"
        50 = "$($counts.watchlists) watchlists"
        60 = "$($counts.automationRules) automation rules"
        83 = "$($counts.dcrs) DCRs"
        85 = "$($counts.rbac) role assignments"
        90 = "$($findings.total) findings"
    }
    if ($costModel) { $headlineByNum[84] = "$($costModel.currency) $($costModel.monthlyTotal)/mo" }
    if ($incSummaryRow) { $headlineByNum[15] = "$incidents30d incidents ($($lookbackDays)d)" }
    if ($ruleRefs.Count -gt 0) { $headlineByNum[28] = "$uncoveredTotal tables without detection" }
    if ($maturityModel) {
        $headlineByNum[91] = if ($null -ne $maturityModel.overall.score) { "Score $($maturityModel.overall.score) / 5" } else { 'Not assessed' }
    }

    # Left in the build context for later steps.
    $Context.headlineByNum = $headlineByNum
    $Context.maturityModel = $maturityModel
}
