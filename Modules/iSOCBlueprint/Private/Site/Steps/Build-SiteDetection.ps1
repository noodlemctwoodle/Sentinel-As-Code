#Requires -Version 7.6

<#
.SYNOPSIS
    Build rule effectiveness, daily usage and the detection outcomes.

.DESCRIPTION
    A step of the SharePoint site build. Steps run in order and pass their results
    to later ones through the build context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Steps/Build-SiteDetection.ps1
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

function Build-SiteDetection {
    <#
    .SYNOPSIS
        Build rule effectiveness, daily usage and the detection outcomes.

    .PARAMETER Context
        The build context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the build context.
    $customDetRefs = $Context.customDetRefs
    $effectRows = $Context.effectRows
    $firedRows = $Context.firedRows
    $k = $Context.k
    $n = $Context.n
    $referencedTables = $Context.referencedTables
    $ruleRefs = $Context.ruleRefs
    $tablesData = $Context.tablesData
    $templateRefs = $Context.templateRefs
    $usageRows = $Context.usageRows

    $effectiveness = @()
    # Sentinel rules first, then other products' alerts by name.
    $effectSorted = @($effectRows | Where-Object { $_ } | Sort-Object { -(ConvertTo-BuildNumber $_.Incidents) } | Sort-Object { if ($_.PSObject.Properties['AlertRuleId'] -and $_.AlertRuleId) { 0 } else { 1 } } -Stable)
    foreach ($e in $effectSorted) {
        $src = if ($e.PSObject.Properties['Source'] -and $e.Source) { [string]$e.Source } elseif ($e.PSObject.Properties['AlertRuleId'] -and $e.AlertRuleId) { 'Analytics rule' } else { 'Other' }
        $effectiveness += [ordered]@{
            rule = $e.RuleName; source = $src; incidents = [int](ConvertTo-BuildNumber $e.Incidents); closed = [int](ConvertTo-BuildNumber $e.Closed)
            tp = [int](ConvertTo-BuildNumber $e.TruePositive); fp = [int](ConvertTo-BuildNumber $e.FalsePositive); bp = [int](ConvertTo-BuildNumber $e.BenignPositive)
            undetermined = [int](ConvertTo-BuildNumber $e.Undetermined); fpRate = [math]::Round((ConvertTo-BuildNumber $e.FPRate), 1)
        }
    }

    $usageDaily = @()
    foreach ($u in ($usageRows | Where-Object { $_ } | Sort-Object { [datetime]$_.Day } | Select-Object -Last 90)) {
        $usageDaily += [ordered]@{ day = ([datetime]$u.Day).ToUniversalTime().ToString('yyyy-MM-dd'); billable = [math]::Round((ConvertTo-BuildNumber $u.BillableGB), 2); free = [math]::Round((ConvertTo-BuildNumber $u.FreeGB), 2) }
    }

    # Tables with data that no enabled rule reads, with the undeployed templates
    # that would cover them (section 28's content; the dashboard shows twelve
    # and a Show all control for the rest).
    $detectionOpportunities = @()
    $uncoveredTotal = 0
    if ($ruleRefs.Count -gt 0) {
        # A template only a deprecated Content Hub solution ships is not one to
        # enable, as on the report page.
        # Read-SiteRawArray emits each array as one object, so hold them first: passed
        # straight in, each list arrived as a single item and every template read
        # as Built-in.
        $pkgInstalled = Read-SiteRawArray 'content-packages.json'
        $pkgCatalogue = Read-SiteRawArray 'content-product-packages.json'
        $tplSolutions = Get-TemplateSolutionMap -Installed $pkgInstalled -Catalogue $pkgCatalogue
        $undeployed = @($templateRefs | Where-Object { $_ -and $_.Deprecated -ne $true -and $_.AlreadyDeployed -ne $true -and -not (Test-TemplateRetired -Map $tplSolutions -TemplateId ([string]$_.TemplateId)) })
        $sevRank2 = @{ High = 0; Medium = 1; Low = 2; Informational = 3 }
        $operationalOnly = @('SecurityIncident', 'SecurityAlert', 'Usage', 'Operation', 'LAQueryLogs', 'SentinelHealth', 'SentinelAudit', 'AzureMetrics')
        $uncovered = @($tablesData | Where-Object {
            $_ -and $_.DataType -and (ConvertTo-BuildNumber $_.BillableLast30d) -gt 0 -and
            -not $referencedTables.ContainsKey([string]$_.DataType) -and ([string]$_.DataType) -notin $operationalOnly
        } | Sort-Object { ConvertTo-BuildNumber $_.BillableLast30d } -Descending)
        $uncoveredTotal = $uncovered.Count
        foreach ($t in $uncovered) {
            $name = [string]$t.DataType
            $cands = @($undeployed | Where-Object { @($_.Tables) -contains $name } | Sort-Object { $sv = [string]$_.Severity; if ($sevRank2.ContainsKey($sv)) { $sevRank2[$sv] } else { 9 } }, DisplayName)
            $detectionOpportunities += [ordered]@{
                table     = $name
                family    = (Get-TableFamily $name)
                gb30d     = [math]::Round((ConvertTo-BuildNumber $t.BillableLast30d), 2)
                templates = @($cands | ForEach-Object { $sol = Get-TemplateSolution -Map $tplSolutions -TemplateId ([string]$_.TemplateId); [ordered]@{ name = $_.DisplayName; severity = $_.Severity; solution = $sol.Solution; installed = $sol.Installed } })
            }
        }
    }

    # The Data flow tab's detection outcomes: every enabled analytics rule and
    # Defender XDR custom detection that reads a workspace table, the tables it
    # reads, its health and the incidents it raised by classification (30 days).
    # Health: Failing when the rule had run failures (SentinelHealth, 7 days),
    # Working when it raised alerts or incidents, Silent otherwise. Rules join
    # the alert and incident captures by rule id, then by name; custom
    # detections, which carry no rule id there, by name.
    $ruleIdKey = { param($id) $k = ([string]$id).ToLowerInvariant(); if ($k -match '/') { ($k -split '/')[-1] } else { $k } }
    $effById = @{}; $effByName = @{}
    foreach ($e in @($effectRows | Where-Object { $_ })) {
        $k = & $ruleIdKey $(if ($e.PSObject.Properties['AlertRuleId']) { $e.AlertRuleId } else { '' })
        if ($k) { $effById[$k] = $e }
        $n = [string]$(if ($e.PSObject.Properties['RuleName']) { $e.RuleName } else { '' })
        if ($n -and -not $effByName.ContainsKey($n)) { $effByName[$n] = $e }
    }
    $firedById = @{}; $firedByName = @{}
    foreach ($f in @($firedRows | Where-Object { $_ })) {
        $k = & $ruleIdKey $(if ($f.PSObject.Properties['AlertRuleId']) { $f.AlertRuleId } else { '' })
        if ($k) { $firedById[$k] = $f }
        $n = [string]$(if ($f.PSObject.Properties['AlertName']) { $f.AlertName } else { '' })
        if ($n -and -not $firedByName.ContainsKey($n)) { $firedByName[$n] = $f }
    }
    # Read-SiteRawArray emits the array as one object, so hold it before iterating.
    $ruleHealthRaw = Read-SiteRawArray 'rule-health.json'
    $ruleFailures = @{}
    foreach ($h in @($ruleHealthRaw | Where-Object { $_ })) {
        $fails = [long](ConvertTo-BuildNumber $(if ($h.PSObject.Properties['Failures']) { $h.Failures } else { 0 }))
        if ($fails -gt 0 -or [string]$(if ($h.PSObject.Properties['Status']) { $h.Status } else { '' }) -eq 'Failure') { $ruleFailures[[string]$h.RuleName] = [math]::Max($fails, 1) }
    }
    $outcomeOf = {
        param($e)
        $num = { param($o, $n) if ($o -and $o.PSObject.Properties[$n]) { [long](ConvertTo-BuildNumber $o.$n) } else { [long]0 } }
        $inc = & $num $e 'Incidents'; $closed = & $num $e 'Closed'
        $tp = & $num $e 'TruePositive'; $fp = & $num $e 'FalsePositive'; $bp = & $num $e 'BenignPositive'; $und = & $num $e 'Undetermined'
        [ordered]@{ incidents = $inc; closed = $closed; tp = $tp; fp = $fp; bp = $bp; undetermined = $und
            unclassified = [math]::Max(0, $closed - $tp - $fp - $bp - $und); open = [math]::Max(0, $inc - $closed) }
    }
    $detectionOutcomes = @()
    foreach ($r in @($ruleRefs | Where-Object { $_ -and $_.Enabled -eq $true -and @($_.Tables | Where-Object { $_ }).Count -gt 0 })) {
        $k = & $ruleIdKey $r.RuleId; $n = [string]$r.RuleName
        $e = if ($k -and $effById.ContainsKey($k)) { $effById[$k] } elseif ($effByName.ContainsKey($n)) { $effByName[$n] } else { $null }
        $f = if ($k -and $firedById.ContainsKey($k)) { $firedById[$k] } elseif ($firedByName.ContainsKey($n)) { $firedByName[$n] } else { $null }
        $o = & $outcomeOf $e
        $alerts = if ($f) { [long](ConvertTo-BuildNumber $f.Alerts) } else { [long]0 }
        $fails = if ($ruleFailures.ContainsKey($n)) { $ruleFailures[$n] } else { [long]0 }
        $detectionOutcomes += [ordered]@{
            name = $n; key = $k; kind = [string]$r.Kind; source = 'Sentinel'; tables = @($r.Tables | Where-Object { $_ } | ForEach-Object { [string]$_ })
            health = $(if ($fails -gt 0) { 'Failing' } elseif ($alerts -gt 0 -or $o.incidents -gt 0) { 'Working' } else { 'Silent' })
            failures = $fails; alerts = $alerts
        } + $o
    }
    foreach ($r in @($customDetRefs | Where-Object { $_ -and $_.Enabled -eq $true -and @($_.Tables | Where-Object { $_ }).Count -gt 0 })) {
        $n = [string]$r.RuleName
        $o = & $outcomeOf $(if ($effByName.ContainsKey($n)) { $effByName[$n] } else { $null })
        $detectionOutcomes += [ordered]@{
            name = $n; key = ''; kind = 'Custom detection'; source = 'Defender XDR'; tables = @($r.Tables | Where-Object { $_ } | ForEach-Object { [string]$_ })
            health = $(if ($o.incidents -gt 0) { 'Working' } else { 'Silent' }); failures = [long]0; alerts = [long]0
        } + $o
    }
    $healthRank = @{ Failing = 0; Working = 1; Silent = 2 }
    $detectionOutcomes = @($detectionOutcomes | Sort-Object @{ Expression = { $healthRank[$_.health] } }, @{ Expression = { -[long]$_.incidents } }, @{ Expression = { $_.name } })
    # The source family of every table they read, for the matrix's columns: a
    # rule can read a table that has no ingestion, so the estate cannot say.
    $detectionTableFamily = [ordered]@{}
    foreach ($o in $detectionOutcomes) { foreach ($t in @($o.tables)) { if (-not $detectionTableFamily.Contains($t)) { $detectionTableFamily[$t] = Get-TableFamily $t } } }

    # Left in the build context for later steps.
    $Context.detectionOpportunities = $detectionOpportunities
    $Context.detectionOutcomes = $detectionOutcomes
    $Context.detectionTableFamily = $detectionTableFamily
    $Context.effectiveness = $effectiveness
    if (Get-Variable -Name 'k' -Scope 0 -ErrorAction Ignore) { $Context.k = $k }
    if (Get-Variable -Name 'n' -Scope 0 -ErrorAction Ignore) { $Context.n = $n }
    if (Get-Variable -Name 'o' -Scope 0 -ErrorAction Ignore) { $Context.o = $o }
    $Context.r = $r
    $Context.ruleIdKey = $ruleIdKey
    if (Get-Variable -Name 'src' -Scope 0 -ErrorAction Ignore) { $Context.src = $src }
    $Context.uncoveredTotal = $uncoveredTotal
    $Context.usageDaily = $usageDaily
}
