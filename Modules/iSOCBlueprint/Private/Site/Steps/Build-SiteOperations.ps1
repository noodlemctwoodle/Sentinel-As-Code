#Requires -Version 7.6

<#
.SYNOPSIS
    Build the hunts, playbook health and threat intelligence figures.

.DESCRIPTION
    A step of the SharePoint site build. Steps run in order and pass their results
    to later ones through the build context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Steps/Build-SiteOperations.ps1
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

function Build-SiteOperations {
    <#
    .SYNOPSIS
        Build the hunts, playbook health and threat intelligence figures.

    .PARAMETER Context
        The build context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the build context.
    $bookmarkRows = $Context.bookmarkRows
    $counts = $Context.counts
    $huntRows = $Context.huntRows
    $incSummaryRow = $Context.incSummaryRow
    $runRows = $Context.runRows
    $tiCountRows = $Context.tiCountRows
    $tiObjectRows = $Context.tiObjectRows

    # When the bookmarks list was too large to fetch, the collector keeps the
    # count the service reported.
    $bookmarkCount = @($bookmarkRows | Where-Object { $_ }).Count
    if (-not (Test-Path -LiteralPath (Join-Path $script:RawRoot 'bookmarks.json'))) {
        $bookmarkCountDoc = Read-SiteRaw 'bookmarks-count.json'
        # Neither file: the count is unknown, not zero.
        $bookmarkCount = if ($bookmarkCountDoc -and $bookmarkCountDoc.PSObject.Properties['Count']) {
            [int](ConvertTo-BuildNumber $bookmarkCountDoc.Count)
        } else { $null }
    }
    $huntsSummary = [ordered]@{
        captured       = (Test-Path -LiteralPath (Join-Path $script:RawRoot 'hunts.json'))
        hunts          = @($huntRows | Where-Object { $_ }).Count
        bookmarks      = $bookmarkCount
        huntingQueries = $counts.hunting
    }

    $pbRuns = 0; $pbFailed = 0; $pbFailing = @(); $pbUnavailable = 0
    foreach ($r in ($runRows | Where-Object { $_ })) {
        if ($r.PSObject.Properties['LastRunStatus'] -and [string]$r.LastRunStatus -eq 'Unavailable') { $pbUnavailable++; continue }
        $runs = [int](ConvertTo-BuildNumber $r.Runs7d); $failed = [int](ConvertTo-BuildNumber $r.Failed7d)
        $pbRuns += $runs; $pbFailed += $failed
        if ($failed -gt 0) {
            $last = if ($r.LastFailureUtc) { ([datetime]$r.LastFailureUtc).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') } else { '' }
            $pbFailing += [ordered]@{ playbook = $r.Playbook; runs = $runs; failed = $failed; lastFailure = $last }
        }
    }
    $playbookHealth = [ordered]@{
        runs7d      = $pbRuns
        failed7d    = $pbFailed
        playbooks   = @($runRows | Where-Object { $_ }).Count
        unavailable = $pbUnavailable
        failing     = @($pbFailing | Sort-Object { $_.failed } -Descending)
    }

    $tiBySource = @()
    foreach ($row in ($tiCountRows | Where-Object { $_ } | Sort-Object { ConvertTo-BuildNumber $_.Count } -Descending)) {
        $tiBySource += [ordered]@{ source = [string]$row.SourceSystem; count = [long](ConvertTo-BuildNumber $row.Count) }
    }
    $tiObjects = @()
    foreach ($row in ($tiObjectRows | Where-Object { $_ } | Sort-Object { ConvertTo-BuildNumber $_.Count } -Descending)) {
        $tiObjects += [ordered]@{ type = [string]$row.StixType; count = [long](ConvertTo-BuildNumber $row.Count) }
    }

    # The Overview's alert lifecycle: alerts to incidents, then how the closed ones
    # were closed and how severe the open ones are. closedBy and openBySeverity
    # are null for a snapshot collected before those bags were captured.
    $closedByMap = $null
    if ($incSummaryRow -and $incSummaryRow.PSObject.Properties['ClosedBy'] -and $null -ne $incSummaryRow.ClosedBy) {
        $bag = Get-BuildBag $incSummaryRow.ClosedBy
        $closedByMap = [ordered]@{}
        foreach ($k in 'AutomationRule', 'Analyst', 'DefenderXdr', 'Other') { $closedByMap[$k] = $(if ($bag.Contains($k)) { [long]$bag[$k] } else { [long]0 }) }
    }
    $openBySeverityMap = $null
    if ($incSummaryRow -and $incSummaryRow.PSObject.Properties['OpenBySeverity'] -and $null -ne $incSummaryRow.OpenBySeverity) {
        $bag = Get-BuildBag $incSummaryRow.OpenBySeverity
        $openBySeverityMap = [ordered]@{}
        foreach ($k in 'High', 'Medium', 'Low', 'Informational') { $openBySeverityMap[$k] = $(if ($bag.Contains($k)) { [long]$bag[$k] } else { [long]0 }) }
    }
    $mttrRows = @(Read-SiteRawArray 'incidents-mttr.json')
    $mttrRow = if ($mttrRows.Count -gt 0) { $mttrRows[0] } else { $null }
    $alertLifecycle = [ordered]@{
        closedBy       = $closedByMap
        openBySeverity = $openBySeverityMap
        mttrMinutes    = $(
            if ($mttrRow -and $mttrRow.PSObject.Properties['MTTRMinutes'] -and "$($mttrRow.MTTRMinutes)" -ne '') {
                [math]::Round((ConvertTo-BuildNumber $mttrRow.MTTRMinutes), 1)
            } else { $null }
        )
    }

    # Left in the build context for later steps.
    $Context.alertLifecycle = $alertLifecycle
    if (Get-Variable -Name 'bag' -Scope 0 -ErrorAction Ignore) { $Context.bag = $bag }
    $Context.huntsSummary = $huntsSummary
    $Context.k = $k
    $Context.playbookHealth = $playbookHealth
    $Context.r = $r
    $Context.tiBySource = $tiBySource
    $Context.tiObjects = $tiObjects
}
