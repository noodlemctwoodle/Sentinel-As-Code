#Requires -Version 7.6

<#
.SYNOPSIS
    This run's progress record, from the dashboard model

.DESCRIPTION
    Split from Get-SacProgress.ps1 so each file holds one function.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SiteShared/New-SacProgressRecord.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function New-SacProgressRecord {
    <#
    .SYNOPSIS
        This run's progress record, from the dashboard model.

    .PARAMETER Model
        The dashboard model the site build made.

    .PARAMETER Date
        The run's day, yyyy-MM-dd.

    .PARAMETER GeneratedUtc
        When the inventory was collected.

    .OUTPUTS
        [ordered] date, generatedUtc, windowDays, currency, metrics (the
        headline numbers, $null where not captured), areas (maturity area
        id to score) and sets: findings (id, severity, title), criteria (id,
        name, status M, G or U), rules (enabled analytics rules by name),
        techniques (ATT&CK techniques an enabled rule covers), tables (tables
        ingesting) and uncovered (those no enabled detection reads).
    #>
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Model,
        [Parameter(Mandatory)] [string] $Date,
        [AllowNull()] [AllowEmptyString()] [string] $GeneratedUtc
    )
    $v = { param([string] $Path) Get-SacProgressValue -Object $Model -Path $Path }
    $num = { param($x) if ($null -eq $x -or [string]$x -eq '') { $null } else { [double]$x } }

    # ATT&CK techniques with at least one enabled rule (cells hold indexes
    # into the rule list).
    $rules = @(& $v 'attack.rules')
    $enabled = [System.Collections.Generic.HashSet[int]]::new()
    for ($i = 0; $i -lt $rules.Count; $i++) {
        if ($rules[$i] -and (Get-SacProgressValue -Object $rules[$i] -Path 'enabled') -eq $true) { [void]$enabled.Add($i) }
    }
    # Counted, not tested for truth: a match on rule 0 would read as false.
    $techniques = @(@(& $v 'attack.cells') | Where-Object { $_ } | Where-Object {
            @(@(Get-SacProgressValue -Object $_ -Path 'rules') | Where-Object { $null -ne $_ -and $enabled.Contains([int]$_) }).Count -gt 0
        } | ForEach-Object { [string](Get-SacProgressValue -Object $_ -Path 'technique') } | Where-Object { $_ } | Sort-Object -Unique)
    $ruleNames = @(
        $rules |
            Where-Object { $_ -and (Get-SacProgressValue -Object $_ -Path 'enabled') -eq $true } |
            ForEach-Object { [string](Get-SacProgressValue -Object $_ -Path 'name') } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )

    $estateTables = @(@(& $v 'estate.tables') | Where-Object { $_ })
    $tables = @($estateTables | ForEach-Object { [string](Get-SacProgressValue -Object $_ -Path 'table') } | Where-Object { $_ } | Sort-Object -Unique)
    $uncovered = @(
        $estateTables |
            Where-Object { (Get-SacProgressValue -Object $_ -Path 'covered') -ne $true } |
            ForEach-Object { [string](Get-SacProgressValue -Object $_ -Path 'table') } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )

    $findings = @(@(& $v 'findings.items') | Where-Object { $_ } | ForEach-Object {
            [ordered]@{
                id       = [string](Get-SacProgressValue -Object $_ -Path 'id')
                severity = [string](Get-SacProgressValue -Object $_ -Path 'severity')
                title    = [string](Get-SacProgressValue -Object $_ -Path 'title')
            }
        } | Sort-Object { $_.id })
    $statusCode = @{ Met = 'M'; Gap = 'G' }
    $criteria = @(@(& $v 'maturity.criteria') | Where-Object { $_ } | ForEach-Object {
            $st = [string](Get-SacProgressValue -Object $_ -Path 'status')
            [ordered]@{
                id     = [string](Get-SacProgressValue -Object $_ -Path 'id')
                name   = [string](Get-SacProgressValue -Object $_ -Path 'name')
                status = $(if ($statusCode.ContainsKey($st)) { $statusCode[$st] } else { 'U' })
            }
        } | Sort-Object { $_.id })
    $areas = [ordered]@{}
    foreach ($a in @(& $v 'maturity.areas')) {
        if (-not $a) { continue }
        $id = [string](Get-SacProgressValue -Object $a -Path 'id')
        if ($id) { $areas[$id] = & $num (Get-SacProgressValue -Object $a -Path 'score') }
    }

    $open = $null
    $openBy = & $v 'alertLifecycle.openBySeverity'
    if ($null -ne $openBy) {
        $open = 0
        $props = if ($openBy -is [System.Collections.IDictionary]) { $openBy.Values } else { $openBy.PSObject.Properties | ForEach-Object { $_.Value } }
        foreach ($n in $props) { if ($null -ne $n) { $open += [int]$n } }
    }
    $daily = @(@(& $v 'usageDaily') | Where-Object { $_ })
    $dailyGb = if ($daily.Count) {
        [math]::Round((($daily | ForEach-Object { [double](Get-SacProgressValue -Object $_ -Path 'billable') }) | Measure-Object -Sum).Sum / $daily.Count, 2)
    } else { $null }
    $customCaptured = (& $v 'estate.customDetections.captured') -eq $true
    $mitre = @(& $v 'mitre')

    [ordered]@{
        schemaVersion = 1
        date          = $Date
        generatedUtc  = $GeneratedUtc
        windowDays    = & $num (& $v 'window.days')
        currency      = [string](& $v 'cost.currency')
        metrics       = [ordered]@{
            maturityScore     = & $num (& $v 'maturity.overall.score')
            maturityLevel     = & $num (& $v 'maturity.overall.level')
            criteriaMet       = @($criteria | Where-Object { $_.status -eq 'M' }).Count
            criteriaGap       = @($criteria | Where-Object { $_.status -eq 'G' }).Count
            findings          = & $num (& $v 'findings.total')
            findingsCritical  = & $num (& $v 'findings.bySeverity.Critical')
            findingsWarning   = & $num (& $v 'findings.bySeverity.Warning')
            findingsInfo      = & $num (& $v 'findings.bySeverity.Info')
            rulesEnabled      = & $num (& $v 'counts.rulesEnabled')
            rulesTotal        = & $num (& $v 'counts.rulesTotal')
            customDetections  = $(if ($customCaptured) { & $num (& $v 'estate.customDetections.enabled') } else { $null })
            techniquesCovered = $techniques.Count
            tacticsCovered    = & $num (& $v 'mitreCovered')
            tacticsTotal      = $mitre.Count
            connectors        = & $num (& $v 'counts.connectors')
            tablesIngesting   = $tables.Count
            uncoveredTables   = $uncovered.Count
            uncoveredGb       = & $num (& $v 'estate.uncoveredGb')
            totalGb           = & $num (& $v 'estate.totalGb')
            monthlyCost       = & $num (& $v 'cost.monthlyTotal')
            dailyGb           = $dailyGb
            openIncidents     = $open
            mttrMinutes       = & $num (& $v 'alertLifecycle.mttrMinutes')
        }
        areas         = $areas
        sets          = [ordered]@{
            findings   = $findings
            criteria   = $criteria
            rules      = $ruleNames
            techniques = $techniques
            tables     = $tables
            uncovered  = $uncovered
        }
    }
}
