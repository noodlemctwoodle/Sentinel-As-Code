#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 20-analytics-rules.md (part 1 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/AnalyticsRules/Write-BlueprintAnalyticsRulesSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintAnalyticsRulesSection {
    <#
    .SYNOPSIS
        Build the figures for and write 20-analytics-rules.md (part 1 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $effectivenessRows = $Context.effectivenessRows
    $key = $Context.key
    $kind = $Context.kind
    $label = $Context.label
    $m = $Context.m
    $n = $Context.n
    $ruleEffectiveness = $Context.ruleEffectiveness
    $ruleId = $Context.ruleId
    $rules = $Context.rules
    $s = $Context.s
    $sol = $Context.sol

    # Section 21 — Rules by alert volume (TOC 4.11.2)
    $ruleVolumes = Read-BlueprintRawArray 'analytics-rule-volumes.json'
    $volChartBlock = if ($ruleVolumes.Count -gt 0) {
        $top10 = $ruleVolumes | Select-Object -First 10
        $volAxis = ($top10 | ForEach-Object {
            $n = $_.AlertName
            # Use first significant word, max 12 chars, no parens
            $clean = ($n -replace '\(.*?\)', '' -replace '\[.*?\]', '').Trim()
            $words = $clean -split '\s+'
            $label = if ($words.Count -gt 0) { $words[0] } else { 'rule' }
            if ($label.Length -gt 12) { $label = $label.Substring(0,12) }
            "`"$label`""
        }) -join ', '
        $volBars = ($top10 | ForEach-Object { [long]$_.Alerts }) -join ', '
        $volMax = [long]1
        foreach ($r in $top10) { if ([long]$r.Alerts -gt $volMax) { $volMax = [long]$r.Alerts } }
        @"

### Top 10 noisy rules by alert volume

``````mermaid
---
config:
  xyChart:
    width: 1400
    height: 480
---
xychart-beta
    title "Top 10 alerting rules: alert count (last {lookback-d})"
    x-axis [$volAxis]
$(Format-XyFullLabels @($top10 | ForEach-Object { $_.AlertName }))
    y-axis "Alerts" 0 --> $($volMax + ([math]::Ceiling($volMax * 0.1) + 1))
    bar [$volBars]
``````

The chart's axis uses short labels, and the table below has the full rule names. A single tall bar usually means a tuning candidate (over-broad threshold, missing suppression).
"@
    } else { '' }

    $volumeSection = @"

## By alert volume (last {lookback-d})

Every alert name raised in the last {lookback}, most alerts first, derived from ``SecurityAlert``. A rule firing thousands of alerts a day is usually either a misconfiguration (too-low threshold) or a high-fidelity signal; review and tune.
$volChartBlock

$(Format-BlueprintTable -Items ($ruleVolumes | ForEach-Object { [pscustomobject]@{ Rule = $_.AlertName; Product = $_.ProductName; Severity = $_.AlertSeverity; Alerts = (Format-BlueprintCount $_.Alerts) } }) -Columns 'Rule','Product','Severity','Alerts')

## Rule effectiveness (last {lookback-d})

Incidents per detection with their closure verdicts: Sentinel analytics rules first, then alerts from other products keyed by alert name with the product as **Source**. **FP rate** is false positives over closed incidents, in percent. A high volume with a high false-positive rate is the first tuning candidate; a high volume closed mostly as true positive is a rule earning its keep.

$(Format-BlueprintTable -Items $effectivenessRows -Columns 'Rule','Source','Incidents','Closed','TP','FP','BP','Undetermined','FPRate')

## Noisy rules (closed mostly as false positive)

Sentinel analytics rules with 20 or more incidents closed in the last {lookback} and more than 70% of them closed as false positive: the rules to tune first ([SAC-DET-06]). Alerts from other products are tuned in their own portal, so they are not listed.

$(Format-BlueprintTable -Items @($effectivenessRows | Where-Object { $_.Source -eq 'Analytics rule' -and $_.Closed -ge 20 -and [double]$_.FPRate -gt 70 } | Sort-Object @{ Expression = { [double]$_.FPRate }; Descending = $true }, Rule) -Columns 'Rule','Incidents','Closed','FP','FPRate' -EmptyMessage $(if ($ruleEffectiveness.Count) { '_No analytics rule closed mostly as false positive._' } else { '_Not captured in this snapshot._' }))
"@

    # Section 22 — Microsoft security rules (TOC 4.11.3)
    $msRules = @($rules | Where-Object {
        $kind = $_.kind
        $tn = $_.properties.alertRuleTemplateName
        ($tn -and ($tn -match '^[a-f0-9-]{36}$')) -or ($kind -in @('Fusion','MicrosoftSecurityIncidentCreation','MLBehaviorAnalytics','ThreatIntelligence'))
    })
    # Microsoft rules by severity for the headline pie.
    $msSevCounts = @{ 'High' = 0; 'Medium' = 0; 'Low' = 0; 'Informational' = 0 }
    foreach ($r in $msRules) {
        $sev = if ($r.properties.severity) { [string]$r.properties.severity } else { 'Unknown' }
        if (-not $msSevCounts.ContainsKey($sev)) { $msSevCounts[$sev] = 0 }
        $msSevCounts[$sev]++
    }
    $msPieRows = $msSevCounts.GetEnumerator() | Where-Object { $_.Value -gt 0 } | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | ForEach-Object {
        "    `"$($_.Key)`" : $($_.Value)"
    }
    $msChartBlock = if ($msRules.Count -gt 0) {
        @"

### Microsoft rules by severity

``````mermaid
pie showData title Microsoft-managed rules by severity
$($msPieRows -join [Environment]::NewLine)
``````

$(Format-BlueprintPlural $msRules.Count 'Microsoft-managed rule'). High-severity bias is the norm, as these rules are pre-tuned by Microsoft.
"@
    } else { '' }

    $msRulesSection = @"

## Microsoft-managed rules

Rules backed by a Microsoft template, or built-in Microsoft-managed kinds (Fusion, MicrosoftSecurityIncidentCreation, MLBehaviorAnalytics, ThreatIntelligence). These are not user-editable; tuning is via enable/disable and the per-rule incident-grouping config.
$msChartBlock

$(Format-BlueprintTable -Items ($msRules | ForEach-Object { [pscustomobject]@{ Kind = $_.kind; Name = $_.properties.displayName; Severity = $_.properties.severity; Enabled = if ($_.properties.enabled) {'Yes'} else {'No'} } }) -Columns 'Kind','Name','Severity','Enabled')
"@

    # Section 23 — Modifications (TOC 4.11.4)
    # Format-DateUtc text does not sort as time ("9 Oct" falls after "15 Oct"), so
    # the rows sort on SortKey, the same moment as a [datetime].
    $modifiedRows = $rules | ForEach-Object {
        $lm = $null
        if ($_.properties -and ($_.properties.PSObject.Properties.Name -contains 'lastModifiedUtc')) { $lm = $_.properties.lastModifiedUtc }
        [pscustomobject]@{
            Name = $_.properties.displayName
            Kind = $_.kind
            LastModified = Format-DateUtc $lm
            SortKey = ConvertTo-UtcDateTime $lm
            Enabled = if ($_.properties.enabled) {'Yes'} else {'No'}
        }
    } | Where-Object { $_.LastModified } | Sort-Object -Property SortKey -Descending
    # Modifications-per-month bar over the last 12 months.
    $monthBuckets = [ordered]@{}
    $now = (Get-Date).ToUniversalTime()
    for ($i = 11; $i -ge 0; $i--) {
        $m = $now.AddMonths(-$i)
        $key = $m.ToString('yyyy-MM', [System.Globalization.CultureInfo]::InvariantCulture)
        $monthBuckets[$key] = 0
    }
    foreach ($r in $rules) {
        $lm = if ($r.properties -and ($r.properties.PSObject.Properties.Name -contains 'lastModifiedUtc')) { $r.properties.lastModifiedUtc } else { $null }
        if (-not $lm) { continue }
        $parsed = [datetime]::MinValue
        if ($lm -is [datetime]) { $parsed = $lm }
        elseif (-not [datetime]::TryParse([string]$lm, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { continue }
        $key = $parsed.ToUniversalTime().ToString('yyyy-MM', [System.Globalization.CultureInfo]::InvariantCulture)
        if ($monthBuckets.Contains($key)) { $monthBuckets[$key]++ }
    }
    $modAxis = ($monthBuckets.Keys | ForEach-Object { "`"$($_.Substring(5,2))`"" }) -join ', '
    $modBars = ($monthBuckets.Values) -join ', '
    $modMax = 1
    foreach ($v in $monthBuckets.Values) { if ($v -gt $modMax) { $modMax = $v } }

    $modificationsSection = @"

## Recent modifications

### Modifications per month (last 12 months)

``````mermaid
xychart-beta
    title "Rule modifications per month, last 12 months"
    x-axis [$modAxis]
    y-axis "Modifications" 0 --> $($modMax + 1)
    bar [$modBars]
``````

Each bar is one calendar month (MM). Tempo reveals release cadence: sustained months at zero suggest abandoned content; periodic spikes usually align with vendor content-pack updates.

Every rule, most recently modified first. Cross-reference with [Compare-iSOCContent](https://github.com/noodlemctwoodle/Sentinel-As-Code/blob/main/Docs/Modules/iSOCDeployments/Drift.md): a recent modification on a rule that has a Content Hub template or repo YAML source-of-truth indicates portal drift.

$(Format-BlueprintTable -Items $modifiedRows -Columns 'Name','Kind','LastModified','Enabled')
"@

    # Section 24 — By Content Solution (TOC 4.11.5)
    $metadataAll = Read-BlueprintRawArray 'metadata.json'
    $ruleToSolution = @{}
    foreach ($m in $metadataAll) {
        if ($m.properties.kind -eq 'AnalyticsRule' -and $m.properties.parentId) {
            $ruleId = ($m.properties.parentId -split '/')[-1]
            $ruleToSolution[$ruleId] = $m.properties.source.name
        }
    }
    $bySolution = $rules | ForEach-Object {
        $sol = if ($ruleToSolution.ContainsKey($_.name)) { $ruleToSolution[$_.name] } else { '(custom or unmapped)' }
        [pscustomobject]@{
            Solution = $sol
            Rule     = $_.properties.displayName
            Enabled  = if ($_.properties.enabled) {'Yes'} else {'No'}
            Severity = $_.properties.severity
        }
    } | Sort-Object Solution, Rule
    # Top solutions by rule count (top 8 + Other) for the headline pie.
    $solCounts = @{}
    foreach ($r in $bySolution) {
        $s = if ($r.Solution) { [string]$r.Solution } else { 'Unknown' }
        if (-not $solCounts.ContainsKey($s)) { $solCounts[$s] = 0 }
        $solCounts[$s]++
    }
    $topSols = $solCounts.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | Select-Object -First 8
    $otherSolCount = 0
    $counted = 0
    foreach ($e in $solCounts.GetEnumerator()) { $counted += $e.Value }
    $top8Sum = ($topSols | ForEach-Object { $_.Value } | Measure-Object -Sum).Sum
    $otherSolCount = $counted - $top8Sum

    $solPieRows = $topSols | ForEach-Object { "    `"$($_.Key)`" : $($_.Value)" }
    if ($otherSolCount -gt 0) { $solPieRows += "    `"Other`" : $otherSolCount" }

    # Left in the render context for later sections.
    $Context.bySolution = $bySolution
    $Context.counted = $counted
    if (Get-Variable -Name 'm' -Scope 0 -ErrorAction Ignore) { $Context.m = $m }
    $Context.modificationsSection = $modificationsSection
    $Context.msRulesSection = $msRulesSection
    if (Get-Variable -Name 'parsed' -Scope 0 -ErrorAction Ignore) { $Context.parsed = $parsed }
    $Context.r = $r
    if (Get-Variable -Name 's' -Scope 0 -ErrorAction Ignore) { $Context.s = $s }
    $Context.solCounts = $solCounts
    $Context.solPieRows = $solPieRows
    $Context.volumeSection = $volumeSection
}
