<#
.SYNOPSIS
    Synthesise an "effective connectors" view from the captured inventory.

.DESCRIPTION
    The Sentinel `dataConnectors` and `dataConnectorDefinitions` endpoints only
    enumerate the connectors that explicitly register through the Sentinel
    resource provider. A modern workspace ingests most of its data through
    DCRs and diagnostic-settings pipelines that never appear in those two
    endpoints. Rendering the connectors section solely from those two captures
    therefore makes a well-instrumented workspace look almost empty.

    This helper produces a single unified list of every ingestion source the
    workspace actually has, joining classic + CCF + DCR + diagnostic-settings
    captures plus a `tables-with-data` heuristic for tables receiving data with
    no explicit ingestion mechanism attributable from the other captures.

    The precedence rules avoid double-counting the same data source:

    1. **Classic connector** → if any classic dataConnector covers a target
       table, that table is marked Classic-owned. Any later sighting of the
       same table is suppressed.
    2. **CCF connector definition** → CCF entries are listed separately
       because their data-type-to-table mapping is connector-specific and not
       always known to this helper; they're surfaced by Name/Title/Publisher
       only and don't claim ownership of any specific table.
    3. **DCR-driven** → each DCR data-flow's `outputStream` resolves to a
       workspace table (Microsoft-/Custom- prefixes stripped). Tables already
       claimed by classic are skipped.
    4. **Diagnostic settings** → each enabled log category resolves to a
       workspace table via the category-to-table convention. Already-claimed
       tables are skipped.
    5. **Active table, ingestion unmapped** → any remaining table with
       `BillableLast24h > 0` from `tables-with-data.json` is surfaced as an
       active table whose ingestion source the documenter couldn't attribute.
       This is a deliberate visibility signal: if a workspace is receiving
       data but no captured ingestion mechanism explains it, an operator
       should know.

.PARAMETER ClassicConnectors
    Parsed array from `_raw/data-connectors-classic.json`.

.PARAMETER CcfDefinitions
    Parsed array from `_raw/data-connector-definitions.json`.

.PARAMETER Dcrs
    Parsed array from `_raw/dcrs.json`.

.PARAMETER DiagnosticSettings
    Parsed array from `_raw/diagnostic-settings.json`.

.PARAMETER TablesWithData
    Parsed array from `_raw/tables-with-data.json`.

.OUTPUTS
    [pscustomobject[]] with columns: Source, Identifier, Table, Last24hGB, LastIngested.
#>
function Get-EffectiveConnectors {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [object[]]$ClassicConnectors = @(),
        [Parameter(Mandatory = $false)] [object[]]$CcfDefinitions    = @(),
        [Parameter(Mandatory = $false)] [object[]]$Dcrs              = @(),
        [Parameter(Mandatory = $false)] [object[]]$DiagnosticSettings = @(),
        [Parameter(Mandatory = $false)] [object[]]$TablesWithData    = @()
    )

    # Table lookup for the activity-join columns.
    $tablesByName = @{}
    foreach ($t in $TablesWithData) {
        if ($t.DataType) { $tablesByName[$t.DataType] = $t }
    }

    # Tracks tables already attributed to an earlier source in the precedence chain.
    $claimedTables = New-Object System.Collections.Generic.HashSet[string]
    $rows = New-Object System.Collections.Generic.List[object]

    function _AddRow {
        param([string]$source, [string]$identifier, [string]$table)
        $last24h = ''
        $lastIngested = ''
        if ($table -and $tablesByName.ContainsKey($table)) {
            $r = $tablesByName[$table]
            if ($null -ne $r.BillableLast24h) { $last24h = [string]$r.BillableLast24h }
            if ($r.LastIngested) { $lastIngested = [string]$r.LastIngested }
        }
        $rows.Add([pscustomobject]@{
            Source       = $source
            Identifier   = $identifier
            Table        = $table
            Last24hGB    = $last24h
            LastIngested = $lastIngested
        })
        if ($table) { [void]$claimedTables.Add($table) }
    }

    # 1. Classic connectors → resolve each data type to a target table.
    foreach ($c in $ClassicConnectors) {
        $kind = $c.kind
        $dataTypes = $c.properties.dataTypes
        if ($null -eq $dataTypes) { continue }
        foreach ($dtName in @($dataTypes.PSObject.Properties.Name)) {
            $table = Get-ConnectorTargetTable -Kind $kind -DataType $dtName
            if (-not $table) { continue }
            _AddRow -source 'Classic' -identifier "$kind/$dtName" -table $table
        }
    }

    # 2. CCF connector definitions → list by name; no table claim.
    foreach ($d in $CcfDefinitions) {
        $identifier = if ($d.properties.connectorUiConfig.title) { $d.properties.connectorUiConfig.title } else { $d.name }
        $rows.Add([pscustomobject]@{
            Source       = 'CCF'
            Identifier   = $identifier
            Table        = ''
            Last24hGB    = ''
            LastIngested = ''
        })
    }

    # 3. DCR-driven → derive table from each data flow's outputStream.
    foreach ($dcr in $Dcrs) {
        $dataFlows = $dcr.properties.dataFlows
        if ($null -eq $dataFlows) { continue }
        foreach ($flow in $dataFlows) {
            $output = $flow.outputStream
            if (-not $output) { continue }
            $table = $output -replace '^Microsoft-','' -replace '^Custom-',''
            if ($claimedTables.Contains($table)) { continue }
            _AddRow -source 'DCR' -identifier $dcr.name -table $table
        }
    }

    # 4. Diagnostic settings → derive table from log category.
    foreach ($ds in $DiagnosticSettings) {
        $logs = $ds.properties.logs
        if ($null -eq $logs) { continue }
        foreach ($log in $logs) {
            if (-not $log.enabled) { continue }
            $cat = $log.category
            if (-not $cat) { continue }
            if ($claimedTables.Contains($cat)) { continue }
            _AddRow -source 'Diagnostic' -identifier $ds.name -table $cat
        }
    }

    # 5. Active tables with no attributable ingestion source.
    foreach ($t in $TablesWithData) {
        if (-not $t.DataType) { continue }
        if ($claimedTables.Contains($t.DataType)) { continue }
        $vol = if ($null -ne $t.BillableLast24h) { [double]$t.BillableLast24h } else { 0 }
        if ($vol -le 0) { continue }
        _AddRow -source 'Active-table' -identifier '(ingestion unmapped)' -table $t.DataType
    }

    return $rows.ToArray()
}
