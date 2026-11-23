#Requires -Version 7.6

<#
.SYNOPSIS
    Build the daily series the dashboard slider re-scopes.

.DESCRIPTION
    A step of the SharePoint site build. Steps run in order and pass their results
    to later ones through the build context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Steps/Build-SiteDaily.ps1
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

function Build-SiteDaily {
    <#
    .SYNOPSIS
        Build the daily series the dashboard slider re-scopes.

    .PARAMETER Context
        The build context: the figures earlier steps produced and this one adds to.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'lakeEnrolled', Justification = 'Read by Get-FlowPlanLabel from this function scope, which the analyser cannot see.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the build context.
    $alertRaw = $Context.alertRaw
    $cost = $Context.cost
    $customDetPerTable = $Context.customDetPerTable
    $id = $Context.id
    $k = $Context.k
    $key = $Context.key
    $lakeEnrolled = $Context.lakeEnrolled
    $lookbackDays = $Context.lookbackDays
    $n = $Context.n
    $o = $Context.o
    $prod = $Context.prod
    $queryRuleKeys = $Context.queryRuleKeys
    $r = $Context.r
    $referencedTables = $Context.referencedTables
    $ruleIdKey = $Context.ruleIdKey
    $rulesPerTableBuild = $Context.rulesPerTableBuild
    $rulesQueryEnabled = $Context.rulesQueryEnabled
    $runCtx = $Context.runCtx
    $runRows = $Context.runRows
    $src = $Context.src
    $v = $Context.v
    $wsTableByName = $Context.wsTableByName

    # ---- Daily series for the dashboard's slider ----
    # The collector's daily captures count per day ago (0 = the last 24 hours)
    # over the daily span (the lookback, at most 90). The dashboard sums the
    # last N of them to rebuild every windowed card for N days, so each series
    # carries what that needs: a table's family, plan, flow tier, price per GB
    # and coverage; an alert's product, severity, provider, product family and
    # rule; an incident's state; a rule's verdicts; health events; playbook runs.
    # Sparse: one [daysAgo, values...] entry per day that has any. A run
    # collected before the daily captures existed has none, and the dashboard
    # keeps its collected window without a slider.
    $daily = $null
    $dailyDays = 0
    if ($runCtx -and $runCtx.PSObject.Properties['DailyDays'] -and [int]$runCtx.DailyDays -ge 1) { $dailyDays = [int]$runCtx.DailyDays }
    if ($dailyDays -gt 0 -and (Test-Path -LiteralPath (Join-Path $script:RawRoot 'daily-table-usage.json'))) {
        $dayOf = { param($r) [int](ConvertTo-BuildNumber $r.DaysAgo) }
        $inSpan = { param($k) $k -ge 0 -and $k -lt $dailyDays }
        # Price per GB of a table's billable data, as the cost estimate priced
        # it (its monthly cost over its window GB projected to 30 days). An
        # estimate without every table's row (an older collector's) cannot be
        # re-priced, so costed says whether the dashboard may rebuild cost and
        # the billing flow or must keep the collected ones.
        $unitByTable = @{}; $planByTable = @{}; $grantByTable = @{}
        $costed = [bool]($cost -and $cost.PSObject.Properties['AllTablesByCost'])
        if ($costed) {
            foreach ($t in @($cost.AllTablesByCost | Where-Object { $_ })) {
                $gbW = [double]$t.Gb30d
                $planByTable[[string]$t.Table] = [string]$t.Plan
                if ((Get-FlowBilledGb $t 1.0) -eq 0) { $grantByTable[[string]$t.Table] = $true }
                if ($gbW -gt 0) { $unitByTable[[string]$t.Table] = [double]$t.MonthlyCost / ($gbW * 30.0 / $lookbackDays) }
            }
        }
        $sparse = { param($map) @($map.Keys | Sort-Object | ForEach-Object { , [object[]]$map[$_] }) }

        $dTables = [System.Collections.Generic.List[object]]::new()
        $byTable = [ordered]@{}
        # Read-SiteRawArray emits the array as one object, so hold each before iterating.
        $dailyTableRaw = Read-SiteRawArray 'daily-table-usage.json'
        foreach ($r in @($dailyTableRaw | Where-Object { $_ -and $_.DataType })) {
            $k = & $dayOf $r; if (-not (& $inSpan $k)) { continue }
            $n = [string]$r.DataType
            if (-not $byTable.Contains($n)) { $byTable[$n] = @{} }
            $prev = if ($byTable[$n].ContainsKey($k)) { [double]$byTable[$n][$k][1] } else { 0.0 }
            $byTable[$n][$k] = @($k, [math]::Round($prev + (ConvertTo-BuildNumber $r.GB), 4))
        }
        foreach ($n in $byTable.Keys) {
            $plan = if ($planByTable.ContainsKey($n)) {
                $planByTable[$n]
            } elseif ($wsTableByName.ContainsKey($n) -and $wsTableByName[$n].properties -and $wsTableByName[$n].properties.PSObject.Properties['plan']) {
                [string]$wsTableByName[$n].properties.plan
            } else { 'Analytics' }
            $dTables.Add([ordered]@{
                    t = $n; f = (Get-TableFamily $n); plan = $plan; pl = (Get-FlowPlanLabel -Table $n -Plan $plan)
                    u   = $(if ($unitByTable.ContainsKey($n)) { [math]::Round($unitByTable[$n], 6) } else { 0 })
                    r   = $(if ($rulesPerTableBuild.ContainsKey($n)) { $rulesPerTableBuild[$n] } else { 0 })
                    cd  = $(if ($customDetPerTable.ContainsKey($n)) { $customDetPerTable[$n] } else { 0 })
                    cov = $referencedTables.ContainsKey($n)
                    b   = $grantByTable.ContainsKey($n)
                    d   = @(& $sparse $byTable[$n])
                })
        }

        $dAlerts = [System.Collections.Generic.List[object]]::new()
        $byAlert = [ordered]@{}
        $dailyAlertRaw = Read-SiteRawArray 'daily-alerts.json'
        foreach ($r in @($dailyAlertRaw | Where-Object { $_ })) {
            $k = & $dayOf $r; if (-not (& $inSpan $k)) { continue }
            $prod = [string]$r.ProductName
            $key = @([string]$r.AlertName, $prod, [string]$r.AlertSeverity, [string]$r.ProviderName, (& $ruleIdKey $r.AlertRuleId)) -join "`u{1f}"
            if (-not $byAlert.Contains($key)) {
                $byAlert[$key] = [ordered]@{ n = [string]$r.AlertName; p = $prod; s = [string]$r.AlertSeverity; pv = [string]$r.ProviderName
                    pf   = $(if ($prod -and $prod -notmatch 'Sentinel') { Get-ProductFamily -Product $prod } else { '' })
                    r    = (& $ruleIdKey $r.AlertRuleId)
                    days = @{}
                }
            }
            $prev = if ($byAlert[$key].days.ContainsKey($k)) { [long]$byAlert[$key].days[$k][1] } else { 0 }
            $byAlert[$key].days[$k] = @($k, ($prev + [long](ConvertTo-BuildNumber $r.Alerts)))
        }
        foreach ($a in $byAlert.Values) { $a.d = @(& $sparse $a.days); $a.Remove('days'); $dAlerts.Add($a) }

        $dIncidents = [System.Collections.Generic.List[object]]::new()
        $byInc = [ordered]@{}
        $dailyIncRaw = Read-SiteRawArray 'daily-incidents.json'
        foreach ($r in @($dailyIncRaw | Where-Object { $_ })) {
            $k = & $dayOf $r; if (-not (& $inSpan $k)) { continue }
            $key = @([string]$r.Severity, [string]$r.Status, [string]$r.Class, [string]$r.ClosedBy) -join "`u{1f}"
            if (-not $byInc.Contains($key)) {
                $byInc[$key] = [ordered]@{ sev = [string]$r.Severity; st = [string]$r.Status; c = [string]$r.Class; by = [string]$r.ClosedBy; days = @{} }
            }
            $v = @(
                [long](ConvertTo-BuildNumber $r.Incidents), [long](ConvertTo-BuildNumber $r.AckCount), [double](ConvertTo-BuildNumber $r.AckSum),
                [long](ConvertTo-BuildNumber $r.RsvCount), [double](ConvertTo-BuildNumber $r.RsvSum)
            )
            if ($byInc[$key].days.ContainsKey($k)) { $o = $byInc[$key].days[$k]; for ($i = 0; $i -lt 5; $i++) { $o[$i + 1] += $v[$i] } }
            else { $byInc[$key].days[$k] = @($k) + $v }
        }
        foreach ($a in $byInc.Values) { $a.d = @(& $sparse $a.days); $a.Remove('days'); $dIncidents.Add($a) }

        # A rule is named as the workspace names it, by its rule id; another
        # product's alerts keep their alert name.
        $ruleNameById = @{}
        foreach ($r in @($alertRaw | Where-Object { $_ })) {
            $rid = ([string]$r.name).ToLowerInvariant()
            $dn = if ($r.properties -and $r.properties.PSObject.Properties['displayName']) { [string]$r.properties.displayName } else { '' }
            if ($rid -and $dn) { $ruleNameById[$rid] = $dn }
        }
        $dRules = [System.Collections.Generic.List[object]]::new()
        $byRule = [ordered]@{}
        $dailyRuleRaw = Read-SiteRawArray 'daily-rule-incidents.json'
        foreach ($r in @($dailyRuleRaw | Where-Object { $_ })) {
            $k = & $dayOf $r; if (-not (& $inSpan $k)) { continue }
            $id = & $ruleIdKey $(if ($r.PSObject.Properties['AlertRuleId']) { $r.AlertRuleId } else { '' })
            $alertName = [string]$r.RuleName
            $key = if ($id) { $id } else { $alertName }
            if (-not $byRule.Contains($key)) {
                $src = if ($id) {
                    'Analytics rule'
                } elseif ([string]$r.Product) { [string]$r.Product } elseif ([string]$r.Provider) { [string]$r.Provider } else { 'Other' }
                $byRule[$key] = [ordered]@{
                    id   = $id
                    an   = $alertName
                    n    = $(if ($id -and $ruleNameById.ContainsKey($id)) { $ruleNameById[$id] } else { $alertName })
                    src  = $src
                    days = @{}
                }
            }
            $v = @(
                'Incidents', 'Closed', 'TruePositive', 'FalsePositive', 'BenignPositive', 'Undetermined' |
                    ForEach-Object { [long](ConvertTo-BuildNumber $r.$_) }
            )
            if ($byRule[$key].days.ContainsKey($k)) { $o = $byRule[$key].days[$k]; for ($i = 0; $i -lt 6; $i++) { $o[$i + 1] += $v[$i] } }
            else { $byRule[$key].days[$k] = @($k) + $v }
        }
        foreach ($a in $byRule.Values) { $a.d = @(& $sparse $a.days); $a.Remove('days'); $dRules.Add($a) }

        $dHealth = [System.Collections.Generic.List[object]]::new()
        $byHealth = [ordered]@{}
        $dailyHealthRaw = Read-SiteRawArray 'daily-health.json'
        foreach ($r in @($dailyHealthRaw | Where-Object { $_ })) {
            $k = & $dayOf $r; if (-not (& $inSpan $k)) { continue }
            $key = "$([string]$r.OperationName)`u{1f}$([string]$r.Status)"
            if (-not $byHealth.Contains($key)) { $byHealth[$key] = [ordered]@{ o = [string]$r.OperationName; st = [string]$r.Status; days = @{} } }
            $prev = if ($byHealth[$key].days.ContainsKey($k)) { [long]$byHealth[$key].days[$k][1] } else { 0 }
            $byHealth[$key].days[$k] = @($k, ($prev + [long](ConvertTo-BuildNumber $r.LogCount)))
        }
        foreach ($a in $byHealth.Values) { $a.d = @(& $sparse $a.days); $a.Remove('days'); $dHealth.Add($a) }

        $dPlaybooks = [System.Collections.Generic.List[object]]::new()
        foreach ($r in @($runRows | Where-Object { $_ })) {
            $days = @{}
            foreach ($x in @($(if ($r.PSObject.Properties['Daily']) { $r.Daily } else { @() }) | Where-Object { $_ })) {
                $k = [int](ConvertTo-BuildNumber $x.DaysAgo); if (-not (& $inSpan $k)) { continue }
                $days[$k] = @($k, [long](ConvertTo-BuildNumber $x.Runs), [long](ConvertTo-BuildNumber $x.Failed))
            }
            $dPlaybooks.Add([ordered]@{
                    n           = [string]$r.Playbook
                    unavailable = ($r.PSObject.Properties['LastRunStatus'] -and [string]$r.LastRunStatus -eq 'Unavailable')
                    last        = $(if ($r.LastFailureUtc) { ([datetime]$r.LastFailureUtc).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') } else { '' })
                    d           = @(& $sparse $days)
                })
        }

        $daily = [ordered]@{
            span              = $dailyDays
            asOf              = $(
                if ($runCtx -and $runCtx.StartedAtUtc) { ([datetime]$runCtx.StartedAtUtc).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { '' }
            )
            costed            = $costed
            rulesQueryEnabled = $rulesQueryEnabled
            queryRules        = @($queryRuleKeys.Keys | Sort-Object)
            tables            = $dTables
            alerts            = $dAlerts
            incidents         = $dIncidents
            rules             = $dRules
            health            = $dHealth
            playbooks         = $dPlaybooks
        }
    }

    # Left in the build context for later steps.
    $Context.daily = $daily
    if (Get-Variable -Name 'id' -Scope 0 -ErrorAction Ignore) { $Context.id = $id }
}
