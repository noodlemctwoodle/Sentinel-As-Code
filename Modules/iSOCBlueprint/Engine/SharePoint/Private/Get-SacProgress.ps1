#Requires -Version 7.2

<#
.SYNOPSIS
    One run's progress record, and the history of them the dashboard's
    Progress tab compares.

.DESCRIPTION
    Each export is a snapshot: the window slider re-scopes its activity, but
    posture (rules enabled, findings, criteria, coverage) is as it was on the
    day. To show change, every site build writes a progress record for its
    run: the headline numbers and the lists a change is read from. The
    records are kept as a history:

      progress.json          this run's record, in the bundle
      progress-history.json  every kept day's record, oldest first: in the
                             bundle from earlier day folders (a local run),
                             and on the site, where the publisher adds each
                             run's record (a pipeline run starts with no
                             earlier folders)

    The dashboard compares the run it shows with a baseline from the
    history: the previous run, a run 7, 30 or 90 days earlier, or the first.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/SharePoint/Private/Get-SacProgress.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.1.0
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

function Get-SacProgressValue {
    <#
    .SYNOPSIS
        A property of a dictionary or an object, or $null; a dotted path
        walks down ('maturity.overall.score').
    #>
    [CmdletBinding()]
    param([AllowNull()] $Object, [Parameter(Mandatory)] [string] $Path)
    $cur = $Object
    foreach ($part in $Path.Split('.')) {
        if ($null -eq $cur) { return $null }
        if ($cur -is [System.Collections.IDictionary]) { $cur = if ($cur.Contains($part)) { $cur[$part] } else { $null } }
        elseif ($cur.PSObject.Properties[$part]) { $cur = $cur.PSObject.Properties[$part].Value }
        else { return $null }
    }
    $cur
}

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
    for ($i = 0; $i -lt $rules.Count; $i++) { if ($rules[$i] -and (Get-SacProgressValue -Object $rules[$i] -Path 'enabled') -eq $true) { [void]$enabled.Add($i) } }
    # Counted, not tested for truth: a match on rule 0 would read as false.
    $techniques = @(@(& $v 'attack.cells') | Where-Object { $_ } | Where-Object {
            @(@(Get-SacProgressValue -Object $_ -Path 'rules') | Where-Object { $null -ne $_ -and $enabled.Contains([int]$_) }).Count -gt 0
        } | ForEach-Object { [string](Get-SacProgressValue -Object $_ -Path 'technique') } | Where-Object { $_ } | Sort-Object -Unique)
    $ruleNames = @($rules | Where-Object { $_ -and (Get-SacProgressValue -Object $_ -Path 'enabled') -eq $true } | ForEach-Object { [string](Get-SacProgressValue -Object $_ -Path 'name') } | Where-Object { $_ } | Sort-Object -Unique)

    $estateTables = @(@(& $v 'estate.tables') | Where-Object { $_ })
    $tables = @($estateTables | ForEach-Object { [string](Get-SacProgressValue -Object $_ -Path 'table') } | Where-Object { $_ } | Sort-Object -Unique)
    $uncovered = @($estateTables | Where-Object { (Get-SacProgressValue -Object $_ -Path 'covered') -ne $true } | ForEach-Object { [string](Get-SacProgressValue -Object $_ -Path 'table') } | Where-Object { $_ } | Sort-Object -Unique)

    $findings = @(@(& $v 'findings.items') | Where-Object { $_ } | ForEach-Object {
            [ordered]@{ id = [string](Get-SacProgressValue -Object $_ -Path 'id'); severity = [string](Get-SacProgressValue -Object $_ -Path 'severity'); title = [string](Get-SacProgressValue -Object $_ -Path 'title') }
        } | Sort-Object { $_.id })
    $statusCode = @{ Met = 'M'; Gap = 'G' }
    $criteria = @(@(& $v 'maturity.criteria') | Where-Object { $_ } | ForEach-Object {
            $st = [string](Get-SacProgressValue -Object $_ -Path 'status')
            [ordered]@{ id = [string](Get-SacProgressValue -Object $_ -Path 'id'); name = [string](Get-SacProgressValue -Object $_ -Path 'name'); status = $(if ($statusCode.ContainsKey($st)) { $statusCode[$st] } else { 'U' }) }
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
        $props = if ($openBy -is [System.Collections.IDictionary]) { $openBy.Values } else { $openBy.PSObject.Properties | ForEach-Object Value }
        foreach ($n in $props) { if ($null -ne $n) { $open += [int]$n } }
    }
    $daily = @(@(& $v 'usageDaily') | Where-Object { $_ })
    $dailyGb = if ($daily.Count) { [math]::Round((($daily | ForEach-Object { [double](Get-SacProgressValue -Object $_ -Path 'billable') }) | Measure-Object -Sum).Sum / $daily.Count, 2) } else { $null }
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

function Merge-SacProgressHistory {
    <#
    .SYNOPSIS
        A history with the given records added: one record a day (a later
        record for the same day replaces the earlier), oldest first, and
        none older than -Days before the newest. Pure; the inputs are not
        changed.

    .PARAMETER History
        The history so far, @{ entries = @(...) }, or $null.

    .PARAMETER Records
        Records to add.

    .PARAMETER Days
        How many days back from the newest record to keep. Defaults to 90.

    .OUTPUTS
        [ordered] schemaVersion and entries.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] $History,
        [AllowNull()] [AllowEmptyCollection()] [object[]] $Records = @(),
        [ValidateRange(1, 3650)] [int] $Days = 90
    )
    $byDate = [ordered]@{}
    $add = {
        param($r)
        if ($null -eq $r) { return }
        $d = [string](Get-SacProgressValue -Object $r -Path 'date')
        if ($d -match '^\d{4}-\d{2}-\d{2}$') { $byDate[$d] = $r }
    }
    foreach ($e in @(Get-SacProgressValue -Object $History -Path 'entries')) { & $add $e }
    foreach ($r in @($Records)) { & $add $r }
    $dates = @($byDate.Keys | Sort-Object)
    if ($dates.Count) {
        $cutoff = [datetime]::ParseExact($dates[-1], 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture).AddDays(1 - $Days).ToString('yyyy-MM-dd')
        $dates = @($dates | Where-Object { [string]::CompareOrdinal($_, $cutoff) -ge 0 })
    }
    [ordered]@{ schemaVersion = 1; entries = @($dates | ForEach-Object { $byDate[$_] }) }
}
