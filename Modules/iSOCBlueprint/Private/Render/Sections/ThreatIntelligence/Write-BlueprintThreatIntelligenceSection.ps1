#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 27-threat-intelligence.md (part 1 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/ThreatIntelligence/Write-BlueprintThreatIntelligenceSection.ps1
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
function Write-BlueprintThreatIntelligenceSection {
    <#
    .SYNOPSIS
        Build the figures for and write 27-threat-intelligence.md (part 1 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $connectors = $Context.connectors
    $k = $Context.k
    $rawRoot = $Context.rawRoot

    # Section 27 — Threat Intelligence (TOC 4.17)
    # Indicators by observable type (IP, domain, URL, file hash, email).
    $tiByTypeRows = @(Read-BlueprintRawArray 'threat-intel-by-type.json' | Where-Object { $_ } | ForEach-Object {
            [pscustomobject]@{ Type = $_.Type; Count = $_.Count; Indicators = Get-BlueprintRawProperty $_ 'Indicators' '' }
        } | Sort-Object { ConvertTo-BlueprintNumber $_.Count } -Descending)
    $tiByTypePie = if ($tiByTypeRows.Count -ge 2) {
        @"
``````mermaid
pie showData title Indicators by type (last {lookback-d})
$(($tiByTypeRows | ForEach-Object { "    `"$($_.Type)`" : $(ConvertTo-BlueprintNumber $_.Count)" }) -join [Environment]::NewLine)
``````
"@
    } else { '' }
    # Two capture sources are tried in turn:
    # 1. `threat-intel-metrics.json` — the Sentinel TI metrics REST endpoint.
    #    Independent of the workspace KQL path so it survives KQL-side failures
    #    (missing Az.OperationalInsights module, permission gaps, table absence).
    # 2. `threat-intel-counts.json` — the KQL summary against ThreatIntelligenceIndicator.
    #    Used as a fallback when the metrics endpoint produced no data.
    #
    # Metrics-API response shape (one record per workspace):
    #   properties.threatTypeMetrics[]   { metricName, metricValue }  — by threat type
    #   properties.patternTypeMetrics[]  { metricName, metricValue }  — by STIX pattern type
    #   properties.sourceMetrics[]       { metricName, metricValue }  — by ingestion source
    # An earlier version of the renderer read `properties.metrics[]` with
    # `threatType` / `threatTypeCount` fields — those field names appear nowhere
    # in the real API surface and resulted in zero rows being rendered.
    $tiMetrics = Read-BlueprintRawArray 'threat-intel-metrics.json'
    $tiCounts = Read-BlueprintRawArray 'threat-intel-counts.json'
    $tiSourceRows = @()
    $tiTypeRows = @()
    if ($tiMetrics.Count -gt 0) {
        foreach ($m in $tiMetrics) {
            if ($m.PSObject.Properties.Name -notcontains 'properties' -or -not $m.properties) { continue }
            if ($m.properties.PSObject.Properties.Name -contains 'sourceMetrics' -and $m.properties.sourceMetrics) {
                foreach ($s in $m.properties.sourceMetrics) {
                    $tiSourceRows += [pscustomobject]@{
                        SourceSystem   = $s.metricName
                        IndicatorCount = $s.metricValue
                        LastIngested   = ''
                    }
                }
            }
            if ($m.properties.PSObject.Properties.Name -contains 'threatTypeMetrics' -and $m.properties.threatTypeMetrics) {
                foreach ($t in $m.properties.threatTypeMetrics) {
                    $tiTypeRows += [pscustomobject]@{
                        ThreatType     = $t.metricName
                        IndicatorCount = $t.metricValue
                    }
                }
            }
        }
        # Sort both tables by count desc so the loudest entry surfaces first.
        $tiSourceRows = @($tiSourceRows) | Sort-Object -Property IndicatorCount -Descending
        $tiTypeRows = @($tiTypeRows) | Sort-Object -Property IndicatorCount -Descending
        $tiRows = $tiSourceRows
        $tiSourceLabel = 'TI metrics API (`threatIntelligence/main/metrics`)'
    } else {
        $tiRows = $tiCounts | ForEach-Object {
            [pscustomobject]@{ SourceSystem = $_.SourceSystem; IndicatorCount = $_.Count; LastIngested = $_.Last }
        } | Sort-Object -Property IndicatorCount -Descending
        $tiSourceLabel = 'workspace KQL summary'
    }
    $tiTotal = ($tiRows | Measure-Object -Property IndicatorCount -Sum).Sum
    $tiHeadline = if ($tiTotal -and $tiTotal -gt 0) {
        "**Total active indicators:** $(Format-BlueprintCount $tiTotal)  ·  **Distinct breakdown rows:** $(Format-BlueprintCount @($tiRows).Count)  ·  **Data source:** $tiSourceLabel"
    } else {
        '_No threat intelligence indicators surfaced via either capture path._'
    }
    # Threat-type breakdown only renders when the metrics API path actually
    # returned a populated array — under the KQL fallback there is no
    # equivalent breakdown so the section is suppressed entirely.
    $tiTypeBlock = if ($tiTypeRows.Count -gt 0 -and ($tiTypeRows | Measure-Object -Property IndicatorCount -Sum).Sum -gt 0) {
        @"

## Indicator breakdown by threat type

$(Format-BlueprintTable -Items @($tiTypeRows | ForEach-Object { [pscustomobject]@{ ThreatType = $_.ThreatType; IndicatorCount = (Format-BlueprintCount $_.IndicatorCount) } }) -Columns 'ThreatType','IndicatorCount')
"@
    } else { '' }
    # Pie of TI sources: the six largest, the rest as one Other slice. The
    # indicator table on this page lists every source.
    $tiPieBlock = if ($tiRows -and ($tiRows | Measure-Object -Property IndicatorCount -Sum).Sum -gt 0) {
        $tiBySource = [ordered]@{}
        foreach ($row in @($tiRows)) {
            $k = [string]$row.SourceSystem
            $tiBySource[$k] = $(if ($tiBySource.Contains($k)) { $tiBySource[$k] } else { 0 }) + [long]$row.IndicatorCount
        }
        $tiPieRows = Format-PieSlice -Counts $tiBySource -Limit 6
        @"

## Indicator distribution by source

``````mermaid
pie showData title TI indicators by source
$($tiPieRows -join [Environment]::NewLine)
``````
"@
    } else { '' }

    # STIX objects beyond indicators, and the feeds that bring indicators in.
    $tiObjects = Read-BlueprintRawArray 'threat-intel-objects.json'
    $tiObjectsBlock = if ($tiObjects.Count -gt 0) {
        @"

## Indicators by type (last {lookback-d})

Observable types across the indicators ingested in the last {lookback}, from the current ``ThreatIntelIndicators`` schema (``ObservableKey``) or, where only the retired table has data, ``ThreatIntelligenceIndicator``. A feed that is all IP addresses covers network detections and nothing else; URL, domain and file-hash coverage is what email and endpoint detections match on.

$tiByTypePie

$(Format-BlueprintTable -Items @($tiByTypeRows | ForEach-Object { [pscustomobject]@{ Type = $_.Type; Count = (Format-BlueprintCount $_.Count); Indicators = (Format-BlueprintCount $_.Indicators) } }) -Columns 'Type','Count','Indicators')

## STIX objects (last {lookback-d})

Objects in ``ThreatIntelObjects`` by STIX type. Indicators alone give matches; threat actors, attack patterns and relationships give those matches their context.

$(Format-BlueprintTable -Items ($tiObjects | ForEach-Object { [pscustomobject]@{ StixType = $_.StixType; Count = (Format-BlueprintCount $_.Count) } }) -Columns 'StixType','Count')
"@
    } else { '' }
    $tiFeedKinds = @(
        'MicrosoftThreatIntelligence', 'PremiumMicrosoftDefenderForThreatIntelligence', 'ThreatIntelligenceTaxii', 'ThreatIntelligence',
        'ThreatIntelligenceUploadIndicatorsAPI'
    )
    $tiFeedRows = @($connectors | Where-Object { $_.kind -in $tiFeedKinds } | ForEach-Object { [pscustomobject]@{ Kind = $_.kind; Name = $_.name } })

    # Which TI tables carry data: the current ThreatIntelIndicators and
    # ThreatIntelObjects, and the retired ThreatIntelligenceIndicator. A table
    # missing from the capture is not in the workspace at all.
    $tiTableRaw = @(Read-BlueprintRawArray 'threat-intel-tables.json' | Where-Object { $_ })
    $tiTableRows = @(foreach ($name in 'ThreatIntelIndicators', 'ThreatIntelObjects', 'ThreatIntelligenceIndicator') {
            $row = $tiTableRaw | Where-Object { [string]$_.Table -eq $name } | Select-Object -First 1
            $n30 = if ($row) { [long](Get-BlueprintRawProperty $row 'Records30d' 0) } else { 0 }
            [pscustomobject]@{
                Table      = $(if ($name -eq 'ThreatIntelligenceIndicator') { "$name (retired)" } else { $name })
                Records30d = $(if ($row) { $n30 } else { '' })
                Records7d  = $(if ($row) { [long](Get-BlueprintRawProperty $row 'Records7d' 0) } else { '' })
                FirstSeen  = $(if ($row) { Format-DateUtc (Get-BlueprintRawProperty $row 'FirstSeen') } else { '' })
                LastSeen   = $(if ($row) { Format-DateUtc (Get-BlueprintRawProperty $row 'LastSeen') } else { '' })
                Status     = $(if (-not $row) { 'Not in workspace' } elseif ($n30 -gt 0) { 'Ingesting' } else { 'No data in {lookback}' })
            }
        })
    $tiCurrent = [long](@(
            $tiTableRaw | Where-Object { [string]$_.Table -eq 'ThreatIntelIndicators' } | ForEach-Object { Get-BlueprintRawProperty $_ 'Records30d' 0 }
        ) |
            Measure-Object -Sum).Sum
    $tiLegacy = [long](@(
            $tiTableRaw | Where-Object { [string]$_.Table -eq 'ThreatIntelligenceIndicator' } | ForEach-Object { Get-BlueprintRawProperty $_ 'Records30d' 0 }
        ) |
            Measure-Object -Sum).Sum
    $tiMigration = if (-not (Test-Path (Join-Path $rawRoot 'threat-intel-tables.json'))) { '_Not captured in this snapshot._' }
    elseif ($tiCurrent -gt 0 -and $tiLegacy -gt 0) {
        '**Both tables carry data.** `ThreatIntelIndicators` is current; confirm nothing still writes to or reads the retired table ([SAC-TI-01], [SAC-TI-02]).'
    } elseif ($tiCurrent -gt 0) { '**Current.** Threat intelligence is flowing into `ThreatIntelIndicators`.' }
    elseif ($tiLegacy -gt 0) {
        '**Retired table only.** Indicators land in `ThreatIntelligenceIndicator` but not `ThreatIntelIndicators`; check the TI connector configuration ([SAC-TI-01]).'
    } else { '**No threat intelligence** in either table over the last {lookback}.' }

    $tiHealth = Read-BlueprintRawArray 'threat-intel-health.json' | Select-Object -First 1
    $tiHealthBlock = if ($tiHealth) {
        @"
| | |
|---|---:|
| Distinct indicators (latest state) | $(Format-BlueprintCount (ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $tiHealth 'Total' 0))) |
| Active | $(Format-BlueprintCount (ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $tiHealth 'Active' 0))) |
| Deleted | $(Format-BlueprintCount (ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $tiHealth 'Deleted' 0))) |
| Revoked | $(Format-BlueprintCount (ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $tiHealth 'Revoked' 0))) |
| Still within their validity | $(Format-BlueprintCount (ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $tiHealth 'StillValid' 0))) |
"@
    } else { Get-BlueprintEmptyMessage 'threat-intel-health.json' '_No indicators in `ThreatIntelIndicators` over the last {lookback}._' }

    $tiKqlSourceRows = @($tiCounts | Where-Object { $_ } | ForEach-Object {
            [pscustomobject]@{
                SourceSystem = $_.SourceSystem
                Records      = $_.Count
                Indicators   = Get-BlueprintRawProperty $_ 'Indicators' ''
                LastSeen     = Format-DateUtc $_.Last
            }
        } |
            Sort-Object @{ Expression = { ConvertTo-BlueprintNumber $_.Records }; Descending = $true }, SourceSystem |
            ForEach-Object { $_.Records = Format-BlueprintCount $_.Records; $_.Indicators = Format-BlueprintCount $_.Indicators; $_ })

    $taxiiRows = @(Read-BlueprintRawArray 'taxii-clients.json' | Where-Object { $_ } | ForEach-Object {
            $tp = Get-BlueprintRawProperty $_ 'properties'
            [pscustomobject]@{
                Name        = [string](Get-BlueprintRawProperty $tp 'friendlyName' $_.name)
                Collection  = [string](Get-BlueprintRawProperty $tp 'collectionId' '')
                Polling     = [string](Get-BlueprintRawProperty $tp 'pollingFrequency' '')
                Server      = [string](Get-BlueprintRawProperty $tp 'taxiiServer' '')
                Description = [string](Get-BlueprintRawProperty $tp 'description' '')
            }
        })

    # Left in the render context for later sections.
    $Context.m = $m
    $Context.name = $name
    $Context.s = $s
    $Context.t = $t
    $Context.taxiiRows = $taxiiRows
    $Context.tiFeedRows = $tiFeedRows
    $Context.tiHeadline = $tiHeadline
    $Context.tiHealthBlock = $tiHealthBlock
    $Context.tiKqlSourceRows = $tiKqlSourceRows
    $Context.tiMigration = $tiMigration
    $Context.tiObjectsBlock = $tiObjectsBlock
    $Context.tiPieBlock = $tiPieBlock
    if (Get-Variable -Name 'tiRows' -Scope 0 -ErrorAction Ignore) { $Context.tiRows = $tiRows }
    $Context.tiTableRows = $tiTableRows
    $Context.tiTypeBlock = $tiTypeBlock
}
