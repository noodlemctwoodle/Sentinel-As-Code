#Requires -Version 7.6

<#
.SYNOPSIS
    Assemble the dashboard model and this runs progress record.

.DESCRIPTION
    A step of the SharePoint site build. Steps run in order and pass their results
    to later ones through the build context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Steps/Build-SiteModel.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Build-SiteModel {
    <#
    .SYNOPSIS
        Assemble the dashboard model and this runs progress record.

    .PARAMETER Context
        The build context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the build context.
    $alertLifecycle = $Context.alertLifecycle
    $attackModel = $Context.attackModel
    $chartCount = $Context.chartCount
    $costModel = $Context.costModel
    $counts = $Context.counts
    $daily = $Context.daily
    $dataLakeModel = $Context.dataLakeModel
    $detectionOpportunities = $Context.detectionOpportunities
    $detectionOutcomes = $Context.detectionOutcomes
    $detectionTableFamily = $Context.detectionTableFamily
    $effectiveness = $Context.effectiveness
    $estate = $Context.estate
    $findings = $Context.findings
    $flow = $Context.flow
    $flowTables = $Context.flowTables
    $generatedUtc = $Context.generatedUtc
    $healthPct = $Context.healthPct
    $healthSum = $Context.healthSum
    $healthTotal = $Context.healthTotal
    $huntsSummary = $Context.huntsSummary
    $incidentsByClassification = $Context.incidentsByClassification
    $lakeEnrolled = $Context.lakeEnrolled
    $maturityModel = $Context.maturityModel
    $mitre = $Context.mitre
    $mitreCovered = $Context.mitreCovered
    $playbookHealth = $Context.playbookHealth
    $ProductName = $Context.ProductName
    $ruleRefs = $Context.ruleRefs
    $sections = $Context.sections
    $Source = $Context.Source
    $tiBySource = $Context.tiBySource
    $tiObjects = $Context.tiObjects
    $Title = $Context.Title
    $topRules = $Context.topRules
    $uncoveredTotal = $Context.uncoveredTotal
    $usageDaily = $Context.usageDaily
    $window = $Context.window
    $workspace = $Context.workspace

    $generatedBuildUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC'

    $model = [ordered]@{
        product                   = $ProductName
        title                     = $Title
        workspace                 = $workspace
        counts                    = $counts
        cost                      = $costModel
        findings                  = $findings
        mitre                     = $mitre
        mitreCovered              = $mitreCovered
        mitreCoveredThreshold     = $script:MitreCoveredThreshold
        flow                      = $flow
        flowTables                = $flowTables
        topRules                  = $topRules
        health                    = [ordered]@{ pct = $healthPct; totalEvents = [int]$healthTotal; rows = @($healthSum | Where-Object { $_ }) }
        estate                    = $estate
        effectiveness             = $effectiveness
        usageDaily                = $usageDaily
        maturity                  = $maturityModel
        detectionOpportunities    = $detectionOpportunities
        detectionOutcomes         = $detectionOutcomes
        detectionTableFamily      = $detectionTableFamily
        window                    = $window
        daily                     = $daily
        huntsSummary              = $huntsSummary
        playbookHealth            = $playbookHealth
        tiBySource                = $tiBySource
        tiObjects                 = $tiObjects
        incidentsByClassification = $incidentsByClassification
        alertLifecycle            = $alertLifecycle
        attack                    = $attackModel
        familyOrder               = @(Get-SectionFamilyOrder)
        sections                  = $sections
        dataLakeEnrolled          = $lakeEnrolled
        dataLake                  = $dataLakeModel
        generatedBlueprintUtc     = $generatedBuildUtc
    }

    # This run's progress record (Private/SiteShared/Get-SacProgress.ps1): the headline
    # numbers and the lists the Progress tab compares across runs. The run's day
    # is its folder's name (yyyy-MM-dd), else the day it was collected.
    $runDay = Split-Path -Leaf $Source
    if ($runDay -notmatch '^\d{4}-\d{2}-\d{2}$') {
        $runDay = if ($generatedUtc -match '^\d{4}-\d{2}-\d{2}') { $Matches[0] } else { (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd') }
    }
    $progressRecord = New-SacProgressRecord -Model $model -Date $runDay -GeneratedUtc $generatedUtc
    $model['progress'] = $progressRecord

    Write-SiteLog "  Sections   : $($sections.Count)   Charts: $chartCount (drawn by the chart web part)" Info
    Write-SiteLog "  Findings   : $($findings.total)   Rules enabled: $($counts.rulesEnabled)/$($counts.rulesTotal)   MITRE: $mitreCovered/$($mitre.Count)" Info
    Write-SiteLog "  Maturity   : $(if ($maturityModel -and $null -ne $maturityModel.overall.score) { "$($maturityModel.overall.score) / 5 ($($maturityModel.overall.levelName)), target $($maturityModel.targetLevel)" } else { 'not assessed' })   Uncovered: $(if ($ruleRefs.Count -gt 0) { "$uncoveredTotal table(s), $($estate.uncoveredGb) GB" } else { 'n/a' })" Info

    # Left in the build context for later steps.
    $Context.generatedBuildUtc = $generatedBuildUtc
    $Context.model = $model
    $Context.progressRecord = $progressRecord
    $Context.runDay = $runDay
}
