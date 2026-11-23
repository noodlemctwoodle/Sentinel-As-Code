#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 88-sentinel-data-lake.md (part 2 of 3).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/SentinelDataLake/Write-BlueprintSentinelDataLakeSectionPart2.ps1
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
function Write-BlueprintSentinelDataLakeSectionPart2 {
    <#
    .SYNOPSIS
        Build the figures for and write 88-sentinel-data-lake.md (part 2 of 3).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $dlTableRows = $Context.dlTableRows
    $gb = $Context.gb
    $hasDataLake = $Context.hasDataLake
    $n = $Context.n
    $name = $Context.name
    $operationalTables = $Context.operationalTables
    $parsed = $Context.parsed
    $q = $Context.q
    $rawRoot = $Context.rawRoot
    $retAxis = $Context.retAxis
    $retentionRows = $Context.retentionRows
    $retLakeBars = $Context.retLakeBars
    $retYmax = $Context.retYmax
    $rulesPerTable = $Context.rulesPerTable
    $summaryRules = $Context.summaryRules
    $tablesWithData = $Context.tablesWithData
    $tierPieRows = $Context.tierPieRows
    $tierStats = $Context.tierStats
    $topRetention = $Context.topRetention
    $use = $Context.use
    $workspaceTables = $Context.workspaceTables

    if ($tierStats.MirroredOnly -gt 0) { $tierPieRows += "    `"Analytics + Lake mirror`" : $($tierStats.MirroredOnly)" }
    if ($tierStats.MirroredExtended -gt 0) { $tierPieRows += "    `"Analytics + Lake extended`" : $($tierStats.MirroredExtended)" }
    if ($tierStats.LakeOnly -gt 0) { $tierPieRows += "    `"Lake only`" : $($tierStats.LakeOnly)" }

    $tierChartBlock = if ($tierPieRows.Count -ge 2) {
        @"

## Tier distribution

Pie of every operational table (a table that has received data in the last {lookback}, plus all CustomLog tables) by tier configuration. *Analytics + Lake mirror* is the default state on a Lake-enrolled tenant: every Analytics-plan table is auto-mirrored to the Lake at the same retention at no extra cost. *Analytics + Lake extended* means the table also stores beyond the Analytics retention in the Lake (Lake-storage meter applies). *Lake only* means the table bypasses the Analytics tier entirely (Lake-ingestion meter applies; no real-time analytics or detection rules).

``````mermaid
pie showData title Operational tables by tier configuration
$($tierPieRows -join [Environment]::NewLine)
``````
"@
    } else { '' }

    # Retention split bar chart — only render when at least one table has
    # extended retention (otherwise the chart would be empty).
    # Every table whose retention rolls into the lake, with its volume and the
    # rules reading it, and whether each one is still being fed.
    $retentionAllRows = @($retentionRows | ForEach-Object {
            $name = [string]$_.Table
            $use = @($tablesWithData | Where-Object { $_ -and (Get-BlueprintRawProperty $_ 'DataType') -eq $name }) | Select-Object -First 1
            [pscustomobject]@{
                Table = $name; Plan = $_.Plan; AnalyticsDays = $_.AnalyticsDays; LakeOnlyDays = $_.LakeOnlyDays; TotalDays = $_.TotalDays
                Gb90d = $(if ($use) { [math]::Round((ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $use 'BillableLast90d' 0)), 2) } else { 0 })
                Rules = $(if ($rulesPerTable.ContainsKey($name)) { $rulesPerTable[$name] } else { 0 })
            }
        } | Sort-Object @{ Expression = 'LakeOnlyDays'; Descending = $true }, Table)
    $nowUtc88 = (Get-Date).ToUniversalTime()
    $lakeValidationRows = @($retentionRows | ForEach-Object {
            $name = [string]$_.Table
            $use = @($tablesWithData | Where-Object { $_ -and (Get-BlueprintRawProperty $_ 'DataType') -eq $name }) | Select-Object -First 1
            $last = if ($use) { Get-BlueprintRawProperty $use 'LastIngested' } else { $null }
            $lastDt = $null
            if ($last) {
                $parsed = [datetime]::MinValue
                if ([datetime]::TryParse([string]$last, [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$parsed)) {
                    $lastDt = $parsed
                }
            }
            $days = if ($lastDt) { [math]::Round(($nowUtc88 - $lastDt).TotalDays, 1) } else { $null }
            [pscustomobject]@{
                Table = $name; Plan = $_.Plan; LakeOnlyDays = $_.LakeOnlyDays
                Gb90d        = $(if ($use) { [math]::Round((ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $use 'BillableLast90d' 0)), 2) } else { 0 })
                LastIngested = Format-DateUtc $last
                DaysSince    = $(if ($null -ne $days) { Format-BlueprintNumber $days -Decimals 1 } else { 'n/a' })
                Validation   = $(
                    if ($null -eq $days) {
                        'Check: no data in {lookback}'
                    } elseif ($days -gt 7) { "Check: last record $(Format-BlueprintNumber $days -Decimals 1) days ago" } else { 'OK: ingesting' }
                )
            }
        } | Sort-Object @{ Expression = { $_.Validation -like 'OK*' } }, @{ Expression = 'Gb90d'; Descending = $true })

    $retentionChartBlock = if ($topRetention.Count -gt 0) {
        @"

## Retention that rolls into the lake

Tables paying for retention beyond the Analytics-tier interactive period. Each bar is the table's *Lake-only* retention days for the ten longest: the portion of total retention that bills against the Lake-storage meter (per GB · month, with 6:1 compression). The table below lists every one. Tables with the same Analytics retention as total retention don't appear here because they sit entirely within the Analytics retention window and incur no Lake-storage charge.

``````mermaid
---
config:
  xyChart:
    width: 1400
    height: 480
---
xychart-beta
    title "Lake-only retention days (beyond Analytics period)"
    x-axis [$retAxis]
$(Format-XyFullLabels @($topRetention | ForEach-Object { $_.Table }))
    y-axis "Days" 0 --> $($retYmax + 30)
    bar [$retLakeBars]
``````

$(Format-BlueprintTable -Items $retentionAllRows -Columns 'Table','Plan','AnalyticsDays','LakeOnlyDays','TotalDays','Gb90d','Rules')

## Ingestion validation

Is each table with long-term retention still being fed? Last ingestion comes from the ``Usage`` table over {lookback}. A table kept for years that stopped receiving data is paying to retain history nobody is adding to, and its detections have gone quiet.

$(Format-BlueprintTable -Items $lakeValidationRows -Columns 'Table','Plan','LakeOnlyDays','Gb90d','LastIngested','DaysSince','Validation')
"@
    } else { '' }

    # Lake architecture flowchart — static visual showing the three tiers
    # and the ingestion / mirror / promote / query paths. Always rendered
    # when Lake is enrolled because it's instructional rather than
    # data-driven.
    # The lake's tiers as data for the SharePoint graphic, by table count.
    $lakeVisualLine = Format-VisualLine -Kind 'lake' -Data ([ordered]@{
            analyticsOnly  = [int]$tierStats.AnalyticsOnly
            mirrored       = [int]$tierStats.MirroredOnly
            extended       = [int]$tierStats.MirroredExtended
            lakeOnly       = [int]$tierStats.LakeOnly
            retentionYears = 12
            uses           = @(
                [ordered]@{ name = 'KQL jobs'; detail = 'Promote summarised data back to the Analytics tier for detection' }
                [ordered]@{ name = 'KQL exploration'; detail = 'Query the lake in the Defender portal' }
                [ordered]@{ name = 'Notebooks'; detail = 'Jupyter notebooks in VS Code' }
                [ordered]@{ name = 'Sentinel graph'; detail = 'Blast radius and hunting' }
                [ordered]@{ name = 'MCP tools'; detail = 'Entity analysis and triage' }
            )
        })
    $lakeArchitectureBlock = if ($hasDataLake) {
        @"

## Lake architecture

How data flows once the tenant is onboarded to the Lake. Source → Analytics tier → automatic mirror to Lake → optional KQL job to promote summarised data back to Analytics for detection. Notebooks and graph operate against the Lake tier directly. Lake-only tables skip the Analytics tier entirely.

``````mermaid
flowchart LR
$lakeVisualLine
    SRC[Data sources] --> ANA[(Analytics tier<br/>real-time KQL, rules)]
    SRC --> LO[(Lake-only tables<br/>verbose / low-query)]
    ANA -. auto-mirror .-> LAKE
    LO --> LAKE[(Sentinel Data Lake<br/>12-year affordable retention<br/>Parquet, 6:1 compression)]
    LAKE --> JOB[KQL jobs<br/>promote → Analytics]
    JOB --> ANA
    LAKE --> KQL[KQL exploration<br/>Defender portal]
    LAKE --> NB[Jupyter notebooks<br/>VS Code]
    LAKE --> GR[Sentinel graph<br/>blast radius, hunting]
    LAKE --> MCP[MCP tools<br/>entity analyzer, triage]

    classDef ana fill:#5b3a1a,stroke:#a73,color:#fed
    classDef lake fill:#1a3b5b,stroke:#37a,color:#dfd
    classDef tool fill:#1a3b1a,stroke:#3a3,color:#dfd
    class ANA,LO ana
    class LAKE lake
    class JOB,KQL,NB,GR,MCP tool
``````
"@
    } else { '' }

    # Lake-tier tables block — only when there are explicit Lake-only
    # tables on the workspace.
    $lakeTablesBlock = if ($dlTableRows.Count -gt 0) {
        @"

## Lake-only tables

Tables explicitly configured to bypass the Analytics tier and route exclusively to the Lake. These tables bill against the **Data lake ingestion** + **Data processing** meters at a lower per-GB rate than Analytics, but **analytics rules cannot query them in real time**. Use the *Manage table* page in the Defender portal to switch a table's tier.

$(Format-BlueprintTable -Items $dlTableRows -Columns 'Table','RetentionDays','TotalRetention')
"@
    } else {
        @"

## Lake-only tables

_No tables currently route to the Lake-only tier on this workspace._ When Lake is enrolled, the default behaviour is to mirror all Analytics-tier tables to the Lake at the same retention (see the tier distribution above). *Lake-only* requires explicitly switching a table's tier in **Defender portal → Microsoft Sentinel → Data management → Tables**.
"@
    }

    # Usage evidence for the tables that keep data in the lake beyond analytics
    # retention: enabled rules reading the table, summary rules whose query
    # names it, search or restore output tables derived from it, and audited
    # queries from table-query-usage.json when the collector captured it.
    $summaryRuleQueries = @(
        $summaryRules | Where-Object { $_ } | ForEach-Object { [string](Get-BlueprintRawProperty (Get-BlueprintRawProperty $_ 'properties') 'query' '') }
    )
    $derivedSources = @{}
    foreach ($t in $workspaceTables) {
        $n = [string](Get-BlueprintRawProperty $t 'name' '')
        if ($n -match '^(.+?)_(SRCH|RST|KQL_CL)$') { $derivedSources[$matches[1]] = $true }
    }
    $tableQueryUsage = @{}
    foreach ($row in @(Read-BlueprintRawArray 'table-query-usage.json' | Where-Object { $_ })) {
        $tn = [string](Get-BlueprintRawProperty $row 'Table' '')
        if ($tn) { $tableQueryUsage[$tn] = $row }
    }
    $queryUsageCaptured = Test-Path -LiteralPath (Join-Path $rawRoot 'table-query-usage.json')
    $lakeUsageRows = @($retentionRows | ForEach-Object {
            $name = [string]$_.Table
            $use = @($tablesWithData | Where-Object { $_ -and (Get-BlueprintRawProperty $_ 'DataType') -eq $name }) | Select-Object -First 1
            $n = if ($rulesPerTable.ContainsKey($name)) { $rulesPerTable[$name] } else { 0 }
            $inSummary = [bool]($summaryRuleQueries | Where-Object { $_ -match ('\b' + [regex]::Escape($name) + '\b') } | Select-Object -First 1)
            $inDerived = $derivedSources.ContainsKey($name)
            $q = if ($tableQueryUsage.ContainsKey($name)) { $tableQueryUsage[$name] } else { $null }
            $queries = if ($q) { [int](ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $q 'Queries' 0)) } else { 0 }
            $used = ($n -gt 0) -or $inSummary -or $inDerived -or ($queries -gt 0)
            [pscustomobject]@{
                Table = $name; Tier = $(if ($_.Plan -eq 'DataLake') { 'Lake only' } else { 'Analytics + Lake extended' }); LakeOnlyDays = $_.LakeOnlyDays
                Gb90d          = $(if ($use) { [math]::Round((ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $use 'BillableLast90d' 0)), 2) } else { 0 })
                Rules = $n; SummaryRule = $(if ($inSummary) { 'Yes' } else { 'No' }); SearchRestore = $(if ($inDerived) { 'Yes' } else { 'No' })
                AuditedQueries = $(if ($queryUsageCaptured) { $queries } else { 'not captured' })
                Verdict        = $(if ($used) { 'In use' } else { 'No usage evidence' })
            }
        } | Sort-Object -Property @{ Expression = { $_.Verdict -eq 'In use' } }, @{ Expression = 'Gb90d'; Descending = $true })
    $noExtensionRows = @($operationalTables | Where-Object {
            $_ -and (Get-BlueprintRawProperty (Get-BlueprintRawProperty $_ 'properties') 'plan') -eq 'Analytics' -and
            (Get-TableTier -Table $_ -LakeEnrolled $hasDataLake) -eq 'MirroredOnly'
        } | ForEach-Object {
            $name = [string]$_.name
            $use = @($tablesWithData | Where-Object { $_ -and (Get-BlueprintRawProperty $_ 'DataType') -eq $name }) | Select-Object -First 1
            $gb = if ($use) { [math]::Round((ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $use 'BillableLast90d' 0)), 2) } else { 0 }
            if ($gb -le 0) { return }
            [pscustomobject]@{
                Table         = $name
                AnalyticsDays = Get-BlueprintRawProperty (Get-BlueprintRawProperty $_ 'properties') 'retentionInDays' ''
                TotalDays     = Get-BlueprintRawProperty (Get-BlueprintRawProperty $_ 'properties') 'totalRetentionInDays' ''
                Gb90d         = $gb
                Rules         = $(if ($rulesPerTable.ContainsKey($name)) { $rulesPerTable[$name] } else { 0 })
            }
        } | Sort-Object -Property Gb90d -Descending)
    $lakeUsageBlock = if (-not $hasDataLake) { '' } else {
        @"

## Lake usage evidence

For every table that keeps data in the lake beyond its analytics retention (or routes to the lake only): is anything reading it? The signals are enabled analytics rules that reference the table, summary rules whose query names it, search or restore output tables derived from it, and audited queries from ``LAQueryLogs`` over the last {lookback} where the collector captured them. A table with no evidence is not wrong, but its extended retention is a cost nobody has justified yet.

$(if ($lakeUsageRows.Count -gt 0) { Format-BlueprintTable -Items $lakeUsageRows -Columns 'Table','Tier','LakeOnlyDays','Gb90d','Rules','SummaryRule','SearchRestore','AuditedQueries','Verdict' } else { '_No table keeps data in the lake beyond its analytics retention, so there is nothing to assess._' })

## Analytics tables without extended lake retention

Tables receiving data whose total retention equals their analytics retention: on an enrolled workspace they are mirrored to the lake for the same period and nothing is kept once analytics retention expires. Confirm that matches the evidence-retention policy, especially for the tables rules depend on.

$(Format-BlueprintTable -Items $noExtensionRows -Columns 'Table','AnalyticsDays','TotalDays','Gb90d','Rules')
"@
    }

    # Left in the render context for later sections.
    $Context.lakeArchitectureBlock = $lakeArchitectureBlock
    $Context.lakeTablesBlock = $lakeTablesBlock
    $Context.lakeUsageBlock = $lakeUsageBlock
    if (Get-Variable -Name 'n' -Scope 0 -ErrorAction Ignore) { $Context.n = $n }
    $Context.retentionChartBlock = $retentionChartBlock
    $Context.tierChartBlock = $tierChartBlock
}
