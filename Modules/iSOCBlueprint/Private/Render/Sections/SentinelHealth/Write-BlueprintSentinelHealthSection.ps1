#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 11-sentinel-health.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/SentinelHealth/Write-BlueprintSentinelHealthSection.ps1
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
function Write-BlueprintSentinelHealthSection {
    <#
    .SYNOPSIS
        Build the figures for and write 11-sentinel-health.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $m = $Context.m
    $n = $Context.n
    $s = $Context.s

    # Section 11 — Sentinel health (TOC 4.8)
    $health = Read-BlueprintRawArray 'sentinel-health.json'
    $healthRows = $health | ForEach-Object {
        [pscustomobject]@{
            Resource           = $_.SentinelResourceName
            Kind               = $_.SentinelResourceKind
            Type               = $_.SentinelResourceType
            Events             = Format-BlueprintCount $_.Events
            Failures           = Format-BlueprintCount (Get-BlueprintRawProperty $_ 'Failures' '')
            Statuses           = ((Get-BlueprintRawList (Get-BlueprintRawProperty $_ 'Statuses')) -join ', ')
            'Last event (UTC)' = Format-DateUtc $_.LastEvent
        }
    }
    # Data connectors that reported a failure. Failures arrived after the first
    # captures; an older snapshot falls back to a non-Success status.
    $healthFailuresCaptured = @($health | Where-Object { $_ -and $_.PSObject.Properties['Failures'] }).Count -gt 0
    $connectorHealthRows = @($health | Where-Object {
            $_ -and (([string]$_.SentinelResourceType + ' ' + [string]$_.SentinelResourceKind) -match 'connector') -and
            $(
                if ($_.PSObject.Properties['Failures']) {
                    [long]$_.Failures -gt 0
                } else { @(Get-BlueprintRawList (Get-BlueprintRawProperty $_ 'Statuses') | Where-Object { $_ -ne 'Success' }).Count -gt 0 }
            )
        } | ForEach-Object {
            [pscustomobject]@{
                Connector            = $_.SentinelResourceName
                Kind                 = $_.SentinelResourceKind
                Failures             = Get-BlueprintRawProperty $_ 'Failures' 'not captured'
                'Last failure (UTC)' = Format-DateUtc (Get-BlueprintRawProperty $_ 'LastFailure')
                Statuses             = ((Get-BlueprintRawList (Get-BlueprintRawProperty $_ 'Statuses')) -join ', ')
            }
        } |
        Sort-Object @{ Expression = { ConvertTo-BlueprintNumber $_.Failures }; Descending = $true }, Connector |
        ForEach-Object { $_.Failures = Format-BlueprintCount $_.Failures; $_ })
    $healthSummary = Read-BlueprintRawArray 'sentinel-health-summary.json'
    $healthSummaryRows = $healthSummary | ForEach-Object {
        [pscustomobject]@{ OperationName = $_.OperationName; Status = $_.Status; Events = Format-BlueprintCount $_.LogCount }
    }
    $laQueryLogs = Read-BlueprintRawArray 'la-query-logs.json' | Select-Object -First 1
    $ingestionFailureRows = @(Read-BlueprintRawArray 'ingestion-latency.json' | Where-Object { $_ } | ForEach-Object {
            [pscustomobject]@{ OperationKey = $_.OperationKey; Resource = $_.Resource; Failures = $_.Failures; 'Last failure (UTC)' = Format-DateUtc $_.Last }
        } | Sort-Object { ConvertTo-BlueprintNumber $_.Failures } -Descending | ForEach-Object { $_.Failures = Format-BlueprintCount $_.Failures; $_ })
    $laQueryLine = if ($laQueryLogs -and $laQueryLogs.QueryCount) {
        "**LAQueryLogs activity ({lookback-d}):** $(Format-BlueprintCount $laQueryLogs.QueryCount) query records (query logging is active)."
    } elseif ($laQueryLogs) {
        '_LAQueryLogs table is present but empty for the last {lookback}; query logging may be off._'
    } else {
        '_LAQueryLogs table is not populated; query logging diagnostics are not configured._'
    }
    # Chart inputs: bucket health events by Status across all operations.
    $healthByStatus = @{}
    foreach ($r in $healthSummary) {
        $s = if ($r.Status) { [string]$r.Status } else { 'Unknown' }
        if (-not $healthByStatus.ContainsKey($s)) { $healthByStatus[$s] = 0 }
        $healthByStatus[$s] += [long]$r.LogCount
    }
    $healthPieRows = $healthByStatus.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | ForEach-Object {
        "    `"$($_.Key)`" : $($_.Value)"
    }
    $healthChartBlock = if ($healthSummary.Count -gt 0) {
        @"

## Health-event status mix

``````mermaid
pie showData title SentinelHealth events by status (last {lookback-d})
$($healthPieRows -join [Environment]::NewLine)
``````

Mostly-Success workspaces are operating cleanly. A non-trivial Failure / PartialSuccess slice means a Sentinel resource (rule, connector) has misfired recently.
"@
    } else { '' }

    Write-BlueprintSection '11-sentinel-health.md' (@"
$(Format-Banner -Title 'Sentinel Health and Resilience  (TOC 4.8)')

Health events are pulled from the workspace's ``SentinelHealth`` table for the last {lookback}, summarised per Sentinel resource. The table is empty on workspaces where Sentinel diagnostics have not been enabled: [turn on health diagnostics](https://learn.microsoft.com/azure/sentinel/health-audit) to start the data flowing.
$healthChartBlock

$(Format-BlueprintTable -Items $healthRows -Columns 'Resource','Kind','Type','Events','Failures','Statuses','Last event (UTC)')

## Connector and DCR health issues (last {lookback-d})

Data connectors whose health events reported a failure in the last {lookback}, most failures first. A failing connector silently stops feeding the tables its rules read; [83-data-collection.md](83-data-collection.md) lists the DCRs behind it.

$(Format-BlueprintTable -Items $connectorHealthRows -Columns 'Connector','Kind','Failures','Last failure (UTC)','Statuses' -EmptyMessage $(if ($health.Count -eq 0) { '_No connector health events in the last {lookback} (connector health diagnostics may be off)._' } else { '_No connector reported a failure in the last {lookback}._' }))

## Operations summary (per OperationName + Status)

$(Format-BlueprintTable -Items $healthSummaryRows -Columns 'OperationName','Status','Events')

## Ingestion and schema failures (last {lookback-d})

Failed ingestion and schema operations from the ``Operation`` table, grouped by operation detail and category. A row here is a broken pipeline: a DCR transform that rejects records, a custom table whose schema no longer matches what is sent, or a connector writing to a table that cannot accept it. Empty means every ingestion and schema operation in the last {lookback} succeeded.

$(Format-BlueprintTable -Items $ingestionFailureRows -Columns 'OperationKey','Resource','Failures','Last failure (UTC)')

## Query logging activity

$laQueryLine

[Sentinel health, audit, and monitoring (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/health-audit)
"@)

    # Left in the render context for later sections.
    $Context.r = $r
    if (Get-Variable -Name 's' -Scope 0 -ErrorAction Ignore) { $Context.s = $s }
}
