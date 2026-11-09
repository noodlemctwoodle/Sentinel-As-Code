#Requires -Version 7.6

<#
.SYNOPSIS
    Log a dependency fixture run's plan: what it will do with each object, and how the rules are made.

.DESCRIPTION
    The workspace, the prefix, the marker, the run and the scenarios, then a
    line per object with its action and the marker that qualified it.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Write-iSOCDependencyFixturePlan.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-iSOCDependencyFixturePlan {
    <#
    .SYNOPSIS
        Log a dependency fixture run's plan: what it will do with each
        object, and how the rules are made.

    .DESCRIPTION
        The workspace, prefix, marker, run and scenarios; for a create, what
        will be made, the rules' state and clamp and the records to ingest,
        with a warning when the rules are enabled (and another when the clamp
        is off); then a line per object with its action and the marker that
        qualified it. The subscription and workspace ids are not logged.

    .PARAMETER Fixture
        From Get-iSOCDependencyFixturePlan.

    .PARAMETER RunId
        The run.

    .PARAMETER ForRemoval
        A removal.

    .PARAMETER EnableRules
        The rules are made enabled.

    .PARAMETER EnableRulesWithLiveQuery
        Without the clamp too.

    .PARAMETER RecordCount
        Records per table.

    .EXAMPLE
        Write-iSOCDependencyFixturePlan -Fixture $fixture -RunId $runId -RecordCount 5
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Fixture,

        [Parameter(Mandatory)]
        [string] $RunId,

        [switch] $ForRemoval,

        [switch] $EnableRules,

        [switch] $EnableRulesWithLiveQuery,

        [int] $RecordCount
    )

    $setting = Get-iSOCDependencyFixtureSetting
    $plan = $Fixture.Plan
    $mode = if ($ForRemoval) { 'REMOVE' } else { 'CREATE' }
    Write-iSOCLog "Dependency fixture plan ($mode)" -Level Section
    Write-iSOCLog "  Name prefix      : $($plan.NamePrefix)"
    Write-iSOCLog "  Fixture marker   : $($setting.FixtureMarker)"
    Write-iSOCLog "  Run id           : $RunId"
    Write-iSOCLog "  Scenarios        : $($plan.ScenarioName -join ', ')"

    if (-not $ForRemoval) {
        $ruleState = if ($EnableRules) { 'ENABLED' } else { 'DISABLED' }
        $clampText = if ($EnableRulesWithLiveQuery) { 'NO zero-row clamp' } else { "clamped with '$($setting.QueryClamp)'" }
        Write-iSOCLog ('  Will create      : {0} x table, {1} x parser, {2} x hunting query, {3} x analytics rule' -f $plan.Table.Count, @($plan.Parser | Where-Object { -not $_.IsCycleClosure }).Count, $plan.HuntingQuery.Count, $plan.Rule.Count)
        Write-iSOCLog "  Analytics rules  : $ruleState, createIncident=false, $clampText"
        Write-iSOCLog ('  Ingestion        : {0} records total, roughly {1} KB (billable, cannot be recalled)' -f ($RecordCount * $plan.Table.Count), [math]::Max(1, [math]::Round(($RecordCount * $plan.Table.Count * 220) / 1024, 0)))
        if ($EnableRules) {
            Write-iSOCLog 'The fixture analytics rules will be created ENABLED. They will execute on a schedule against production data.' -Level Warning
            Write-iSOCLog 'Incident creation stays off, and Informational severity is retained.' -Level Warning
            if ($EnableRulesWithLiveQuery) { Write-iSOCLog 'The zero-row clamp has ALSO been removed. This is the only configuration in which a fixture rule can raise an alert.' -Level Warning }
        }
    }

    Write-iSOCLog ''
    foreach ($row in $Fixture.Rows) {
        $markerText = if ($row.Marker) { "  [marker: $($row.Marker)]" } else { '' }
        Write-iSOCLog ('  {0,-8} {1,-13} {2}{3}' -f $row.Action, $row.Type, $row.Name, $markerText)
    }
    Write-iSOCLog ''
    if (-not $ForRemoval) { Write-iSOCLog 'Nothing has been created yet.' }
}
