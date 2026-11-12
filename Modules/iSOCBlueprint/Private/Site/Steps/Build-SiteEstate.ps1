#Requires -Version 7.6

<#
.SYNOPSIS
    Read the estate inputs and build the estate figures.

.DESCRIPTION
    A step of the SharePoint site build. Steps run in order and pass their results
    to later ones through the build context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Steps/Build-SiteEstate.ps1
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

function Build-SiteEstate {
    <#
    .SYNOPSIS
        Read the estate inputs and build the estate figures.

    .PARAMETER Context
        The build context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the build context.
    $alertRaw = $Context.alertRaw
    $counts = $Context.counts
    $fam = $Context.fam
    $gb = $Context.gb
    $k = $Context.k
    $key = $Context.key
    $lookbackDays = $Context.lookbackDays
    $n = $Context.n
    $recentDays = $Context.recentDays
    $rulesEnabled = $Context.rulesEnabled
    $volumes = $Context.volumes

    $ruleRefs      = Read-SiteRawArray 'rule-table-references.json'
    $templateRefs  = Read-SiteRawArray 'template-table-references.json'
    $customDetRefs = Read-SiteRawArray 'custom-detection-table-references.json'
    $customDetCaptured = Test-Path -LiteralPath (Join-Path $script:RawRoot 'defender-custom-detections.json')
    $customDetRaw = Read-SiteRawArray 'defender-custom-detections.json'
    $effectRows    = Read-SiteRawArray 'rule-effectiveness.json'
    $firedRows     = Read-SiteRawArray 'rules-fired.json'
    $runRows       = Read-SiteRawArray 'playbook-runs.json'
    $huntRows      = Read-SiteRawArray 'hunts.json'
    $bookmarkRows  = Read-SiteRawArray 'bookmarks.json'
    $usageRows     = Read-SiteRawArray 'workspace-usage-daily.json'
    $tablesData    = Read-SiteRawArray 'tables-with-data.json'
    # Read-SiteRawArray emits the array as one object, so take the first row by index.
    $incSummaryRows = @(Read-SiteRawArray 'incidents-summary.json')
    $incSummaryRow = if ($incSummaryRows.Count -gt 0) { $incSummaryRows[0] } else { $null }
    $tiCountRows   = Read-SiteRawArray 'threat-intel-counts.json'
    $tiObjectRows  = Read-SiteRawArray 'threat-intel-objects.json'
    $maturityRaw   = Read-SiteRaw 'maturity.json'
    # A failed maturity capture writes '{}', which is truthy, so test for the
    # members the dashboard needs.
    $maturityOk    = ($null -ne $maturityRaw -and $null -ne $maturityRaw.PSObject.Properties['areas'] -and $null -ne $maturityRaw.PSObject.Properties['overall'])

    # Estate: source families -> ingestion -> detection -> alerts -> incidents,
    # the same numbers the Markdown renderer draws on 00 and 01.
    $referencedTables = @{}
    foreach ($r in $ruleRefs) {
        if (-not $r -or $r.Enabled -ne $true) { continue }
        foreach ($t in @($r.Tables)) { if ($t) { $referencedTables[[string]$t] = $true } }
    }
    # Enabled Defender XDR custom detections count as coverage too.
    $customDetPerTable = @{}
    foreach ($r in $customDetRefs) {
        if (-not $r -or $r.Enabled -ne $true) { continue }
        foreach ($t in @($r.Tables)) { if ($t) { $k = [string]$t; $referencedTables[$k] = $true; if (-not $customDetPerTable.ContainsKey($k)) { $customDetPerTable[$k] = 0 }; $customDetPerTable[$k]++ } }
    }
    $famAgg2 = [ordered]@{}
    $tablesActive = 0; $tablesSeen = 0; $tablesCovered = 0; $estateTotalGb = 0.0; $estateCoveredGb = 0.0
    # Enabled rules per table, so the estate flow can list what reads each one.
    $rulesPerTableBuild = @{}
    foreach ($r in $ruleRefs) {
        if (-not $r -or $r.Enabled -ne $true) { continue }
        foreach ($t in @($r.Tables)) { if ($t) { $k = [string]$t; if (-not $rulesPerTableBuild.ContainsKey($k)) { $rulesPerTableBuild[$k] = 0 }; $rulesPerTableBuild[$k]++ } }
    }
    $estateTableRows = @()
    foreach ($t in $tablesData) {
        if (-not $t -or -not $t.DataType) { continue }
        $gb = ConvertTo-BuildNumber $t.BillableLast30d
        if ($gb -le 0) { continue }
        # Seen: data in the lookback. Active: some in the recent window, and
        # coverage is counted among the active tables.
        $isActive = (ConvertTo-BuildNumber $t.BillableLast7d) -gt 0
        $tablesSeen++
        if ($isActive) { $tablesActive++ }
        $estateTotalGb += $gb
        $fam = Get-TableFamily $t.DataType
        if (-not $famAgg2.Contains($fam)) { $famAgg2[$fam] = [ordered]@{ category = $fam; tables = 0; gb = 0.0; coveredGb = 0.0; covered = 0 } }
        $famAgg2[$fam].tables++; $famAgg2[$fam].gb += $gb
        $isCovered = $referencedTables.ContainsKey([string]$t.DataType)
        if ($isCovered) { if ($isActive) { $tablesCovered++ }; $estateCoveredGb += $gb; $famAgg2[$fam].covered++; $famAgg2[$fam].coveredGb += $gb }
        $estateTableRows += [ordered]@{
            table   = [string]$t.DataType
            family  = $fam
            gb      = [math]::Round($gb, 2)
            rules   = $(if ($rulesPerTableBuild.ContainsKey([string]$t.DataType)) { $rulesPerTableBuild[[string]$t.DataType] } else { 0 })
            customDetections = $(if ($customDetPerTable.ContainsKey([string]$t.DataType)) { $customDetPerTable[[string]$t.DataType] } else { 0 })
            covered = $isCovered
        }
    }
    $sortedFams = @($famAgg2.Values | Sort-Object { $_.gb } -Descending)
    $estateSources = @()
    foreach ($f in $sortedFams) {
        $estateSources += [ordered]@{ category = $f.category; tables = $f.tables; gb = [math]::Round($f.gb, 2); coveredGb = [math]::Round($f.coveredGb, 2); covered = $f.covered }
    }
    $alerts30d = [long]0
    foreach ($f in $firedRows) { if ($f) { $alerts30d += [long](ConvertTo-BuildNumber $f.Alerts) } }
    # Every alert in the window from every product, so the alert lifecycle's
    # alerts and incidents count the same things: in a workspace joined to the
    # Defender portal every incident is a Defender XDR one, whichever product
    # raised its alerts. They split into Sentinel's own (its analytics) and
    # the rest (Defender XDR and the Microsoft products feeding it), which the
    # lifecycle draws as two nodes. The scheduled and NRT rules' alerts stay as
    # ruleAlerts. A snapshot without the volumes falls back to the rules'
    # alerts, all counted as Sentinel's.
    $allAlerts30d = [long]0; $sentinelAlerts30d = [long]0; $xdrAlerts30d = [long]0
    foreach ($v in @($volumes | Where-Object { $_ })) {
        $n = [long](ConvertTo-BuildNumber $v.Alerts)
        $allAlerts30d += $n
        if ([string]$(if ($v.PSObject.Properties['ProductName']) { $v.ProductName } else { '' }) -match 'Sentinel') { $sentinelAlerts30d += $n } else { $xdrAlerts30d += $n }
    }
    if ($allAlerts30d -le 0) { $allAlerts30d = $alerts30d; $sentinelAlerts30d = $alerts30d }
    # First-party detections by source family: alerts raised inside Defender XDR,
    # Entra ID Protection, Defender for Identity and Defender for Cloud do not
    # read workspace tables, so the rings cannot count them; the flow shows them
    # beside each family instead. Sentinel's own rules are excluded here.
    $productAgg = [ordered]@{}
    foreach ($v in @($volumes | Where-Object { $_ })) {
        $prod = [string]$(if ($v.PSObject.Properties['ProductName']) { $v.ProductName } else { '' })
        if (-not $prod -or $prod -match 'Sentinel') { continue }
        $famName = Get-ProductFamily -Product $prod
        $key = "$famName|$prod"
        if (-not $productAgg.Contains($key)) { $productAgg[$key] = [ordered]@{ family = $famName; product = $prod; alerts = [long]0; detections = 0 } }
        $productAgg[$key].alerts += [long](ConvertTo-BuildNumber $v.Alerts); $productAgg[$key].detections++
    }
    $productAlerts = @($productAgg.Values | Sort-Object { -$_.alerts })
    $incidents30d = if ($incSummaryRow -and $incSummaryRow.PSObject.Properties['Count'])  { [int](ConvertTo-BuildNumber $incSummaryRow.Count) }  else { 0 }
    $closed30d    = if ($incSummaryRow -and $incSummaryRow.PSObject.Properties['Closed']) { [int](ConvertTo-BuildNumber $incSummaryRow.Closed) } else { 0 }
    $rulesQueryEnabled = @($alertRaw | Where-Object { $_.properties -and $_.properties.enabled -and $_.kind -in @('Scheduled', 'NRT') }).Count
    # Fired, of the enabled Scheduled and NRT rules (by rule id, or by name for an
    # alert without one), as the ring says: a rule disabled or deleted since it
    # fired is not one of them. The keys go to the dashboard for its slider too.
    $queryRuleKeys = @{}
    foreach ($r in @($alertRaw | Where-Object { $_.properties -and $_.properties.enabled -and $_.kind -in @('Scheduled', 'NRT') })) {
        $queryRuleKeys[([string]$r.name).ToLowerInvariant()] = $true
        if ($r.properties.PSObject.Properties['displayName'] -and $r.properties.displayName) { $queryRuleKeys["name:$($r.properties.displayName)"] = $true }
    }
    $rulesFiredCount = @($firedRows | Where-Object {
        if (-not $_) { return $false }
        $k = ([string]$(if ($_.PSObject.Properties['AlertRuleId']) { $_.AlertRuleId } else { '' })).ToLowerInvariant(); if ($k -match '/') { $k = ($k -split '/')[-1] }
        if ($k) { $queryRuleKeys.ContainsKey($k) } else { $queryRuleKeys.ContainsKey("name:$([string]$(if ($_.PSObject.Properties['AlertName']) { $_.AlertName } else { '' }))") }
    }).Count
    $estate = [ordered]@{
        window          = "$($lookbackDays)d"
        sources         = $estateSources
        tables          = @($estateTableRows | Sort-Object { $_.gb } -Descending)
        productAlerts   = $productAlerts
        customDetections = [ordered]@{ captured = $customDetCaptured; total = @($customDetRaw | Where-Object { $_ }).Count; enabled = @($customDetRefs | Where-Object { $_ -and $_.Enabled -eq $true }).Count }
        totalGb         = [math]::Round($estateTotalGb, 2)
        coveredGb       = [math]::Round($estateCoveredGb, 2)
        uncoveredGb     = [math]::Round($estateTotalGb - $estateCoveredGb, 2)
        rings           = [ordered]@{
            ingestion = New-EstateRing "Tables still receiving data ($($recentDays)d, of those with data in $($lookbackDays)d)" $tablesActive $tablesSeen
            detection = New-EstateRing 'Active tables read by an enabled Sentinel rule or custom detection' $tablesCovered $tablesActive
            alerts    = New-EstateRing 'Enabled Scheduled/NRT Sentinel rules that fired' $rulesFiredCount $rulesQueryEnabled
            incidents = New-EstateRing 'Incidents closed, of those created' $closed30d $incidents30d
        }
        rulesEnabled    = $rulesEnabled
        rulesFired      = $rulesFiredCount
        alerts          = $allAlerts30d
        alertsSentinel  = $sentinelAlerts30d
        alertsXdr       = $xdrAlerts30d
        ruleAlerts      = $alerts30d
        incidents       = $incidents30d
        incidentsClosed = $closed30d
        incidentsOpen   = [math]::Max(0, $incidents30d - $closed30d)
        dcrs            = $counts.dcrs
        automationRules = $counts.automationRules
        playbooks       = Measure-Count (Read-SiteRaw 'playbooks.json')
    }

    # Left in the build context for later steps.
    $Context.bookmarkRows = $bookmarkRows
    $Context.customDetPerTable = $customDetPerTable
    $Context.customDetRefs = $customDetRefs
    $Context.effectRows = $effectRows
    $Context.estate = $estate
    $Context.firedRows = $firedRows
    $Context.huntRows = $huntRows
    $Context.incidents30d = $incidents30d
    $Context.incSummaryRow = $incSummaryRow
    if (Get-Variable -Name 'k' -Scope 0 -ErrorAction Ignore) { $Context.k = $k }
    if (Get-Variable -Name 'key' -Scope 0 -ErrorAction Ignore) { $Context.key = $key }
    $Context.maturityOk = $maturityOk
    $Context.maturityRaw = $maturityRaw
    if (Get-Variable -Name 'n' -Scope 0 -ErrorAction Ignore) { $Context.n = $n }
    if (Get-Variable -Name 'prod' -Scope 0 -ErrorAction Ignore) { $Context.prod = $prod }
    $Context.queryRuleKeys = $queryRuleKeys
    $Context.r = $r
    $Context.referencedTables = $referencedTables
    $Context.ruleRefs = $ruleRefs
    $Context.rulesPerTableBuild = $rulesPerTableBuild
    $Context.rulesQueryEnabled = $rulesQueryEnabled
    $Context.runRows = $runRows
    $Context.tablesData = $tablesData
    $Context.templateRefs = $templateRefs
    $Context.tiCountRows = $tiCountRows
    $Context.tiObjectRows = $tiObjectRows
    $Context.usageRows = $usageRows
    $Context.v = $v
}
