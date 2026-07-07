#
# Sentinel-As-Code/Tools/Documenter/Private/Get-EffectiveConnectors.ps1
#
# Created by noodlemctwoodle on 13/05/2026.
#

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
        [Parameter(Mandatory = $false)] [object[]]$TablesWithData    = @(),
        # When provided, DCR data flows are filtered to those whose
        # `destinations` reference an LA destination on this workspace.
        # Without this filter the helper surfaces every DCR in the
        # subscription's data-collection scope, including DCRs that
        # send to OTHER workspaces, and they show up as orphan rows
        # against the current workspace.
        [Parameter(Mandatory = $false)] [string]$WorkspaceResourceId
    )

    # Source-family inference for the Active-table fallback. The captured
    # inventory doesn't always explain how a table is receiving data
    # (Defender XDR advanced hunting tables stream via the unified portal
    # rather than the classic Sentinel data-connector endpoint, for
    # example). Rather than labelling those rows "ingestion unmapped"
    # we surface the inferred product family so the reader at least
    # knows where the data is coming from.
    function _ActiveTableFamily {
        param([string]$Table)
        switch -Regex ($Table) {
            '^ThreatIntel'                                                                                  { return 'Microsoft Defender TI' }
            '^(SigninLogs|AuditLogs|AAD.*|MicrosoftGraphActivityLogs|MicrosoftServicePrincipalSignInLogs)$' { return 'Microsoft Entra ID' }
            '^(Device|Email|Url|Alert|Cloud|Identity).*'                                                    { return 'Microsoft Defender XDR' }
            '^ASim'                                                                                         { return 'ASIM normaliser' }
            '^Office'                                                                                       { return 'Office 365' }
            '^(CommonSecurityLog|Syslog)$'                                                                  { return 'CEF / Syslog' }
            '^(SecurityEvent|WindowsEvent|Event)$'                                                          { return 'Windows events' }
            '^AzureActivity$'                                                                               { return 'Azure Activity' }
            '^(AzureDiagnostics|AzureMetrics)$'                                                             { return 'Azure resource diagnostics' }
            '^Intune'                                                                                       { return 'Intune' }
            '^App'                                                                                          { return 'Application Insights' }
            '^Dataverse'                                                                                    { return 'Power Platform' }
            '^(LAQueryLogs|Usage|Heartbeat|Operation|Perf|SentinelAudit)$'                                  { return 'Workspace operations' }
            '^(UserPeerAnalytics|BehaviorAnalytics)$'                                                       { return 'UEBA (Sentinel internal)' }
            '_CL$'                                                                                          { return 'Custom log (CCF / DCR not captured)' }
            default                                                                                         { return 'Unmapped' }
        }
    }

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
            # Format helpers live in the renderer; degrade gracefully when
            # invoked from a test context that doesn't dot-source them.
            if ($null -ne $r.BillableLast24h) {
                $last24h = if (Get-Command Format-Gb -ErrorAction SilentlyContinue) { Format-Gb $r.BillableLast24h } else { [string]$r.BillableLast24h }
            }
            if ($r.LastIngested) {
                $lastIngested = if (Get-Command Format-DateUtc -ErrorAction SilentlyContinue) { Format-DateUtc $r.LastIngested } else { [string]$r.LastIngested }
            }
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
    # When a WorkspaceResourceId is supplied, filter DCRs and their data
    # flows to only those that target the current workspace. DCRs are
    # captured at subscription scope by the exporter so DCRs that send
    # to other workspaces in the same subscription would otherwise be
    # surfaced as if they were ingesting into this workspace.
    foreach ($dcr in $Dcrs) {
        $dataFlows = $dcr.properties.dataFlows
        if ($null -eq $dataFlows) { continue }

        # Build the in-scope destination set for this DCR. When no
        # WorkspaceResourceId is given, every LA destination is in
        # scope (backward-compatible default). Comparison is
        # case-insensitive on the LA workspace resource ID, as Azure
        # normalises segment case inconsistently across APIs.
        $inScopeDestNames = $null
        if ($WorkspaceResourceId) {
            $inScopeDestNames = New-Object System.Collections.Generic.HashSet[string]
            $laDests = $null
            if ($dcr.properties.PSObject.Properties.Name -contains 'destinations' -and $dcr.properties.destinations) {
                if ($dcr.properties.destinations.PSObject.Properties.Name -contains 'logAnalytics') {
                    $laDests = $dcr.properties.destinations.logAnalytics
                }
            }
            if ($laDests) {
                foreach ($d in $laDests) {
                    if ([string]::Equals([string]$d.workspaceResourceId, $WorkspaceResourceId, [System.StringComparison]::OrdinalIgnoreCase)) {
                        [void]$inScopeDestNames.Add([string]$d.name)
                    }
                }
            }
            # DCR has no destination targeting the current workspace, skip entirely.
            if ($inScopeDestNames.Count -eq 0) { continue }
        }

        foreach ($flow in $dataFlows) {
            # Skip flows whose destinations don't target this workspace.
            if ($null -ne $inScopeDestNames) {
                $flowDests = @($flow.destinations)
                $hit = $false
                foreach ($fd in $flowDests) {
                    if ($inScopeDestNames.Contains([string]$fd)) { $hit = $true; break }
                }
                if (-not $hit) { continue }
            }
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

    # 5. Active tables with no attributable ingestion source. The
    # Identifier surfaces the inferred product family (Microsoft
    # Defender XDR / Microsoft Entra ID / etc.) so reviewers see what
    # the data is rather than a generic "ingestion unmapped" label.
    # Common sources: Defender XDR advanced hunting tables that stream
    # via the unified portal, Entra ID sign-in/audit tables routed
    # through the AzureActiveDirectory data-connector even when the
    # connector itself didn't enumerate the dataType, and Sentinel-
    # internal tables (BehaviorAnalytics, UserPeerAnalytics) populated
    # by the UEBA engine.
    foreach ($t in $TablesWithData) {
        if (-not $t.DataType) { continue }
        if ($claimedTables.Contains($t.DataType)) { continue }
        $vol = if ($null -ne $t.BillableLast24h) { [double]$t.BillableLast24h } else { 0 }
        if ($vol -le 0) { continue }
        $family = _ActiveTableFamily -Table $t.DataType
        _AddRow -source 'Active-table' -identifier $family -table $t.DataType
    }

    return $rows.ToArray()
}
