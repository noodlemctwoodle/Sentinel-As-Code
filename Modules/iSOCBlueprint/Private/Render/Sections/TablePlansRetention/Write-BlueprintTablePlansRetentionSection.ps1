#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 81-table-plans-retention.md (part 1 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/TablePlansRetention/Write-BlueprintTablePlansRetentionSection.ps1
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
function Write-BlueprintTablePlansRetentionSection {
    <#
    .SYNOPSIS
        Build the figures for and write 81-table-plans-retention.md (part 1 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $connectedConnectorIds = $Context.connectedConnectorIds
    $connectorCatalogue = $Context.connectorCatalogue
    $customDetectionRefs = $Context.customDetectionRefs
    $n = $Context.n
    $operationalTables = $Context.operationalTables
    $populatedTableNames = $Context.populatedTableNames
    $ruleTableRefs = $Context.ruleTableRefs
    $run = $Context.run
    $tablesWithData = $Context.tablesWithData
    $usage = $Context.usage
    $workspaceTables = $Context.workspaceTables

    # ---------------------------------------------------------------------------
    # Section: 81 — table plans + retention
    # ---------------------------------------------------------------------------
    $tableSchemaByName = @{}
    foreach ($t in $workspaceTables) { $tableSchemaByName[$t.name] = $t }

    # Build rows for the OPERATIONAL set only (populated tables + custom logs).
    # The full workspace catalogue (~800 entries) is summarised separately so a
    # reader doesn't have to scroll through 750 unpopulated Microsoft schemas to
    # find the 50 tables that actually matter.
    $tableRows = foreach ($t in $operationalTables) {
        $name = $t.name
        $usage = $tablesWithData | Where-Object { $_.DataType -eq $name } | Select-Object -First 1
        [pscustomobject]@{
            Name         = $name
            Plan         = $t.properties.plan
            Interactive  = $t.properties.retentionInDays
            Total        = $t.properties.totalRetentionInDays
            Archive      = $t.properties.archiveRetentionInDays
            Type         = $t.properties.schema.tableType
            Gb90d        = if ($usage) { [math]::Round([double]$usage.BillableLast90d, 2) } else { 0 }
            Last24h      = if ($usage -and [double]$usage.BillableLast24h -gt 0) { 'Yes' } else { '' }
            LastIngested = if ($usage) { Format-DateUtc $usage.LastIngested } else { '' }
        }
    }

    $active = @($tableRows | Where-Object { $_.Last24h })
    $silent = @($tableRows | Where-Object {
            # Had data in 90d window (LastIngested set) but nothing in last 24h —
            # likely connector breakage. Excludes orphan custom tables that never
            # received data.
            -not $_.Last24h -and $_.LastIngested
        })
    # Orphan = custom log table with NO ingestion in the last 90 days. We
    # deliberately don't flag Microsoft pre-defined tables as orphans because
    # their schema exists by default in every workspace.
    $orphans = @($tableRows | Where-Object { -not $_.LastIngested -and $_.Type -eq 'CustomLog' })

    # Plan summary covers operational tables only.
    $gbByPlan = $tableRows | Group-Object Plan | ForEach-Object {
        [pscustomobject]@{
            Plan   = $_.Name
            Tables = $_.Count
            Gb90d  = [math]::Round(($_.Group | Measure-Object Gb90d -Sum).Sum, 2)
        }
    }

    # Catalogue summary: Microsoft pre-defined tables that never received
    # data. Most workspaces carry hundreds of these; every name is listed.
    $catalogueOnly = @($workspaceTables | Where-Object {
            ($_.properties.schema.tableType -ne 'CustomLog') -and
            (-not $populatedTableNames.ContainsKey($_.name))
        })
    $catalogueOnlyRows = @($catalogueOnly | ForEach-Object {
            $name = [string]$_.name
            [pscustomobject]@{
                Table     = $name
                Connector = $(
                    if ($connectorCatalogue) {
                        Get-TableConnectorLabel -Catalogue $connectorCatalogue -Table $name -ConnectedIds $connectedConnectorIds
                    } else { '' }
                )
            }
        } | Sort-Object Table)

    # Detection coverage per operational table, from the enabled rules' table
    # references. Empty when the collector did not compute the mapping.
    $rulesPerTable = @{}
    foreach ($ref in $ruleTableRefs) {
        if ($ref.Enabled -ne $true) { continue }
        foreach ($t in @($ref.Tables)) {
            if (-not $t) { continue }
            if (-not $rulesPerTable.ContainsKey($t)) { $rulesPerTable[$t] = 0 }
            $rulesPerTable[$t]++
        }
    }
    $customDetectionsPerTable = @{}
    foreach ($cd in $customDetectionRefs) {
        if (-not $cd -or (Get-BlueprintRawProperty $cd 'Enabled' $false) -ne $true) { continue }
        foreach ($t in @(Get-BlueprintRawProperty $cd 'Tables' @())) {
            if ($t) { if (-not $customDetectionsPerTable.ContainsKey($t)) { $customDetectionsPerTable[$t] = 0 }; $customDetectionsPerTable[$t]++ }
        }
    }
    $coverageRows = @($tableRows | Where-Object { $_.Gb90d -gt 0 } | ForEach-Object {
            $n = if ($rulesPerTable.ContainsKey($_.Name)) { $rulesPerTable[$_.Name] } else { 0 }
            $cdn = if ($customDetectionsPerTable.ContainsKey($_.Name)) { $customDetectionsPerTable[$_.Name] } else { 0 }
            [pscustomobject]@{
                Name             = $_.Name
                Plan             = $_.Plan
                Gb90d            = $_.Gb90d
                Rules            = $n
                CustomDetections = $cdn
                Coverage         = if ($n -gt 0 -and $cdn -gt 0) {
                    'Rule and custom detection'
                } elseif ($n -gt 0) { 'Sentinel rule' } elseif ($cdn -gt 0) { 'Custom detection' } else { 'None' }
            }
        } | Sort-Object -Property Gb90d -Descending)
    $coverageBlock = if ($ruleTableRefs.Count -eq 0) {
        '_Table-to-rule mapping was not computed in this run._'
    } else {
        Format-BlueprintTable -Items $coverageRows -Columns 'Name', 'Plan', 'Gb90d', 'Rules', 'CustomDetections', 'Coverage'
    }

    # Silent tables in detail, split by whether an enabled rule reads them: a
    # silent table nobody detects on is a cost question, one that rules depend
    # on is a detection outage ([SAC-MON-06]).
    $docNow = $(
        if ($run -and (Get-BlueprintRawProperty $run 'CompletedAtUtc')) {
            ([datetime]::Parse([string]$run.CompletedAtUtc, [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AssumeUniversal)).ToUniversalTime()
        } else { [datetime]::UtcNow }
    )
    $silentRows = @($silent | ForEach-Object {
            $name = $_.Name
            $use = @($tablesWithData | Where-Object { $_ -and (Get-BlueprintRawProperty $_ 'DataType') -eq $name }) | Select-Object -First 1
            $lastRaw = Get-BlueprintRawProperty $use 'LastIngested'
            $days = ''
            if ($lastRaw) {
                $parsed = [datetime]::MinValue
                if ([datetime]::TryParse([string]$lastRaw, [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
                    $days = [int][math]::Floor(($docNow - $parsed.ToUniversalTime()).TotalDays)
                }
            }
            $n = if ($rulesPerTable.ContainsKey($name)) { $rulesPerTable[$name] } else { 0 }
            [pscustomobject]@{
                Name         = $name
                Plan         = $_.Plan
                Gb90d        = $_.Gb90d
                LastIngested = $_.LastIngested
                DaysSilent   = $days
                Rules        = $n
                Impact       = if ($n -gt 0) { 'Detection outage' } else { 'Cost only' }
            }
        } | Sort-Object -Property @{ Expression = 'Rules'; Descending = $true }, @{ Expression = 'Gb90d'; Descending = $true })
    $silentWithRules = @($silentRows | Where-Object { $_.Rules -gt 0 })
    $silentDetail = if ($silentRows.Count -eq 0) { '' } else {
        @"

$(Format-BlueprintCount $silentWithRules.Count) of these are read by enabled analytics rules; those rules still run on schedule and return nothing, so the detection has gone dark without an alert. The rest are cost-only questions: confirm the source was retired on purpose, then stop the collection or delete the table.

$(Format-BlueprintTable -Items $silentRows -Columns 'Name','Plan','Gb90d','LastIngested','DaysSilent','Rules','Impact')
"@
    }

    # Classic custom tables: created through the legacy HTTP Data Collector API
    # (or the MMA custom-log path) rather than a DCR. The API retires on
    # 14 September 2026; every table still written through it needs a DCR
    # before then. tableSubType is the authoritative marker when present.
    $classicTables = @($workspaceTables | Where-Object {
            $_ -and (Get-BlueprintRawProperty (Get-BlueprintRawProperty (Get-BlueprintRawProperty $_ 'properties') 'schema') 'tableType') -eq 'CustomLog' -and
            (Get-BlueprintRawProperty (Get-BlueprintRawProperty (Get-BlueprintRawProperty $_ 'properties') 'schema') 'tableSubType') -eq 'Classic'
        })
    $dcrBasedCustom = @(
        $workspaceTables |
            Where-Object {
                $_ -and (Get-BlueprintRawProperty (Get-BlueprintRawProperty (Get-BlueprintRawProperty $_ 'properties') 'schema') 'tableSubType') -eq
                'DataCollectionRuleBased'
            }
    ).Count
    $classicRows = @($classicTables | ForEach-Object {
            $name = [string]$_.name
            $props = Get-BlueprintRawProperty $_ 'properties'
            $use = @($tablesWithData | Where-Object { $_ -and (Get-BlueprintRawProperty $_ 'DataType') -eq $name }) | Select-Object -First 1
            $gb24 = ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $use 'BillableLast24h' 0)
            $gb7 = ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $use 'BillableLast7d' 0)
            $gb30 = ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $use 'BillableLast30d' 0)
            $gb90 = ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $use 'BillableLast90d' 0)
            $status = if ($gb24 -gt 0) {
                'Active (last 24h)'
            } elseif ($gb7 -gt 0) {
                'Active (last {recent-d})'
            } elseif ($gb30 -gt 0) { 'Intermittent' } elseif ($gb90 -gt 0) { 'Stale' } else { 'No data in {lookback-d}' }
            $n = if ($rulesPerTable.ContainsKey($name)) { $rulesPerTable[$name] } else { 0 }
            $action = if ($gb90 -le 0) {
                'Confirm the source is retired, then delete the table'
            } elseif ($n -eq 0) {
                'Still ingesting with no rule reading it: migrate to a DCR-based table or stop the collection'
            } else { 'Rules depend on it: migrate to the Logs Ingestion API and a DCR before the retirement date' }
            [pscustomobject]@{
                Name         = $name
                Plan         = [string](Get-BlueprintRawProperty $props 'plan' '')
                Interactive  = Get-BlueprintRawProperty $props 'retentionInDays' ''
                Total        = Get-BlueprintRawProperty $props 'totalRetentionInDays' ''
                Gb90d        = [math]::Round($gb90, 2)
                LastIngested = $(if ($use) { Format-DateUtc (Get-BlueprintRawProperty $use 'LastIngested') } else { '' })
                Status       = $status
                Rules        = $n
                Action       = $action
            }
        } | Sort-Object -Property @{ Expression = { $_.Status -eq 'No data in {lookback-d}' } }, @{ Expression = 'Gb90d'; Descending = $true })
    $classicActiveCount = @($classicRows | Where-Object { $_.Status -like 'Active*' }).Count
    $classicDormantCount = @($classicRows | Where-Object { $_.Status -in @('Stale', 'No data in {lookback-d}') }).Count
    $classicBlock = if ($classicRows.Count -eq 0) {
        "_No classic custom tables: every custom table in this workspace is DCR-based ($(Format-BlueprintPlural $dcrBasedCustom 'table')), so nothing is exposed to the Data Collector API retirement._"
    } else {
        @"
**$(Format-BlueprintCount $classicRows.Count)** classic $(Format-BlueprintPlural $classicRows.Count 'table' -NoCount): **$(Format-BlueprintCount $classicActiveCount)** still ingesting, **$(Format-BlueprintCount $classicDormantCount)** stale or empty, beside **$(Format-BlueprintCount $dcrBasedCustom)** DCR-based custom $(Format-BlueprintPlural $dcrBasedCustom 'table' -NoCount). [SAC-PLT-02] fires for the ones still receiving data.

$(Format-BlueprintTable -Items $classicRows -Columns 'Name','Plan','Interactive','Total','Gb90d','LastIngested','Status','Rules','Action')
"@
    }

    # Plan pie inputs.
    $planPieAnalytics = ($gbByPlan | Where-Object { $_.Plan -eq 'Analytics' } | Measure-Object -Property Tables -Sum).Sum
    $planPieBasic = ($gbByPlan | Where-Object { $_.Plan -eq 'Basic' } | Measure-Object -Property Tables -Sum).Sum
    $planPieAuxiliary = ($gbByPlan | Where-Object { $_.Plan -eq 'Auxiliary' } | Measure-Object -Property Tables -Sum).Sum
    if (-not $planPieAnalytics) { $planPieAnalytics = 0 }
    if (-not $planPieBasic) { $planPieBasic = 0 }
    if (-not $planPieAuxiliary) { $planPieAuxiliary = 0 }

    # Left in the render context for later sections.
    $Context.active = $active
    $Context.catalogueOnly = $catalogueOnly
    $Context.catalogueOnlyRows = $catalogueOnlyRows
    $Context.classicBlock = $classicBlock
    $Context.coverageBlock = $coverageBlock
    $Context.gbByPlan = $gbByPlan
    if (Get-Variable -Name 'name' -Scope 0 -ErrorAction Ignore) { $Context.name = $name }
    $Context.orphans = $orphans
    $Context.planPieAnalytics = $planPieAnalytics
    $Context.planPieAuxiliary = $planPieAuxiliary
    $Context.planPieBasic = $planPieBasic
    $Context.rulesPerTable = $rulesPerTable
    $Context.silent = $silent
    $Context.silentDetail = $silentDetail
    $Context.t = $t
    $Context.tableRows = $tableRows
}
