#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 15-incidents.md (part 1 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Incidents/Write-BlueprintIncidentsSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintIncidentsSection {
    <#
    .SYNOPSIS
        Build the figures for and write 15-incidents.md (part 1 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $d = $Context.d
    $incMttr = $Context.incMttr
    $incSummary = $Context.incSummary
    $p = $Context.p
    $rid = $Context.rid
    $row = $Context.row
    $ruleEffectiveness = $Context.ruleEffectiveness
    $rules = $Context.rules
    $ruleVolumesAll = $Context.ruleVolumesAll
    $s = $Context.s

    # Section 15 — Incidents (TOC 4.10)
    # $incSummary and $incMttr are read at the top of the file (the estate flow
    # on 00 and 01 needs them before this section runs).
    $incByRule = Read-BlueprintRawArray 'incidents-by-rule.json'
    # Alert volume by severity and by the product that raised it, from the same
    # SecurityAlert aggregate the dashboard uses (every product, not only
    # Sentinel rules).
    $alertVolumeTotal = [long]0
    foreach ($v in @($ruleVolumesAll | Where-Object { $_ })) { $alertVolumeTotal += [long](ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $v 'Alerts' 0)) }
    $sevOrder = @{ High = 0; Medium = 1; Low = 2; Informational = 3 }
    $sevAgg = [ordered]@{}
    foreach ($v in @($ruleVolumesAll | Where-Object { $_ })) {
        $s = [string](Get-BlueprintRawProperty $v 'AlertSeverity' '')
        if (-not $s) { $s = 'Other' }
        if (-not $sevAgg.Contains($s)) { $sevAgg[$s] = [long]0 }
        $sevAgg[$s] += [long](ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $v 'Alerts' 0))
    }
    $alertSeverityRows = @($sevAgg.GetEnumerator() |
            Sort-Object { if ($sevOrder.ContainsKey([string]$_.Key)) { $sevOrder[[string]$_.Key] } else { 9 } } |
            ForEach-Object {
                [pscustomobject]@{
                    Severity = $_.Key
                    Alerts   = $_.Value
                    Share    = $(if ($alertVolumeTotal -gt 0) { "$([math]::Round(100.0 * $_.Value / $alertVolumeTotal, 1))%" } else { '0%' })
                }
            })
    $productLabel = @{ 'Microsoft Defender Advanced Threat Protection' = 'Defender for Endpoint'; 'Azure Sentinel' = 'Microsoft Sentinel' }
    $srcAgg = [ordered]@{}
    foreach ($v in @($ruleVolumesAll | Where-Object { $_ })) {
        $p = [string](Get-BlueprintRawProperty $v 'ProductName' '')
        if (-not $p) { $p = 'Other' }
        if ($productLabel.ContainsKey($p)) { $p = $productLabel[$p] }
        if (-not $srcAgg.Contains($p)) { $srcAgg[$p] = [pscustomobject]@{ Source = $p; Alerts = [long]0; Rules = 0 } }
        $srcAgg[$p].Alerts += [long](ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $v 'Alerts' 0))
        $srcAgg[$p].Rules++
    }
    $alertSourceRows = @($srcAgg.Values | Sort-Object { - $_.Alerts } | ForEach-Object {
            [pscustomobject]@{
                Source = $_.Source
                Alerts = $_.Alerts
                Rules  = $_.Rules
                Share  = $(if ($alertVolumeTotal -gt 0) { "$([math]::Round(100.0 * $_.Alerts / $alertVolumeTotal, 1))%" } else { '0%' })
            }
        })
    $incDaily = Read-BlueprintRawArray 'incidents-daily-metrics.json' | Select-Object -First 1

    $mttrLine = if ($incMttr -and $incMttr.ClosedCount) {
        $ackCount = $null
        if ($incMttr.PSObject.Properties.Name -contains 'AcknowledgedCount') {
            $ackCount = $incMttr.AcknowledgedCount
        }
        $mttaStr = Format-MinutesScalar -Value $incMttr.MTTAMinutes -CountAcknowledged $ackCount
        $mttrStr = Format-MinutesScalar -Value $incMttr.MTTRMinutes -CountAcknowledged $incMttr.ClosedCount
        $ackSuffix = if ($null -ne $ackCount) {
            "  ·  **Acknowledged:** $(Format-BlueprintCount $ackCount) of $(Format-BlueprintCount $incMttr.ClosedCount)"
        } else { '' }
        "**MTTA:** $mttaStr  ·  **MTTR:** $mttrStr  ·  **Closed:** $(Format-BlueprintCount $incMttr.ClosedCount) (last {lookback-d})$ackSuffix"
    } else { '_No closed incidents in the last {lookback}; MTTA/MTTR not available._' }

    $dailyLine = if ($incDaily -and $null -ne $incDaily.AvgDailyUniqueIncidents) {
        "**Avg daily unique incidents:** $(Format-BlueprintNumber $incDaily.AvgDailyUniqueIncidents)  ·  **Peak daily new incidents:** $(Format-BlueprintCount $incDaily.PeakDailyNewIncidents) (last {lookback-d})"
    } else { '_No incident-flow metrics available._' }

    # Closed-without-ack count for the state diagram note. The fixture's
    # AcknowledgedCount field was added by the MTTA-NaN fix; older captures
    # may not have it.
    $closedCount = if ($incMttr) { [int]($incMttr.ClosedCount) } else { 0 }
    $ackCountForState = 0
    if ($incMttr -and ($incMttr.PSObject.Properties.Name -contains 'AcknowledgedCount')) {
        $ackCountForState = [int]$incMttr.AcknowledgedCount
    }
    $unackCount = $closedCount - $ackCountForState
    $totalIncidents = if ($incSummary -and $incSummary.Count) { [int]$incSummary.Count } else { $closedCount }

    # Closure verdicts (ByClassification arrived with the 2.2 collector; older
    # captures have no bag and get no chart) and the per-rule effectiveness
    # table shared with section 21.
    $incClassBag = if ($incSummary -and $incSummary.PSObject.Properties['ByClassification']) {
        ConvertTo-BlueprintBag $incSummary.ByClassification
    } else { [ordered]@{} }
    $incClassTotal = 0
    foreach ($v in $incClassBag.Values) { $incClassTotal += [long]$v }
    $incOutcomeBlock = if ($incClassTotal -gt 0) {
        $classRows = ($incClassBag.GetEnumerator() |
                Sort-Object @{ Expression = 'Value'; Descending = $true }, Key |
                ForEach-Object { "    `"$(ConvertTo-BlueprintWord ([string]$_.Key))`" : $($_.Value)" }) -join
        [Environment]::NewLine
        @"

## Incident outcomes (closed, last {lookback-d})

``````mermaid
pie showData title Closed incidents by classification ({lookback-d})
$classRows
``````

Undetermined and Unclassified closures carry no verdict, so they feed neither the false-positive rate nor rule tuning; [SAC-INC-02] fires when they are the majority.
"@
    } else { '' }
    # A Sentinel rule's incidents are keyed on its rule id, so the table names
    # the rule as the workspace does, not by the name its alerts carry (a rule
    # can give its alerts their own names). An id with no rule in the inventory
    # keeps the alert name.
    $ruleNameById = @{}
    foreach ($r in @($rules | Where-Object { $_ })) {
        $rid = ([string](Get-BlueprintRawProperty $r 'name' '')).ToLowerInvariant()
        $rdn = [string](Get-BlueprintRawProperty (Get-BlueprintRawProperty $r 'properties') 'displayName' '')
        if ($rid -and $rdn) { $ruleNameById[$rid] = $rdn }
    }
    # Sentinel rules first, then other products' alerts by name; Source is the
    # collector's column when present, else derived from the rule id.
    $effectivenessRows = @($ruleEffectiveness |
            Sort-Object { - (ConvertTo-BlueprintNumber $_.Incidents) } |
            Sort-Object { if ($_.PSObject.Properties['AlertRuleId'] -and $_.AlertRuleId) { 0 } else { 1 } } -Stable |
            ForEach-Object {
                $src = if ($_.PSObject.Properties['Source'] -and $_.Source) { [string]$_.Source }
                elseif ($_.PSObject.Properties['AlertRuleId'] -and $_.AlertRuleId) { 'Analytics rule' }
                elseif ($_.PSObject.Properties['Product'] -and $_.Product) { [string]$_.Product }
                else { 'Other' }
                $rk = if ($_.PSObject.Properties['AlertRuleId'] -and $_.AlertRuleId) { (([string]$_.AlertRuleId).ToLowerInvariant() -split '/')[-1] } else { '' }
                [pscustomobject]@{
                    Rule         = $(if ($rk -and $ruleNameById.ContainsKey($rk)) { $ruleNameById[$rk] } else { $_.RuleName })
                    Source       = $src
                    Incidents    = [int](ConvertTo-BlueprintNumber $_.Incidents)
                    Closed       = [int](ConvertTo-BlueprintNumber $_.Closed)
                    TP           = [int](ConvertTo-BlueprintNumber $_.TruePositive)
                    FP           = [int](ConvertTo-BlueprintNumber $_.FalsePositive)
                    BP           = [int](ConvertTo-BlueprintNumber $_.BenignPositive)
                    Undetermined = [int](ConvertTo-BlueprintNumber $_.Undetermined)
                    FPRate       = ConvertTo-BlueprintNumber $_.FPRate
                }
            })

    # The last 7 days, as the health check reports them: incidents updated in
    # the window at their latest state, and the alert names behind them.
    $incident7dBlock = if ($incSummary -and $incSummary.PSObject.Properties['Count7d']) {
        $mtta7 = if ($incMttr -and $incMttr.PSObject.Properties['MTTAMinutes7d']) { Format-MinutesScalar -Value $incMttr.MTTAMinutes7d } else { 'n/a' }
        $mttr7 = if ($incMttr -and $incMttr.PSObject.Properties['MTTRMinutes7d']) { Format-MinutesScalar -Value $incMttr.MTTRMinutes7d } else { 'n/a' }
        @"
| | |
|---|---:|
| Incidents | $(Format-BlueprintCount (ConvertTo-BlueprintNumber $incSummary.Count7d)) |
| Closed | $(Format-BlueprintCount (ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $incSummary 'Closed7d' 0))) |
| Closed as true positive | $(Format-BlueprintCount (ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $incSummary 'TruePositive7d' 0))) |
| Closed as false positive | $(Format-BlueprintCount (ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $incSummary 'FalsePositive7d' 0))) |
| Raised through Defender XDR (unified) | $(Format-BlueprintCount (ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $incSummary 'Unified7d' 0))) |
| MTTA (incidents closed in the window) | $mtta7 |
| MTTR (incidents closed in the window) | $mttr7 |
"@
    } else { '_Not captured in this snapshot._' }
    $incProviderBag = if ($incSummary -and $incSummary.PSObject.Properties['ByProvider']) { ConvertTo-BlueprintBag $incSummary.ByProvider } else { $null }
    $incProviderRows = if ($incProviderBag) {
        @(
            $incProviderBag.GetEnumerator() |
                Sort-Object @{ Expression = 'Value'; Descending = $true }, Key |
                ForEach-Object { [pscustomobject]@{ Provider = $_.Key; Incidents = $_.Value } }
        )
    } else { @() }
    $alertVolumes = @(Read-BlueprintRawArray 'analytics-rule-volumes.json' | Where-Object { $_ })
    $alert7dCaptured = @($alertVolumes | Where-Object { $_.PSObject.Properties['Alerts7d'] }).Count -gt 0
    # Every alert name that fired in the lookback, busiest first, with how many of
    # its alerts fell in the recent window when the capture has that figure (and
    # the recent window is shorter than the lookback).
    $alertProviderRecent = $alert7dCaptured -and (Get-BlueprintWindow).RecentDays -lt (Get-BlueprintWindow).Days
    $alertProviderRows = @($alertVolumes | Where-Object { (ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $_ 'Alerts' 0)) -gt 0 } |
            Sort-Object @{ Expression = { ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $_ 'Alerts' 0) }; Descending = $true }, AlertName |
            ForEach-Object {
                $row = [ordered]@{
                    Provider = [string](Get-BlueprintRawProperty $_ 'ProviderName' '')
                    Product  = $_.ProductName
                    Alert    = $_.AlertName
                    Severity = $_.AlertSeverity
                    Alerts   = [long](ConvertTo-BlueprintNumber $_.Alerts)
                }
                if ($alertProviderRecent) { $row.Alerts7d = [long](ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $_ 'Alerts7d' 0)) }
                [pscustomobject]$row
            })
    $alertProviderColumns = @('Provider', 'Product', 'Alert', 'Severity', 'Alerts') + @(if ($alertProviderRecent) { 'Alerts7d' })

    $incStatusBag = if ($incSummary -and $incSummary.PSObject.Properties['ByStatus']) { ConvertTo-BlueprintBag $incSummary.ByStatus } else { $null }
    $incAckKnown = $incMttr -and ($incMttr.PSObject.Properties.Name -contains 'AcknowledgedCount')
    $incMinutes = {
        param($v) $s = [string]$v
        $d = 0.0
        if ($null -ne $v -and $s -ne 'NaN' -and
            [double]::TryParse($s, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
            [math]::Round($d, 1)
        } else { $null }
    }
    $lifecycleVisual = [ordered]@{
        days           = 30
        raised         = $totalIncidents
        new            = $(if ($incStatusBag) { [long](Get-BlueprintRawProperty ([pscustomobject]$incStatusBag) 'New' 0) } else { $null })
        active         = $(if ($incStatusBag) { [long](Get-BlueprintRawProperty ([pscustomobject]$incStatusBag) 'Active' 0) } else { $null })
        closed         = $(
            if ($incStatusBag) { [long](Get-BlueprintRawProperty ([pscustomobject]$incStatusBag) 'Closed' 0) } elseif ($incMttr) { $closedCount } else { $null }
        )
        acknowledged   = $(if ($incAckKnown) { $ackCountForState } else { $null })
        unacknowledged = $(if ($incAckKnown) { $unackCount } else { $null })
        mttaMinutes    = $(if ($incMttr) { & $incMinutes (Get-BlueprintRawProperty $incMttr 'MTTAMinutes') } else { $null })
        mttrMinutes    = $(if ($incMttr) { & $incMinutes (Get-BlueprintRawProperty $incMttr 'MTTRMinutes') } else { $null })
        unified        = $(
            if ($incSummary -and $incSummary.PSObject.Properties['Unified']) { [long](ConvertTo-BlueprintNumber $incSummary.Unified) } else { $null }
        )
        openBySeverity = ConvertTo-LifecycleList -Bag $(
            if ($incSummary -and $incSummary.PSObject.Properties['OpenBySeverity']) { ConvertTo-BlueprintBag $incSummary.OpenBySeverity } else { $null }
        ) -Order 'High', 'Medium', 'Low', 'Informational'
        classification = ConvertTo-LifecycleList -Bag $incClassBag -Order 'TruePositive', 'BenignPositive', 'FalsePositive', 'Undetermined',
        'Unclassified' -Labels @{
            TruePositive   = 'True positive'
            BenignPositive = 'Benign positive'
            FalsePositive  = 'False positive'
        }
        closedBy       = ConvertTo-LifecycleList -Bag $(
            if ($incSummary -and $incSummary.PSObject.Properties['ClosedBy']) { ConvertTo-BlueprintBag $incSummary.ClosedBy } else { $null }
        ) -Labels @{ AutomationRule = 'Automation rule'; DefenderXdr = 'Defender XDR' }
        check          = [ordered]@{ id = 'SAC-INC-05'; fired = $script:FiredFindingIds.ContainsKey('SAC-INC-05') }
    }
    $lifecycleVisualLine = Format-VisualLine -Kind 'incident-lifecycle' -Data $lifecycleVisual

    # Left in the render context for later sections.
    $Context.alertProviderColumns = $alertProviderColumns
    $Context.alertProviderRecent = $alertProviderRecent
    $Context.alertProviderRows = $alertProviderRows
    $Context.alertSeverityRows = $alertSeverityRows
    $Context.alertSourceRows = $alertSourceRows
    $Context.closedCount = $closedCount
    $Context.dailyLine = $dailyLine
    $Context.effectivenessRows = $effectivenessRows
    $Context.incByRule = $incByRule
    $Context.incident7dBlock = $incident7dBlock
    $Context.incOutcomeBlock = $incOutcomeBlock
    $Context.incProviderRows = $incProviderRows
    $Context.lifecycleVisualLine = $lifecycleVisualLine
    $Context.mttrLine = $mttrLine
    if (Get-Variable -Name 'p' -Scope 0 -ErrorAction Ignore) { $Context.p = $p }
    $Context.r = $r
    if (Get-Variable -Name 's' -Scope 0 -ErrorAction Ignore) { $Context.s = $s }
    $Context.totalIncidents = $totalIncidents
    $Context.unackCount = $unackCount
}
