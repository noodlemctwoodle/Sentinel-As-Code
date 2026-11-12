#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 15-incidents.md (part 2 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Incidents/Write-BlueprintIncidentsSectionPart2.ps1
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
function Write-BlueprintIncidentsSectionPart2 {
    <#
    .SYNOPSIS
        Build the figures for and write 15-incidents.md (part 2 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $closedCount = $Context.closedCount
    $dailyLine = $Context.dailyLine
    $incByRule = $Context.incByRule
    $incident7dBlock = $Context.incident7dBlock
    $incOutcomeBlock = $Context.incOutcomeBlock
    $incProviderRows = $Context.incProviderRows
    $incSummary = $Context.incSummary
    $lifecycleVisualLine = $Context.lifecycleVisualLine
    $m = $Context.m
    $mttrLine = $Context.mttrLine
    $n = $Context.n
    $totalIncidents = $Context.totalIncidents
    $unackCount = $Context.unackCount

    $incidentBody = @"
$(Format-Banner -Title "Incidents  (TOC 4.10)")

> Aggregate-only. The Blueprint never exports incident bodies, alert payloads or entity detail, only counts and derived SOC-efficiency metrics.

$mttrLine

$dailyLine

> Alert volumes are in [16-alerts.md](16-alerts.md), and alert volume and closure verdicts per rule in [21-rule-performance.md](21-rule-performance.md). When triaging a high MTTR, start with the rules driving raw alert load: high alert volume from a single rule usually inflates time-to-acknowledge for everything else in the queue.

## Incident lifecycle

``````mermaid
stateDiagram-v2
$lifecycleVisualLine
    [*] --> New : Alert fires
    New --> Active : Analyst opens
    New --> Closed : Auto-suppress<br/>(SAC-INC-05 fires here)
    Active --> InProgress : Investigation begins
    InProgress --> Active : Re-assigned
    InProgress --> Closed : Resolved
    Closed --> [*]

    state Closed {
        [*] --> TruePositive
        [*] --> FalsePositive
        [*] --> BenignPositive
        [*] --> Undetermined
    }

    note right of New
        $(Format-BlueprintCount $totalIncidents) incidents in {lookback-d}
        $(Format-BlueprintCount $closedCount) reached Closed
        $(Format-BlueprintCount $unackCount) closed without acknowledgement
    end note
``````

## Analyst journey: a typical high-severity incident

``````mermaid
---
config:
  journey:
    diagramMarginX: 60
    diagramMarginY: 30
    leftMargin: 160
    width: 220
    height: 80
    taskFontSize: 12
---
journey
    title Analyst journey: a typical high-severity incident
    section Alert created
        Alert fires: 5: Sentinel
        Incident created: 5: Sentinel
    section Triage
        Notify SOC channel: 4: Teams
        Open incident: 4: Analyst
        Read entity timelines: 3: Analyst
        KQL hunt for context: 2: Analyst
    section Investigation
        Identify scope: 2: Analyst
        Run enrichment playbook: 4: Playbook
        Decide remediation: 3: Analyst, Lead
    section Resolution
        Apply remediation: 3: Analyst
        Document + close: 4: Analyst
``````

Dips at "KQL hunt for context" and "Identify scope" mark the SOC pain points. Workspaces firing [SAC-AUT-01] (no automation) see steeper dips because every step is manual.

## Incidents by rule (last {lookback-d})

Every rule title that produced an incident in the last {lookback}, busiest first. Alert volume per rule is in [21-rule-performance.md](21-rule-performance.md#by-alert-volume-last-{lookback-d}).

$(Format-BlueprintTable -Items ($incByRule | ForEach-Object { [pscustomobject]@{ Rule = $_.Title; Incidents = (Format-BlueprintCount $_.Incidents) } }) -Columns 'Rule','Incidents')

$incOutcomeBlock

## Incident detail by provider / product / first rule (last {lookback-d})

Per-provider, per-product, per-first-rule alert counts joined to the incidents they belong to. The FirstRule ID resolves to its full name via the [20-analytics-rules.md](20-analytics-rules.md) table.

$(Format-BlueprintTable -Items (Read-BlueprintRawArray 'incidents-detail-by-provider.json' | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ Provider = $_.ProviderName; Product = $_.ProductName; FirstRule = $_.FirstRule; AlertCount = (Format-BlueprintCount $_.AlertCount) } }) -Columns 'Provider','Product','FirstRule','AlertCount')

## Incident metrics (last {recent-d})

Incidents updated in the last {recent}, each at its latest state. The {lookback} view is at the top of the page.

$incident7dBlock

## Incidents by provider (last {lookback-d})

Which service created the incident. ``Microsoft XDR`` (or ``Microsoft 365 Defender``) means the incident came through the unified Defender XDR queue rather than from a Sentinel rule.

$(Format-BlueprintTable -Items $incProviderRows -Columns 'Provider','Incidents' -EmptyMessage $(if ($incSummary -and -not $incSummary.PSObject.Properties['ByProvider']) { '_Not captured in this snapshot._' } else { '_None._' }))

[Sentinel incidents (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/investigate-cases)
"@
    Write-BlueprintSection '15-incidents.md' $incidentBody
}
