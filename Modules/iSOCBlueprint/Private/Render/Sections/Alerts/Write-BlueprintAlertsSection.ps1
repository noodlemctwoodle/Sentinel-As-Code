#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 16-alerts.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Alerts/Write-BlueprintAlertsSection.ps1
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
function Write-BlueprintAlertsSection {
    <#
    .SYNOPSIS
        Build the figures for and write 16-alerts.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $alertProviderColumns = $Context.alertProviderColumns
    $alertProviderRecent = $Context.alertProviderRecent
    $alertProviderRows = $Context.alertProviderRows
    $alertSeverityRows = $Context.alertSeverityRows
    $alertSourceRows = $Context.alertSourceRows
    $m = $Context.m
    $n = $Context.n

    # Section 16: alerts, across every product that raises them.
    $alertsBody = @"
$(Format-Banner -Title "Alerts")

> Aggregate-only, like the incidents page: alert names, products and counts from ``SecurityAlert``, never alert payloads or entities. Incidents are in [15-incidents.md](15-incidents.md); alert volume per rule with its closure verdicts is in [21-rule-performance.md](21-rule-performance.md).

## Alert volume by severity (last {lookback-d})

Alerts raised in the last {lookback} grouped by severity, from ``SecurityAlert`` across every product, not only Sentinel rules.

$(Format-BlueprintTable -Items $alertSeverityRows -Columns 'Severity','Alerts','Share')

## Alerts by detection source (last {lookback-d})

Which security product raised the alert volume. Sentinel analytics rules appear as Microsoft Sentinel; the rest are first-party detections that run inside their product. ``Rules`` is the number of distinct detections per product.

$(Format-BlueprintTable -Items $alertSourceRows -Columns 'Source','Alerts','Rules','Share')

## Alert volumes by provider (last {lookback-d})

Every alert name that fired in the last {lookback}, with the provider and product that raised it, busiest first.$(if ($alertProviderRecent) { ' The last column is how many of those alerts fired in the last {recent}.' })

$(Format-BlueprintTable -Items $alertProviderRows -Columns $alertProviderColumns -EmptyMessage (Get-BlueprintEmptyMessage 'analytics-rule-volumes.json' '_No alerts in the last {lookback}._'))

[Sentinel alerts and incidents (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/investigate-cases)
"@
    Write-BlueprintSection '16-alerts.md' $alertsBody
}
