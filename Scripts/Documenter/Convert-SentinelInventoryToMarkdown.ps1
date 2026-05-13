<#
.SYNOPSIS
    Render the JSON snapshot under SecurityDocs/<workspace>/_raw/ into the human-readable
    Markdown report under SecurityDocs/<workspace>/.

.DESCRIPTION
    Pure file-to-file transformation — no Azure dependency. Designed so the renderer can
    be exercised end-to-end by Pester fixtures without auth, and so a re-run produces the
    same output for the same input (idempotent).

    Sections produced (one MD file each, plus index.md):

      00-overview.md
      10-data-connectors.md
      20-analytics-rules.md
      25-mitre-coverage.md
      30-hunting-queries.md
      35-parsers-functions.md
      40-workbooks.md
      50-watchlists.md
      60-automation-rules-playbooks.md
      70-content-hub.md
      80-workspace.md
      81-table-plans-retention.md
      82-dedicated-cluster.md
      83-data-collection.md
      84-cost-estimate.md
      85-rbac.md
      86-subscription-context.md
      90-gap-analysis.md
      99-references.md

.PARAMETER InputRoot
    Path to the workspace root that contains _raw/. Defaults to ./SecurityDocs/<WorkspaceName>.

.PARAMETER OutputRoot
    Folder for the rendered Markdown. Defaults to InputRoot.

.PARAMETER WorkspaceName
    Workspace name. Used to title sections and to default InputRoot/OutputRoot.

.PARAMETER ResourcesRoot
    Folder containing best-practices.json, mitre-attack-v18.json, etc. Defaults to
    Scripts/Documenter/Private/Resources.

.NOTES
    Author:         noodlemctwoodle
    Component:      Sentinel Documenter — Renderer
    Last Updated:   2026-05-06
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [Parameter(Mandatory = $false)]
    [string]$InputRoot,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [string]$ResourcesRoot = (Join-Path $PSScriptRoot 'Private/Resources')
)

# Strict mode is intentionally NOT set in the renderer.
# The renderer reads JSON shapes from many heterogeneous Azure REST endpoints whose
# nested property graphs differ between API versions (and frequently include null
# branches). StrictMode 'Latest' would force every read access to be defensively
# wrapped, polluting every interpolation. We keep strict mode in the collector and
# the gap engine where shapes are bounded; here we trade strictness for resilience.
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

if (-not $InputRoot)  {
    $InputRoot = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath "SecurityDocs/$WorkspaceName"
}
if (-not $OutputRoot) { $OutputRoot = $InputRoot }

$rawRoot = Join-Path $InputRoot '_raw'
if (-not (Test-Path $rawRoot)) {
    throw "Renderer cannot find raw inventory at $rawRoot. Run Export-SentinelInventory.ps1 first."
}
if (-not (Test-Path $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

# Dot-source private helpers.
. (Join-Path $PSScriptRoot 'Private/Get-EffectiveConnectors.ps1')

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Read-Raw([string]$Name) {
    $p = Join-Path $rawRoot $Name
    if (-not (Test-Path $p)) { return $null }
    $raw = Get-Content $p -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json -Depth 32)
}

function Read-RawArray([string]$Name) {
    # Array-shaped reader. Use this when the caller intends to iterate the
    # result via ForEach-Object. Returns an empty array when the underlying
    # file is missing or empty, rather than the one-element-null-array a
    # naive array-wrap of Read-Raw produces. The phantom all-null row that
    # iterating a one-element-null-array yields (and PowerShells own quirk
    # that returns 0 for the Count property of a null reference) is the bug
    # this helper prevents.
    $value = Read-Raw $Name
    if ($null -eq $value) { return ,@() }
    return @($value)
}

function Write-Section([string]$FileName, [string]$Body) {
    $target = Join-Path $OutputRoot $FileName
    $body = $Body.TrimEnd() + [Environment]::NewLine
    Set-Content -Path $target -Value $body -Encoding UTF8
    Write-Information "  ↳ rendered $FileName"
}

function Format-Banner {
    param([string]$Title)
    $run = Read-Raw 'run-context.json'
    $started = if ($run) { $run.StartedAtUtc } else { '' }
    @"
# $Title

> **Workspace** ``$WorkspaceName``  ·  **Generated** $started UTC  ·  **Documenter** v$($run.DocumenterVersion)
"@
}

function Format-Table {
    <# Render an array of [pscustomobject] as a Markdown table. Headers come from -Columns.
       -Items is intentionally non-mandatory because callers commonly pipe empty arrays
       through ForEach-Object — a null reaching this function is the empty case, not an
       error. #>
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] [object[]]$Items,
        [Parameter(Mandatory = $true)]  [string[]]$Columns,
        [Parameter(Mandatory = $false)] [string]$EmptyMessage = '_None._'
    )
    if (-not $Items -or @($Items).Count -eq 0) { return $EmptyMessage }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('| ' + ($Columns -join ' | ') + ' |')
    [void]$sb.AppendLine('|' + (($Columns | ForEach-Object { '---' }) -join '|') + '|')
    foreach ($item in $Items) {
        $row = foreach ($col in $Columns) {
            $val = $null
            if ($item -is [hashtable] -and $item.ContainsKey($col)) { $val = $item[$col] }
            elseif ($item.PSObject.Properties.Name -contains $col) { $val = $item.$col }
            $cell = if ($null -eq $val) { '' } else { ([string]$val) -replace '\|','\|' -replace '[\r\n]+',' ' }
            $cell
        }
        [void]$sb.AppendLine('| ' + ($row -join ' | ') + ' |')
    }
    return $sb.ToString().TrimEnd()
}

function Format-Severity-Badge { param([string]$Severity)
    switch ($Severity) {
        'Critical' { return '🔴 Critical' }
        'Warning'  { return '🟠 Warning'  }
        'Info'     { return '🔵 Info'     }
        default    { return $Severity     }
    }
}

# Workspace feature-flag boolean → display string. The Sentinel API omits
# these fields when they're at their default value (= False), so a missing
# property must render as "False" not as an empty cell. Otherwise readers
# can't tell "disabled by default" from "report didn't capture this field".
function Format-FeatureFlag {
    param([psobject]$Container, [string]$Property)
    if ($null -eq $Container) { return 'False' }
    if ($Container.PSObject.Properties.Name -notcontains $Property) { return 'False' }
    $val = $Container.$Property
    if ($null -eq $val) { return 'False' }
    return [string]$val
}

# ---------------------------------------------------------------------------
# Section: 00-overview
# ---------------------------------------------------------------------------
$workspace          = Read-Raw 'workspace.json'
$run                = Read-Raw 'run-context.json'
$rules              = Read-RawArray 'alert-rules.json'
$connectors         = Read-RawArray 'data-connectors-classic.json'
$workbooksSaved     = Read-RawArray 'workbooks-saved.json'
$dcrs               = Read-RawArray 'dcrs.json'
$tablesWithData     = Read-RawArray 'tables-with-data.json'
$workspaceTables    = Read-RawArray 'workspace-tables.json'
$watchlists         = Read-RawArray 'watchlists.json'
$autoRules          = Read-RawArray 'automation-rules.json'
$gapFindings        = Read-RawArray 'gap-analysis.json'
$cost               = Read-Raw 'cost-estimate.json'

$enabledRules = @($rules | Where-Object { $_.properties.enabled -eq $true })
$populatedTables = @($tablesWithData | Where-Object { [double]($_.BillableLast90d) -gt 0 })

# Names of tables that have ever received data in the last 90d. Used to
# scope reports to the operationally relevant subset — the workspace's
# table catalogue lists ~800 Microsoft-defined schemas regardless of
# whether the customer has onboarded a source for them, so 'tables with
# schema' is misleading on its own.
$populatedTableNames = @{}
foreach ($t in $populatedTables) {
    if ($t.DataType) { $populatedTableNames[$t.DataType] = $true }
}

# 'Operational' tables = Microsoft tables that have data, plus all
# CustomLog tables (always intended to receive data, surface even when
# silent). Excludes ~750 Microsoft pre-defined schemas the workspace
# never received data for — those are catalogue, not deployment.
$operationalTables = @($workspaceTables | Where-Object {
    $tt = $_.properties.schema.tableType
    ($tt -eq 'CustomLog') -or ($populatedTableNames.ContainsKey($_.name))
})
$catalogueOnlyCount = $workspaceTables.Count - $operationalTables.Count

$top5Findings = @($gapFindings | Sort-Object @{Expression={ switch($_.Severity){'Critical'{0}'Warning'{1}'Info'{2}default{3}} }} | Select-Object -First 5)

$overviewBody = @"
$(Format-Banner -Title "Microsoft Sentinel Workspace — Overview")

## Headline

| | |
|---|---|
| Workspace ID | ``$($workspace.properties.customerId)`` |
| Region | ``$($workspace.location)`` |
| SKU | ``$($workspace.properties.sku.name)`` |
| Default retention | $($workspace.properties.retentionInDays) days |
| Daily cap | $(if ($workspace.properties.workspaceCapping.dailyQuotaGb -eq -1) { 'Unlimited' } else { "$($workspace.properties.workspaceCapping.dailyQuotaGb) GB" }) |
| Replication | $(if ($workspace.properties.replication.enabled) { 'Enabled' } else { 'Disabled' }) |
| Public network access (ingestion) | ``$($workspace.properties.publicNetworkAccessForIngestion)`` |
| Public network access (query) | ``$($workspace.properties.publicNetworkAccessForQuery)`` |

## Counts

| Artefact | Count |
|---|---:|
| Data connectors | $($connectors.Count) |
| Analytics rules | $($rules.Count) (enabled: $($enabledRules.Count)) |
| Automation rules | $($autoRules.Count) |
| Watchlists | $($watchlists.Count) |
| Workbooks | $($workbooksSaved.Count) |
| Data Collection Rules | $($dcrs.Count) |
| Tables operational (populated + custom logs) | $($operationalTables.Count) |
| Tables receiving data (90d) | $($populatedTables.Count) |
| Catalogue-only Microsoft schemas (never ingested) | $catalogueOnlyCount |

## Estimated monthly cost

$(if ($cost) {
"**$($cost.MonthlyTotal) $($cost.Currency)** for the workspace, computed from the last 30 days of `Usage` against the Azure Retail Prices API on $($cost.AsOfUtc). See [84-cost-estimate.md](84-cost-estimate.md) for breakdown and methodology."
} else { '_Cost estimate not available._' })

## Top findings

$(if ($top5Findings.Count -gt 0) {
($top5Findings | ForEach-Object {
    "- **$(Format-Severity-Badge $_.Severity)** [$($_.Id)] $($_.Title) — $($_.Evidence) [Learn]($($_.Learn))"
}) -join [Environment]::NewLine
} else { '_No findings — clean run._' })

See the rest of this folder for deep-dive sections: [data connectors](10-data-connectors.md), [analytics rules](20-analytics-rules.md), [MITRE coverage](25-mitre-coverage.md), [workbooks](40-workbooks.md), [workspace](80-workspace.md), [table plans + retention](81-table-plans-retention.md), [data collection](83-data-collection.md), [cost estimate](84-cost-estimate.md), [RBAC](85-rbac.md), [gap analysis](90-gap-analysis.md).
"@

Write-Section '00-overview.md' $overviewBody

# ---------------------------------------------------------------------------
# Section: 10-data-connectors
# ---------------------------------------------------------------------------
# Classic connector resources are named by GUID and store per-data-type state
# under properties.dataTypes.<typename>.state. The earlier rendering pulled
# Name=$_.name (GUID) and State=$_.properties.connectorUiConfig.connectivityCriterias
# — a CCF field that doesn't exist on the classic schema, so State was always
# blank. The fix below maps Kind to a friendly Title, aggregates per-data-type
# state into a single overall state column, and lists the data-type names in
# their own column.
function Get-ConnectorFriendlyTitle {
    param([string]$Kind, [psobject]$Connector, [hashtable]$CcfTitleByName = @{})
    switch ($Kind) {
        'AzureActiveDirectory'                         { 'Microsoft Entra ID' }
        'MicrosoftCloudAppSecurity'                    { 'Microsoft Defender for Cloud Apps' }
        'MicrosoftDefenderAdvancedThreatProtection'    { 'Microsoft Defender for Endpoint' }
        'MicrosoftPurviewInformationProtection'        { 'Microsoft Purview Information Protection' }
        'MicrosoftThreatIntelligence'                  { 'Microsoft Defender Threat Intelligence' }
        'MicrosoftThreatProtection'                    { 'Microsoft Defender XDR' }
        'Office365'                                    { 'Microsoft 365 (Office 365)' }
        'AzureSecurityCenter'                          { 'Microsoft Defender for Cloud' }
        'GenericUI'                                    { if ($Connector.properties.connectorUiConfig.title) { $Connector.properties.connectorUiConfig.title } else { $Kind } }
        'StaticUI'                                     { if ($Connector.properties.connectorUiConfig.title) { $Connector.properties.connectorUiConfig.title } else { $Kind } }
        { $_ -in 'RestApiPoller','Push' }              {
            # CCF-derived kinds. Each connector instance carries a
            # connectorDefinitionName that points at the matching CCF
            # definition entry, where the human-readable title lives.
            $defName = $Connector.properties.connectorDefinitionName
            if ($defName -and $CcfTitleByName.ContainsKey($defName)) {
                "$($CcfTitleByName[$defName])  ($Kind)"
            } elseif ($defName) {
                "$defName  ($Kind)"
            } else {
                $Kind
            }
        }
        default                                        { $Kind }
    }
}

function Get-ConnectorAggregateState {
    param([psobject]$Connector)
    # RestApiPoller / Push connectors don't carry a dataTypes map. Treat the
    # presence of a dataType + dcrConfig as 'enabled' for that kind.
    if ($Connector.kind -in @('RestApiPoller','Push')) {
        $hasDataType = $Connector.properties.PSObject.Properties.Name -contains 'dataType' -and $Connector.properties.dataType
        $hasDcr = $Connector.properties.PSObject.Properties.Name -contains 'dcrConfig' -and $Connector.properties.dcrConfig
        if ($hasDataType -and $hasDcr) { return 'enabled' }
        if ($hasDataType -or $hasDcr) { return 'partial' }
        return 'unknown'
    }
    $dataTypes = $Connector.properties.dataTypes
    if ($null -eq $dataTypes) { return 'unknown' }
    $names = @($dataTypes.PSObject.Properties.Name)
    if ($names.Count -eq 0) { return 'unknown' }
    $states = foreach ($n in $names) {
        $s = $dataTypes.$n.state
        if ($s) { $s.ToLowerInvariant() } else { 'unknown' }
    }
    $enabled  = @($states | Where-Object { $_ -eq 'enabled' }).Count
    $disabled = @($states | Where-Object { $_ -eq 'disabled' }).Count
    if ($enabled -eq $states.Count) { 'enabled' }
    elseif ($disabled -eq $states.Count) { 'disabled' }
    elseif ($enabled -gt 0) { 'partial' }
    else { 'unknown' }
}

function Get-ConnectorDataTypes {
    param([psobject]$Connector)
    # RestApiPoller / Push schema: single string at properties.dataType.
    if ($Connector.kind -in @('RestApiPoller','Push')) {
        if ($Connector.properties.PSObject.Properties.Name -contains 'dataType' -and $Connector.properties.dataType) {
            return [string]$Connector.properties.dataType
        }
        return ''
    }
    $dataTypes = $Connector.properties.dataTypes
    if ($null -eq $dataTypes) { return '' }
    @($dataTypes.PSObject.Properties.Name) -join ', '
}

function Get-ConnectorTargetTable {
    # Map (Kind, dataType) -> Log Analytics table the connector writes to.
    # Returns $null when no known mapping exists; the renderer then leaves the
    # activity columns blank for that data type rather than guessing wrong.
    param([string]$Kind, [string]$DataType)
    $dt = if ($DataType) { $DataType.ToLowerInvariant() } else { '' }
    switch ("$Kind/$dt") {
        'Office365/sharepoint'                                   { 'OfficeActivity' }
        'Office365/exchange'                                     { 'OfficeActivity' }
        'Office365/teams'                                        { 'OfficeActivity' }
        'AzureActiveDirectory/signinlogs'                        { 'SigninLogs' }
        'AzureActiveDirectory/auditlogs'                         { 'AuditLogs' }
        'AzureActiveDirectory/noninteractiveusersigninlogs'      { 'AADNonInteractiveUserSignInLogs' }
        'MicrosoftCloudAppSecurity/alerts'                       { 'SecurityAlert' }
        'MicrosoftCloudAppSecurity/discoverylogs'                { 'McasShadowItReporting' }
        'MicrosoftDefenderAdvancedThreatProtection/alerts'       { 'SecurityAlert' }
        'MicrosoftThreatProtection/alerts'                       { 'SecurityAlert' }
        'MicrosoftThreatProtection/incidents'                    { 'SecurityIncident' }
        'MicrosoftThreatIntelligence/microsoftemergingthreatfeed' { 'ThreatIntelligenceIndicator' }
        'MicrosoftPurviewInformationProtection/logs'             { 'InformationProtectionLogs_CL' }
        'AzureSecurityCenter/alerts'                             { 'SecurityAlert' }
        default                                                  { $null }
    }
}

$ccfDefs = Read-RawArray 'data-connector-definitions.json'

# Index CCF definitions by name so RestApiPoller / Push connectors can look up
# their human-readable title via the `connectorDefinitionName` field.
$ccfTitleByName = @{}
foreach ($d in $ccfDefs) {
    if ($d.name -and $d.properties.connectorUiConfig.title) {
        $ccfTitleByName[$d.name] = $d.properties.connectorUiConfig.title
    }
}

# Pre-index tables-with-data by name so the connector rows can join on it
# without rebuilding the lookup once per row.
$tablesByNameForConnectors = @{}
foreach ($t in $tablesWithData) {
    if ($t.DataType) { $tablesByNameForConnectors[$t.DataType] = $t }
}
function Get-ConnectorData7d {
    param([psobject]$Connector)
    # RestApiPoller / Push connectors write to a single table at
    # properties.dataType. The table name itself is the join key — no
    # data-type-to-table mapping is needed.
    if ($Connector.kind -in @('RestApiPoller','Push')) {
        $tbl = $Connector.properties.dataType
        if (-not $tbl) { return '' }
        if ($tablesByNameForConnectors.ContainsKey($tbl)) {
            $row = $tablesByNameForConnectors[$tbl]
            $bill7d = if ($null -ne $row.BillableLast7d) { [double]$row.BillableLast7d } else { 0 }
            if ($bill7d -gt 0) { return 'Yes' }
        }
        return 'No'
    }
    $dataTypes = $Connector.properties.dataTypes
    if ($null -eq $dataTypes) { return '' }
    $anyData = $false
    foreach ($dtName in @($dataTypes.PSObject.Properties.Name)) {
        $table = Get-ConnectorTargetTable -Kind $Connector.kind -DataType $dtName
        if (-not $table) { continue }
        if ($tablesByNameForConnectors.ContainsKey($table)) {
            $row = $tablesByNameForConnectors[$table]
            $bill7d = if ($null -ne $row.BillableLast7d) { [double]$row.BillableLast7d } else { 0 }
            if ($bill7d -gt 0) { $anyData = $true; break }
        }
    }
    if ($anyData) { 'Yes' } else { 'No' }
}

$connectorRows = $connectors | ForEach-Object {
    [pscustomobject]@{
        Title     = Get-ConnectorFriendlyTitle -Kind $_.kind -Connector $_ -CcfTitleByName $ccfTitleByName
        Kind      = $_.kind
        DataTypes = Get-ConnectorDataTypes -Connector $_
        State     = Get-ConnectorAggregateState -Connector $_
        Data7d    = Get-ConnectorData7d -Connector $_
    }
}

$ccfRows = $ccfDefs | ForEach-Object {
    [pscustomobject]@{
        Name      = $_.name
        Title     = $_.properties.connectorUiConfig.title
        Publisher = $_.properties.connectorUiConfig.publisher
    }
}

# Build a per-connector / per-data-type activity table by joining each
# connector's data types to the corresponding workspace table via
# Get-ConnectorTargetTable, then looking up the table's last-ingested
# timestamp and 24h billable volume from tables-with-data.json. Rows where
# we can't map a data type to a known table are still listed (operators
# can recognise the mapping gap) with blank activity columns.
$tablesByName = @{}
foreach ($t in $tablesWithData) {
    if ($t.DataType) { $tablesByName[$t.DataType] = $t }
}

$healthRows = foreach ($c in $connectors) {
    $kind = $c.kind
    $title = Get-ConnectorFriendlyTitle -Kind $kind -Connector $c
    $dataTypes = $c.properties.dataTypes
    if ($null -eq $dataTypes) { continue }
    foreach ($dtName in @($dataTypes.PSObject.Properties.Name)) {
        $table = Get-ConnectorTargetTable -Kind $kind -DataType $dtName
        $lastIngested = ''
        $last24h = ''
        if ($table -and $tablesByName.ContainsKey($table)) {
            $row = $tablesByName[$table]
            if ($row.LastIngested) { $lastIngested = [string]$row.LastIngested }
            if ($null -ne $row.BillableLast24h) { $last24h = [string]$row.BillableLast24h }
        }
        [pscustomobject]@{
            Connector    = $title
            DataType     = $dtName
            Table        = if ($table) { $table } else { '_(no mapping)_' }
            LastIngested = $lastIngested
            BillableLast24hGB = $last24h
        }
    }
}

# Build the synthesised effective-connectors view. Covers DCR-driven and
# diagnostic-settings-driven ingestion which the Sentinel data-connectors
# endpoint doesn't enumerate. See Get-EffectiveConnectors for the precedence
# rules.
$diagSettings = Read-RawArray 'diagnostic-settings.json'
$effective = Get-EffectiveConnectors `
    -ClassicConnectors  $connectors `
    -CcfDefinitions     $ccfDefs `
    -Dcrs               $dcrs `
    -DiagnosticSettings $diagSettings `
    -TablesWithData     $tablesWithData

$connectorBody = @"
$(Format-Banner -Title "Data Connectors")

## Classic connectors

$(Format-Table -Items $connectorRows -Columns 'Title','Kind','DataTypes','State','Data7d')

## Codeless Connector Framework definitions

$(Format-Table -Items $ccfRows -Columns 'Name','Title','Publisher')

## Effective connectors (synthesised view)

Modern Sentinel workspaces ingest most of their data through DCRs and diagnostic settings that don't register against the Sentinel ``dataConnectors`` endpoint. This table fuses every ingestion source the captured inventory can attribute, with precedence rules to avoid double-counting:

1. **Classic** — a classic data-connector explicitly covers the target table.
2. **CCF** — a Codeless Connector Framework definition. Listed by name; table claim depends on connector implementation.
3. **DCR** — derived from each data flow's ``outputStream`` (Microsoft-/Custom- prefixes stripped). Skipped when the table is already classic-claimed.
4. **Diagnostic** — derived from enabled diagnostic-setting log categories. Skipped when already claimed.
5. **Active-table** — a remaining table receiving billable data (>0 GB in the last 24h) that no captured ingestion mechanism explains. Surfaces as a visibility signal.

See ``Docs/Operations/Sentinel-Documenter.md`` for the design note.

$(Format-Table -Items $effective -Columns 'Source','Identifier','Table','Last24hGB','LastIngested')

## Connector health (24h activity)

Last ingested and 24-hour billable volume per **classic** data-connector's data type, joined against the workspace ``Usage`` summary. Rows with a blank Table column have no known data-type-to-table mapping in the renderer; cross-reference [83-data-collection.md](83-data-collection.md) for DCRs and [81-table-plans-retention.md](81-table-plans-retention.md) for the full per-table view.

$(Format-Table -Items $healthRows -Columns 'Connector','DataType','Table','LastIngested','BillableLast24hGB')

[Connector reference (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/data-connectors-reference) · [Connector health monitoring](https://learn.microsoft.com/azure/sentinel/monitor-data-connectors-health)
"@

Write-Section '10-data-connectors.md' $connectorBody

# ---------------------------------------------------------------------------
# Section: 20-analytics-rules
# ---------------------------------------------------------------------------
$ruleRows = $rules | ForEach-Object {
    [pscustomobject]@{
        Kind     = $_.kind
        Name     = $_.properties.displayName
        Severity = $_.properties.severity
        Enabled  = if ($_.properties.enabled) { 'Yes' } else { 'No' }
        Tactics  = ($_.properties.tactics -join ', ')
    }
}

# Per-kind / per-state aggregate counts. Microsoft-managed kinds (Fusion etc)
# are excluded from the Scheduled/NRT counts because they aren't user-editable.
$schedEnabled  = @($rules | Where-Object { $_.kind -eq 'Scheduled' -and $_.properties.enabled }).Count
$schedDisabled = @($rules | Where-Object { $_.kind -eq 'Scheduled' -and -not $_.properties.enabled }).Count
$nrtEnabled    = @($rules | Where-Object { $_.kind -eq 'NRT' -and $_.properties.enabled }).Count
$nrtDisabled   = @($rules | Where-Object { $_.kind -eq 'NRT' -and -not $_.properties.enabled }).Count

# Mouldy rules — Scheduled / NRT rules enabled but last-modified > 1 year ago.
$yearAgo = (Get-Date).ToUniversalTime().AddYears(-1)
$mouldyRows = $rules | Where-Object {
    $_.kind -in @('Scheduled','NRT') -and
    $_.properties.enabled -and
    $_.properties.lastModifiedUtc -and
    ([datetime]$_.properties.lastModifiedUtc) -lt $yearAgo
} | ForEach-Object {
    [pscustomobject]@{
        Name         = $_.properties.displayName
        Kind         = $_.kind
        Severity     = $_.properties.severity
        LastModified = ([datetime]$_.properties.lastModifiedUtc).ToString('yyyy-MM-dd')
    }
}

# MS Incident Creation rules — these aren't user-editable detection rules
# in the usual sense; they translate first-party security alerts into
# Sentinel incidents based on per-product filter criteria. Surface those
# filter fields explicitly since they don't fit the standard row schema.
$msIncidentRows = $rules | Where-Object { $_.kind -eq 'MicrosoftSecurityIncidentCreation' } | ForEach-Object {
    [pscustomobject]@{
        Name              = $_.properties.displayName
        Product           = $_.properties.productFilter
        Severities        = (@($_.properties.severitiesFilter) -join ', ')
        Includes          = (@($_.properties.displayNamesFilter) -join '; ')
        Excludes          = (@($_.properties.displayNamesExcludeFilter) -join '; ')
        Enabled           = if ($_.properties.enabled) { 'Yes' } else { 'No' }
    }
}

# Template mismatch — rules whose templateVersion does not match the latest
# template version. Look up the template by alertRuleTemplateName in the
# captured alert-rule-templates.json.
$alertRuleTemplates = Read-RawArray 'alert-rule-templates.json'
$templateByName = @{}
foreach ($t in $alertRuleTemplates) {
    if ($t.name) { $templateByName[$t.name] = $t }
}
$mismatchRows = $rules | Where-Object {
    $_.properties.alertRuleTemplateName -and
    $_.properties.templateVersion -and
    $templateByName.ContainsKey($_.properties.alertRuleTemplateName) -and
    $templateByName[$_.properties.alertRuleTemplateName].properties.version -and
    $templateByName[$_.properties.alertRuleTemplateName].properties.version -ne $_.properties.templateVersion
} | ForEach-Object {
    $tplName = $_.properties.alertRuleTemplateName
    [pscustomobject]@{
        Name           = $_.properties.displayName
        Kind           = $_.kind
        CurrentVersion = $_.properties.templateVersion
        LatestVersion  = $templateByName[$tplName].properties.version
    }
}

$rulesBody = @"
$(Format-Banner -Title "Analytics Rules")

| Total | Enabled | Disabled | Scheduled-Enabled | Scheduled-Disabled | NRT-Enabled | NRT-Disabled |
|---:|---:|---:|---:|---:|---:|---:|
| $($rules.Count) | $($enabledRules.Count) | $($rules.Count - $enabledRules.Count) | $schedEnabled | $schedDisabled | $nrtEnabled | $nrtDisabled |

## All rules

$(Format-Table -Items $ruleRows -Columns 'Kind','Name','Severity','Enabled','Tactics')

## Mouldy rules — enabled but last modified over a year ago

Rules in this table are still firing but haven't been reviewed in over twelve months. Stale thresholds, deprecated KQL operators, and dropped data sources are all common causes. Each row is a candidate for explicit re-review or retirement.

$(Format-Table -Items $mouldyRows -Columns 'Name','Kind','Severity','LastModified')

## Template mismatch — rules behind their latest template version

Rules where the deployed ``templateVersion`` is older than the version available in the Content Hub catalogue. Update via the rule's "Update from template" action in the portal, or re-deploy from the matching repo YAML.

$(Format-Table -Items $mismatchRows -Columns 'Name','Kind','CurrentVersion','LatestVersion')

## MS Incident Creation rules

These translate first-party security alerts (Defender for Cloud Apps, Defender XDR, etc.) into Sentinel incidents based on per-product filter criteria. They aren't editable as KQL rules; the ``Product`` column is the source product, and ``Includes`` / ``Excludes`` are the alert-name filters.

$(Format-Table -Items $msIncidentRows -Columns 'Name','Product','Severities','Includes','Excludes','Enabled')

[Built-in detections (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/detect-threats-built-in) · [Detect threats from template](https://learn.microsoft.com/azure/sentinel/detect-threats-from-template)
"@

Write-Section '20-analytics-rules.md' $rulesBody

# ---------------------------------------------------------------------------
# Section: 25-mitre-coverage
# ---------------------------------------------------------------------------
$mitreFile = Join-Path $ResourcesRoot 'mitre-attack-v18.json'
$tactics = @()
if (Test-Path $mitreFile) {
    $tactics = (Get-Content $mitreFile -Raw | ConvertFrom-Json).tactics
}

$tacticCounts = @{}
foreach ($t in $tactics) { $tacticCounts[$t.shortName] = 0 }
foreach ($r in $enabledRules) {
    # Some rule kinds (e.g. MicrosoftSecurityIncidentCreation) omit the
    # tactics property entirely; @($null) iterates once with $t = $null
    # which would throw on ContainsKey. Filter nulls.
    foreach ($t in @($r.properties.tactics | Where-Object { $_ })) {
        if ($tacticCounts.ContainsKey($t)) { $tacticCounts[$t]++ }
    }
}

$mitreRows = foreach ($t in $tactics) {
    $count = $tacticCounts[$t.shortName]
    [pscustomobject]@{
        ID = $t.id
        Tactic = $t.name
        EnabledRules = $count
        Coverage = if ($count -eq 0) { '🔴 None' } elseif ($count -lt 3) { '🟠 Thin' } else { '🟢 Covered' }
    }
}

# Build the full hierarchy: tactic → base technique → subtechniques → rules.
# Sentinel rules carry both 'tactics' (TA0xxx shortNames) and 'techniques'
# (raw IDs like T1078 or T1078.001). We don't need a separate technique
# catalogue — the IDs themselves are the canonical MITRE references and
# every cell links back to attack.mitre.org for the human-readable name.
$mitreHierarchy = @{}
foreach ($r in $enabledRules) {
    # Filter out $null entries — many rule kinds (Fusion, MicrosoftSecurityIncidentCreation
    # etc.) carry no `techniques` array at all, which arrives as $null and would
    # poison the dictionary key lookup.
    $rTactics    = @($r.properties.tactics    | Where-Object { $_ })
    $rTechniques = @($r.properties.techniques | Where-Object { $_ })
    $ruleName    = $r.properties.displayName
    foreach ($tac in $rTactics) {
        if (-not $mitreHierarchy.ContainsKey($tac)) { $mitreHierarchy[$tac] = @{} }
        foreach ($tech in $rTechniques) {
            $isSub = ($tech -match '^T\d+\.\d+$')
            $base  = if ($isSub) { ($tech -split '\.')[0] } else { $tech }
            if (-not $base) { continue }
            if (-not $mitreHierarchy[$tac].ContainsKey($base)) {
                $mitreHierarchy[$tac][$base] = @{
                    Subs  = New-Object System.Collections.Generic.SortedSet[string]
                    Rules = New-Object System.Collections.Generic.SortedSet[string]
                }
            }
            if ($isSub) { [void]$mitreHierarchy[$tac][$base].Subs.Add($tech) }
            [void]$mitreHierarchy[$tac][$base].Rules.Add($ruleName)
        }
    }
}

# Build the headline tactic matrix from the same data.
$mitreRowsRich = foreach ($t in $tactics) {
    $key = $t.shortName
    $tacticBucket = if ($mitreHierarchy.ContainsKey($key)) { $mitreHierarchy[$key] } else { @{} }
    $techCount = $tacticBucket.Count
    $subCount  = ($tacticBucket.Values | ForEach-Object { $_.Subs.Count } | Measure-Object -Sum).Sum
    if (-not $subCount) { $subCount = 0 }
    $ruleCount = $tacticCounts[$key]
    $coverage = if ($ruleCount -eq 0) { '🔴 None' } elseif ($ruleCount -lt 3) { '🟠 Thin' } else { '🟢 Covered' }
    [pscustomobject]@{
        ID = $t.id
        Tactic = $t.name
        EnabledRules = $ruleCount
        Techniques = $techCount
        SubTechniques = $subCount
        Coverage = $coverage
    }
}

# Render hierarchical breakdown after the matrix.
$detailSections = New-Object System.Text.StringBuilder
foreach ($t in $tactics) {
    $key = $t.shortName
    [void]$detailSections.AppendLine("")
    [void]$detailSections.AppendLine("### $($t.id) · $($t.name)")
    [void]$detailSections.AppendLine("")
    if (-not $mitreHierarchy.ContainsKey($key) -or $mitreHierarchy[$key].Count -eq 0) {
        [void]$detailSections.AppendLine("_No enabled rules cover this tactic._  [View tactic on MITRE](https://attack.mitre.org/tactics/$($t.id)/)")
        continue
    }
    $techRows = foreach ($techId in ($mitreHierarchy[$key].Keys | Sort-Object)) {
        $bucket = $mitreHierarchy[$key][$techId]
        $subs = if ($bucket.Subs.Count -gt 0) {
            (($bucket.Subs | Sort-Object) | ForEach-Object { "[$_](https://attack.mitre.org/techniques/$($_.Replace('.','/')))" }) -join ', '
        } else { '_(base only)_' }
        [pscustomobject]@{
            Technique     = "[$techId](https://attack.mitre.org/techniques/$techId/)"
            SubTechniques = $subs
            Rules         = $bucket.Rules.Count
            SampleRules   = (($bucket.Rules | Sort-Object) | Select-Object -First 3) -join '; '
        }
    }
    [void]$detailSections.AppendLine((Format-Table -Items $techRows -Columns 'Technique','SubTechniques','Rules','SampleRules'))
}

$mitreBody = @"
$(Format-Banner -Title "MITRE ATT&CK Coverage")

Coverage is derived from the ``tactics`` and ``techniques`` arrays on every **enabled** Sentinel detection rule. Rules that carry sub-technique IDs (e.g. ``T1078.001``) contribute to both the parent technique and the sub-technique counts. Every ID in the breakdown below links to its canonical entry on attack.mitre.org.

## Tactic matrix

$(Format-Table -Items $mitreRowsRich -Columns 'ID','Tactic','EnabledRules','Techniques','SubTechniques','Coverage')

## Technique and sub-technique breakdown
$($detailSections.ToString())
[MITRE coverage in Sentinel (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/mitre-coverage) · [ATT&CK Enterprise (mitre.org)](https://attack.mitre.org/matrices/enterprise/)
"@

Write-Section '25-mitre-coverage.md' $mitreBody

# ---------------------------------------------------------------------------
# Section: 30 / 35 — hunting & parsers
# ---------------------------------------------------------------------------
$hunting = Read-RawArray 'hunting-queries.json'
$parsers = Read-RawArray 'parsers-functions.json'

$huntingRows = $hunting | ForEach-Object {
    [pscustomobject]@{
        Name = $_.properties.displayName
        Tags = ($_.properties.tags | ForEach-Object { "$($_.name)=$($_.value)" }) -join ', '
    }
}
Write-Section '30-hunting-queries.md' (@"
$(Format-Banner -Title "Hunting Queries")

$(Format-Table -Items $huntingRows -Columns 'Name','Tags')
"@)

$parserRows = $parsers | ForEach-Object {
    [pscustomobject]@{
        Name = $_.properties.displayName
        Alias = $_.properties.functionAlias
        Category = $_.properties.category
    }
}
Write-Section '35-parsers-functions.md' (@"
$(Format-Banner -Title "Parsers and Functions")

$(Format-Table -Items $parserRows -Columns 'Name','Alias','Category')
"@)

# ---------------------------------------------------------------------------
# Section: 40 / 50 / 60 / 70
# ---------------------------------------------------------------------------
$workbookTemplates = Read-RawArray 'workbook-templates.json'
$wbRows = $workbooksSaved | ForEach-Object {
    [pscustomobject]@{ Name = $_.properties.displayName; Category = $_.properties.category }
}
Write-Section '40-workbooks.md' (@"
$(Format-Banner -Title "Workbooks")

## Saved workbooks

$(Format-Table -Items $wbRows -Columns 'Name','Category')

## Templates available (Content Hub)

Total available: $($workbookTemplates.Count)
"@)

$wlRows = $watchlists | ForEach-Object {
    [pscustomobject]@{
        Name = $_.properties.displayName
        Source = $_.properties.source
        ItemsSearchKey = $_.properties.itemsSearchKey
    }
}
Write-Section '50-watchlists.md' (@"
$(Format-Banner -Title "Watchlists")

$(Format-Table -Items $wlRows -Columns 'Name','Source','ItemsSearchKey')

> Watchlist item contents are exported under ``_raw/watchlist-items/`` (gitignored). Item bodies are not embedded in the rendered report.
"@)

$arRows = $autoRules | ForEach-Object {
    [pscustomobject]@{ Name = $_.properties.displayName; Order = $_.properties.order; Enabled = if ($_.properties.triggeringLogic.isEnabled) { 'Yes' } else { 'No' } }
}
$playbooks = Read-RawArray 'playbooks.json'
$miAssignments = Read-RawArray 'rbac-playbook-mi.json'
# Note on schema: the Microsoft.Logic/workflows ?api-version=2016-06-01 list
# response returns PascalCase properties at the top level (Name, State,
# Version, ProvisioningState, Definition, etc.) — NOT the nested
# `{ properties: { state, ... } }` shape the docs imply. Defensive lookups
# below try both paths so the renderer works against the live API response
# AND against fixtures shaped to the documented schema.
$pbRows = $playbooks | ForEach-Object {
    $pbName = if ($_.PSObject.Properties.Name -contains 'Name') { $_.Name } else { $_.name }
    $pbState = if ($_.PSObject.Properties.Name -contains 'State') { $_.State }
               elseif ($_.PSObject.Properties.Name -contains 'properties' -and $_.properties) { $_.properties.state }
               else { '' }
    # Closure-scoping note: `Where-Object { $_.Playbook -eq $_.Name }` is
    # ambiguous because $_ inside Where-Object refers to the miAssignment.
    # Capture the outer playbook name first.
    $mi = $miAssignments | Where-Object { $_.Playbook -eq $pbName } | Select-Object -First 1
    $roles = if ($mi -and @($mi.WorkspaceRoles).Count -gt 0) {
        @($mi.WorkspaceRoles) -join ', '
    } elseif ($mi) {
        '_(MI present, no workspace roles)_'
    } else {
        '_(no managed identity)_'
    }
    [pscustomobject]@{
        Name           = $pbName
        State          = $pbState
        WorkspaceRoles = $roles
    }
}
Write-Section '60-automation-rules-playbooks.md' (@"
$(Format-Banner -Title "Automation Rules and Playbooks")

## Automation rules

$(Format-Table -Items $arRows -Columns 'Name','Order','Enabled')

## Playbooks (Logic Apps)

$(Format-Table -Items $pbRows -Columns 'Name','State','WorkspaceRoles')

[Sentinel automation (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/automation/automate-responses-with-playbooks)
"@)

$contentPackages = Read-RawArray 'content-packages.json'
$contentCatalogue = Read-RawArray 'content-product-packages.json'
$repos           = Read-RawArray 'repositories.json'

# Index catalogue versions by contentId so installed packages can join for
# "update available" detection.
$catalogueByContentId = @{}
foreach ($p in $contentCatalogue) {
    $cid = $p.properties.contentId
    if ($cid) { $catalogueByContentId[$cid] = $p }
}

$cpRows = $contentPackages | ForEach-Object {
    $installed = $_.properties.version
    $cid = $_.properties.contentId
    $latest = if ($cid -and $catalogueByContentId.ContainsKey($cid)) { $catalogueByContentId[$cid].properties.version } else { $null }
    $updateAvailable = if ($latest -and $installed -and $latest -ne $installed) { $latest } else { '' }
    [pscustomobject]@{
        Name            = $_.properties.displayName
        Installed       = $installed
        Latest          = if ($latest) { $latest } else { '' }
        UpdateAvailable = $updateAvailable
        Source          = $_.properties.source.kind
    }
}
$repoRows = $repos | ForEach-Object {
    [pscustomobject]@{ Name = $_.properties.displayName; Type = $_.properties.repoType; Url = $_.properties.repository.url }
}
Write-Section '70-content-hub.md' (@"
$(Format-Banner -Title "Content Hub and Repositories")

## Solutions installed

The ``UpdateAvailable`` column is populated only when the installed version is older than the latest available in the Content Hub catalogue.

$(Format-Table -Items $cpRows -Columns 'Name','Installed','Latest','UpdateAvailable','Source')

## Repositories

$(Format-Table -Items $repoRows -Columns 'Name','Type','Url')

[Sentinel solutions (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/sentinel-solutions)
"@)

# ---------------------------------------------------------------------------
# Section: 80 — workspace
# ---------------------------------------------------------------------------
$features = $workspace.properties.features
$wsCreated = $workspace.properties.createdDate
$wsAgeDays = if ($wsCreated) {
    [int]([math]::Floor(((Get-Date).ToUniversalTime() - [datetime]$wsCreated).TotalDays))
} else { $null }
$wsAgeWarning = if ($null -ne $wsAgeDays -and $wsAgeDays -lt 28) {
    " — _Workspace is less than 28 days old; some metrics derived from 7-day and 30-day KQL windows may be incomplete._"
} else { '' }
$wsDefaultDcr = $null
if ($workspace.properties.PSObject.Properties.Name -contains 'defaultDataCollectionRuleResourceId') {
    $wsDefaultDcr = $workspace.properties.defaultDataCollectionRuleResourceId
}
$wsBody = @"
$(Format-Banner -Title "Workspace Inventory")

## Provenance

| Property | Value |
|---|---|
| Resource ID | ``$($workspace.id)`` |
| Created | $wsCreated |
| Age | $(if ($null -ne $wsAgeDays) { "$wsAgeDays days$wsAgeWarning" } else { '_(unknown)_' }) |
| Default DCR | $(if ($wsDefaultDcr) { "``$wsDefaultDcr``" } else { '_(none set on the workspace)_' }) |

## SKU and pricing

| Property | Value |
|---|---|
| SKU name | ``$($workspace.properties.sku.name)`` |
| Capacity reservation level | $(if ($workspace.properties.sku.capacityReservationLevel) { "$($workspace.properties.sku.capacityReservationLevel) GB/day" } else { '_(n/a)_' }) |
| Default retention | $($workspace.properties.retentionInDays) days |
| Daily cap | $(if ($workspace.properties.workspaceCapping.dailyQuotaGb -eq -1 -or $null -eq $workspace.properties.workspaceCapping.dailyQuotaGb) { 'Unlimited' } else { "$($workspace.properties.workspaceCapping.dailyQuotaGb) GB" }) |

### Available service tiers

$( $availableTiers = Read-RawArray 'available-service-tiers.json'
   $tierRows = $availableTiers | ForEach-Object {
       [pscustomobject]@{
           SkuName            = $_.serviceTier
           CapacityReservation = if ($_.PSObject.Properties.Name -contains 'capacityReservationLevel') { $_.capacityReservationLevel } else { '' }
           Enabled            = $_.enabled
       }
   }
   Format-Table -Items $tierRows -Columns 'SkuName','CapacityReservation','Enabled' )

## Usage telemetry

$( $usage = Read-RawArray 'workspace-usage.json' | Select-Object -First 1
   if ($usage) {
@"
| Window | Total GB | Billable GB |
|---|---:|---:|
| Last 30 days (sum) | $($usage.TotalGB) | $($usage.BillableTotalGB) |
| Last 14 days (peak day) | $($usage.PeakDailyGB) | $($usage.BillablePeakDailyGB) |
| Last 14 days (avg/day) | _(n/a)_ | $($usage.BillableAvgDailyGB) |
"@
   } else { '_No usage telemetry captured._' } )

## Networking + replication

| Property | Value |
|---|---|
| Public ingestion | ``$($workspace.properties.publicNetworkAccessForIngestion)`` |
| Public query | ``$($workspace.properties.publicNetworkAccessForQuery)`` |
| Replication enabled | $(if ($null -eq $workspace.properties.replication -or $null -eq $workspace.properties.replication.enabled) { 'False (not configured)' } else { [string]$workspace.properties.replication.enabled }) |
| Replication location | $(if ($workspace.properties.replication -and $workspace.properties.replication.location) { "``$($workspace.properties.replication.location)``" } else { '_(n/a)_' }) |

## Feature flags

| Flag | Value |
|---|---|
| disableLocalAuth | $(Format-FeatureFlag $features 'disableLocalAuth') |
| enableLogAccessUsingOnlyResourcePermissions | $(Format-FeatureFlag $features 'enableLogAccessUsingOnlyResourcePermissions') |
| enableDataExport | $(Format-FeatureFlag $features 'enableDataExport') |
| immediatePurgeDataOn30Days | $(Format-FeatureFlag $features 'immediatePurgeDataOn30Days') |
| clusterResourceId | $(if ($features -and $features.PSObject.Properties.Name -contains 'clusterResourceId' -and $features.clusterResourceId) { "``$($features.clusterResourceId)`` — see [82-dedicated-cluster.md](82-dedicated-cluster.md)" } else { '_(none)_' }) |

## Resource locks

$( $wsLocks = Read-RawArray 'workspace-locks.json'
   $lockRows = $wsLocks | ForEach-Object {
       [pscustomobject]@{ Name = $_.name; Level = $_.properties.level; Notes = $_.properties.notes }
   }
   Format-Table -Items $lockRows -Columns 'Name','Level','Notes' )

A non-empty list of locks here is a deletion-protection signal. ``CanNotDelete`` blocks resource deletion; ``ReadOnly`` blocks both modification and deletion.

[Workspace design (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/logs/workspace-design) · [Manage access](https://learn.microsoft.com/azure/azure-monitor/logs/manage-access) · [Replication](https://learn.microsoft.com/azure/azure-monitor/logs/workspace-replication) · [Resource locks](https://learn.microsoft.com/azure/azure-resource-manager/management/lock-resources)
"@
Write-Section '80-workspace.md' $wsBody

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
        Name = $name
        Plan = $t.properties.plan
        Interactive = $t.properties.retentionInDays
        Total = $t.properties.totalRetentionInDays
        Archive = $t.properties.archiveRetentionInDays
        Type = $t.properties.schema.tableType
        Gb90d = if ($usage) { [math]::Round([double]$usage.BillableLast90d, 2) } else { 0 }
        Last24h = if ($usage -and [double]$usage.BillableLast24h -gt 0) { '✓' } else { '' }
        LastIngested = if ($usage) { $usage.LastIngested } else { '' }
    }
}

$active  = @($tableRows | Where-Object { $_.Last24h })
$silent  = @($tableRows | Where-Object {
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
        Plan = $_.Name
        Tables = $_.Count
        Gb90d = [math]::Round(($_.Group | Measure-Object Gb90d -Sum).Sum, 2)
    }
}

# Catalogue summary — Microsoft pre-defined tables that never received
# data. Most workspaces carry hundreds of these; surface the count and a
# short head sample rather than dumping every name.
$catalogueOnly = @($workspaceTables | Where-Object {
    ($_.properties.schema.tableType -ne 'CustomLog') -and
    (-not $populatedTableNames.ContainsKey($_.name))
})
$catalogueSample = ($catalogueOnly | Select-Object -First 20 | ForEach-Object { $_.name }) -join ', '

$tablePlansBody = @"
$(Format-Banner -Title "Table Plans, Retention and Activity")

The workspace catalogue carries every Microsoft-defined table schema regardless of whether your tenant has onboarded a source for it — typically several hundred. This section focuses on the **operational** subset: tables that have actually received data in the last 90 days plus all custom (``CustomLog``) tables. The full catalogue counts are at the bottom.

| | |
|---|---:|
| Operational tables shown below | $($tableRows.Count) |
| Catalogue-only Microsoft schemas (never ingested, hidden) | $($catalogueOnly.Count) |
| Total tables in workspace | $($workspaceTables.Count) |

## Summary by plan

$(Format-Table -Items $gbByPlan -Columns 'Plan','Tables','Gb90d')

## Operational tables

$(Format-Table -Items ($tableRows | Sort-Object -Property Gb90d -Descending) -Columns 'Name','Plan','Interactive','Total','Archive','Type','Gb90d','Last24h','LastIngested')

## Active (received data in last 24h)

Total: **$($active.Count)** table(s).

## Silent (had data in 90d, nothing in last 24h)

Total: **$($silent.Count)** table(s) — likely connector breakage.

## Orphan custom tables (no data in 90d)

Total: **$($orphans.Count)** custom ``_CL`` table(s) — delete candidates or never-onboarded sources. Microsoft pre-defined tables without data are catalogue entries, not orphans, and are excluded from this list.

## Catalogue-only Microsoft schemas

$($catalogueOnly.Count) Microsoft pre-defined table schemas never received data in the last 90 days. These are part of every workspace's table catalogue and don't represent a deployment problem; first 20 names: ``$catalogueSample$(if ($catalogueOnly.Count -gt 20) { ', …' })``.

## Tables with non-default retention

Tables where the Interactive or Total retention setting differs from the workspace default ($($workspace.properties.retentionInDays) days) AND that have received billable data in the last 90 days. A workspace with hundreds of rows here is usually leaking budget on long-retention tables that should be on the cheaper Archive plan.

$( $nonDefaultRows = @($tableRows | Where-Object {
        ($_.Interactive -ne $workspace.properties.retentionInDays -or $_.Total -ne $workspace.properties.retentionInDays) -and ($_.Gb90d -gt 0)
    } | Sort-Object -Property Gb90d -Descending)
   Format-Table -Items $nonDefaultRows -Columns 'Name','Plan','Interactive','Total','Archive','Gb90d' )

[Table plans (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/logs/logs-table-plans) · [Retention & archive](https://learn.microsoft.com/azure/azure-monitor/logs/data-retention-archive) · [Manage table tiers in Sentinel](https://learn.microsoft.com/azure/sentinel/manage-table-tiers-retention)
"@
Write-Section '81-table-plans-retention.md' $tablePlansBody

# ---------------------------------------------------------------------------
# Section: 82 — dedicated cluster
# ---------------------------------------------------------------------------
$cluster = Read-Raw 'dedicated-cluster.json'
if ($cluster) {
    $clusterBody = @"
$(Format-Banner -Title "Dedicated Cluster")

| Property | Value |
|---|---|
| Name | ``$($cluster.name)`` |
| Capacity reservation | $($cluster.properties.sku.capacity) GB/day |
| Billing type | $($cluster.properties.billingType) |
| Double encryption | $($cluster.properties.isDoubleEncryptionEnabled) |
| Availability zones | $($cluster.properties.isAvailabilityZonesEnabled) |
| CMK key vault | ``$($cluster.properties.keyVaultProperties.keyVaultUri)`` |
| Identity type | $($cluster.identity.type) |
| Associated workspaces | $(($cluster.properties.associatedWorkspaces | Measure-Object).Count) |

[Dedicated clusters (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/logs/logs-dedicated-clusters) · [Customer-managed keys](https://learn.microsoft.com/azure/azure-monitor/logs/customer-managed-keys)
"@
    Write-Section '82-dedicated-cluster.md' $clusterBody
} else {
    Write-Section '82-dedicated-cluster.md' (@"
$(Format-Banner -Title "Dedicated Cluster")

_No dedicated cluster linked to this workspace._

For workspaces sustaining > 500 GB/day, [a dedicated cluster](https://learn.microsoft.com/azure/azure-monitor/logs/logs-dedicated-clusters) unlocks cluster-level commitment pricing, customer-managed keys and availability-zone redundancy.
"@)
}

# ---------------------------------------------------------------------------
# Section: 83 — data collection
# ---------------------------------------------------------------------------
$dces = Read-RawArray 'dces.json'
$dcrRows = $dcrs | ForEach-Object {
    $streams = ($_.properties.dataFlows | ForEach-Object { $_.streams } | Sort-Object -Unique) -join ', '
    [pscustomobject]@{
        Name = $_.name
        Kind = $_.kind
        Streams = $streams
        HasTransform = if (($_.properties.dataFlows.transformKql) -ne $null) { '✓' } else { '' }
    }
}
$dceRows = $dces | ForEach-Object {
    [pscustomobject]@{ Name = $_.name; Location = $_.location }
}
$dcBody = @"
$(Format-Banner -Title "Data Collection Rules and Endpoints")

## DCRs

$(Format-Table -Items $dcrRows -Columns 'Name','Kind','Streams','HasTransform')

## DCEs

$(Format-Table -Items $dceRows -Columns 'Name','Location')

[Data collection rules (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview) · [Transformations](https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-transformations)
"@
Write-Section '83-data-collection.md' $dcBody

# ---------------------------------------------------------------------------
# Section: 84 — cost estimate
# ---------------------------------------------------------------------------
$costBody = if (-not $cost) { @"
$(Format-Banner -Title "Estimated Monthly Cost")

_Cost estimate not available. Confirm Export-SentinelInventory.ps1 ran with retail-prices fetch and tables-with-data KQL._
"@ } else {
$planRows = $cost.ByPlan.PSObject.Properties | ForEach-Object {
    [pscustomobject]@{ Plan = $_.Name; Gb30d = [math]::Round($_.Value.Gb30d, 2); MonthlyCost = $_.Value.MonthlyCost }
}
@"
$(Format-Banner -Title "Estimated Monthly Cost")

> **Headline** **$($cost.MonthlyTotal) $($cost.Currency)** for the workspace, based on the last 30 days of `Usage` × Azure Retail Prices for ``$($cost.Region)`` as of ``$($cost.AsOfUtc)``.

## By plan

$(Format-Table -Items $planRows -Columns 'Plan','Gb30d','MonthlyCost')

## Top tables by cost

$(Format-Table -Items $cost.Top10TablesByCost -Columns 'Table','Plan','Gb30d','MonthlyCost')

## Commitment-tier what-if

$(if ($cost.CommitmentTierWhatIf.Count -gt 0) {
    Format-Table -Items $cost.CommitmentTierWhatIf -Columns 'Rung','ProjectedMonthlyCost','DeltaVsCurrent'
} else { '_Workspace not on PerGB2018, or daily ingest below the lowest commitment rung — no projection produced._' })

## Methodology (v$($cost.MethodologyVersion))

1. Source of truth for ingestion: `Usage` table over the last 30 days, `IsBillable` honoured.
2. Plan attribution: each table's current `plan` decides which meter applies (Analytics / Basic / Auxiliary / DataLake).
3. Unit price: fetched from the [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices) for ``$($cost.Region)`` at run-time.
4. Sentinel free benefit: tables in `Private/Resources/sentinel-benefit-tables.json` have their ingestion price reduced/zeroed when the benefit applies.
5. Commitment-tier projection: illustrative — actual discounts depend on published rates.
6. Dedicated cluster break-even: candidate flag set when daily ingest > 500 GB and no cluster exists.

## Caveats — explicitly NOT priced

$($cost.Caveats | ForEach-Object { "- $_" }) -join "`n")

[Sentinel billing (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/billing) · [Reduce costs](https://learn.microsoft.com/azure/sentinel/billing-reduce-costs) · [Cost logs](https://learn.microsoft.com/azure/azure-monitor/logs/cost-logs)
"@
}
Write-Section '84-cost-estimate.md' $costBody

# ---------------------------------------------------------------------------
# Section: 85 — RBAC
# ---------------------------------------------------------------------------
$rbacWs = Read-RawArray 'rbac-workspace.json'
$rbacRg = Read-RawArray 'rbac-resourcegroup.json'

$wsRows = $rbacWs | ForEach-Object {
    [pscustomobject]@{ Principal = $_.DisplayName; Type = $_.ObjectType; Role = $_.RoleDefinitionName }
}
$rgRows = $rbacRg | ForEach-Object {
    [pscustomobject]@{ Principal = $_.DisplayName; Type = $_.ObjectType; Role = $_.RoleDefinitionName }
}

Write-Section '85-rbac.md' (@"
$(Format-Banner -Title "RBAC")

## At workspace scope

$(Format-Table -Items $wsRows -Columns 'Principal','Type','Role')

## At resource group scope

$(Format-Table -Items $rgRows -Columns 'Principal','Type','Role')

[Sentinel roles (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/roles)
"@)

# ---------------------------------------------------------------------------
# Section: 86 — subscription context
# ---------------------------------------------------------------------------
$sub        = Read-Raw 'subscription.json'
$rps        = Read-RawArray 'resource-providers.json'
$locks      = Read-RawArray 'subscription-locks.json'
$policies   = Read-RawArray 'policy-assignments.json'

$rpRows = $rps | ForEach-Object { [pscustomobject]@{ Provider = $_.ProviderNamespace; State = $_.RegistrationState } }
$lockRows = $locks | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Level = $_.Properties.level; Notes = $_.Properties.notes } }
$polRows = $policies | ForEach-Object {
    # Az.Resources policy-assignment shape varies between versions; surface
    # whichever displayName/scope tier is present.
    $name = $null; $scope = $null
    if ($_.Properties) {
        $name  = $_.Properties.DisplayName
        $scope = $_.Properties.Scope
    }
    if (-not $name)  { $name  = $_.DisplayName }
    if (-not $name)  { $name  = $_.Name }
    if (-not $scope) { $scope = $_.Scope }
    [pscustomobject]@{ Name = $name; Scope = $scope }
}

Write-Section '86-subscription-context.md' (@"
$(Format-Banner -Title "Subscription and Tenant Context")

## Subscription

| | |
|---|---|
| Name | $($sub.Name) |
| ID   | ``$($sub.Id)`` |
| Tenant ID | ``$($sub.TenantId)`` |
| State | $($sub.State) |

## Resource providers

$(Format-Table -Items $rpRows -Columns 'Provider','State')

## Locks

$(Format-Table -Items $lockRows -Columns 'Name','Level','Notes')

## Sentinel-relevant policy assignments

$(Format-Table -Items $polRows -Columns 'Name','Scope')

[Resource providers (Microsoft Learn)](https://learn.microsoft.com/azure/azure-resource-manager/management/resource-providers-and-types)
"@)

# ---------------------------------------------------------------------------
# Section: 90 — gap analysis
# ---------------------------------------------------------------------------
$gapRows = $gapFindings | ForEach-Object {
    [pscustomobject]@{
        ID = $_.Id
        Severity = Format-Severity-Badge $_.Severity
        Category = $_.Category
        Title = $_.Title
        Evidence = $_.Evidence
        Learn = "[$($_.Learn)]($($_.Learn))"
    }
}
Write-Section '90-gap-analysis.md' (@"
$(Format-Banner -Title "Gap Analysis")

The gap engine compares the live workspace against the rule set in [Private/Resources/best-practices.json](../../Scripts/Documenter/Private/Resources/best-practices.json). Each row is a Test-* function in [Private/GapChecks.ps1](../../Scripts/Documenter/Private/GapChecks.ps1) — adding a new rule is a two-line change.

## Findings

$(if ($gapRows.Count -gt 0) { Format-Table -Items $gapRows -Columns 'ID','Severity','Category','Title','Evidence','Learn' } else { '_No findings — clean run._' })

## Remediation detail

$(if ($gapFindings.Count -gt 0) {
    ($gapFindings | ForEach-Object { @"
### [$($_.Id)] $($_.Title)
- **Severity:** $($_.Severity)
- **Category:** $($_.Category)
- **Evidence:** $($_.Evidence)
- **Remediation:** $($_.Remediation)
- **Learn:** $($_.Learn)
"@ }) -join [Environment]::NewLine
} else { '' })
"@)

# ---------------------------------------------------------------------------
# New sections aligned to the formal Sentinel Configuration TOC
# (TOC numbering shown alongside each MD filename).
# ---------------------------------------------------------------------------

# Section 01 — Executive Summary  (TOC 1)
# Synthesised from headline counts + cost + top gap findings + MITRE coverage.
$gapBySeverity = @{ Critical = 0; Warning = 0; Info = 0 }
foreach ($f in $gapFindings) {
    if ($gapBySeverity.ContainsKey($f.Severity)) { $gapBySeverity[$f.Severity]++ }
}
$tacticsCovered = ($enabledRules | ForEach-Object { $_.properties.tactics } | Where-Object { $_ } | Sort-Object -Unique).Count
$tacticsTotal = if ($tactics) { $tactics.Count } else { 14 }

$execBody = @"
$(Format-Banner -Title "Executive Summary")

> A high-level snapshot of the Microsoft Sentinel deployment for ``$WorkspaceName``. This page is auto-generated from the live workspace; the architectural narrative (3.1) and SOC operational processes (3.3) are customer-supplied and live elsewhere in the formal report.

## Key indicators

| Indicator | Value |
|---|---:|
| Workspace SKU | ``$($workspace.properties.sku.name)`` |
| Default retention | $($workspace.properties.retentionInDays) days |
| Daily cap | $(if ($workspace.properties.workspaceCapping.dailyQuotaGb -eq -1) { 'Unlimited' } else { "$($workspace.properties.workspaceCapping.dailyQuotaGb) GB" }) |
| Estimated monthly cost | $(if ($cost) { "$($cost.MonthlyTotal) $($cost.Currency)" } else { 'n/a' }) |
| Data connectors | $($connectors.Count) |
| Analytics rules (enabled / total) | $($enabledRules.Count) / $($rules.Count) |
| MITRE tactics with coverage | $tacticsCovered / $tacticsTotal |
| Tables receiving data (90d) | $($populatedTables.Count) populated · $($operationalTables.Count) operational · $($workspaceTables.Count) catalogue |
| Findings (Critical / Warning / Info) | $($gapBySeverity.Critical) / $($gapBySeverity.Warning) / $($gapBySeverity.Info) |

## Top recommendations

$(if ($top5Findings.Count -gt 0) {
    ($top5Findings | ForEach-Object {
        "- **$(Format-Severity-Badge $_.Severity)** [$($_.Id)] $($_.Title)`n  $($_.Remediation) [Learn]($($_.Learn))"
    }) -join [Environment]::NewLine
} else { '_No findings — clean run._' })

## Where to read more

| Concern | See |
|---|---|
| Connectors and ingestion | [10-data-connectors.md](10-data-connectors.md), [83-data-collection.md](83-data-collection.md) |
| Detection coverage | [20-analytics-rules.md](20-analytics-rules.md), [25-mitre-coverage.md](25-mitre-coverage.md) |
| Workspace, tables, retention | [80-workspace.md](80-workspace.md), [81-table-plans-retention.md](81-table-plans-retention.md) |
| Cost | [84-cost-estimate.md](84-cost-estimate.md) |
| Operational health | [11-sentinel-health.md](11-sentinel-health.md), [12-soc-optimization.md](12-soc-optimization.md), [15-incidents.md](15-incidents.md) |
| Identity and access | [85-rbac.md](85-rbac.md) |
| Findings vs. best practice | [90-gap-analysis.md](90-gap-analysis.md) |
"@
Write-Section '01-executive-summary.md' $execBody

# Section 11 — Sentinel health (TOC 4.8)
$health = Read-RawArray 'sentinel-health.json'
$healthRows = $health | ForEach-Object {
    [pscustomobject]@{
        Resource = $_.SentinelResourceName
        Kind     = $_.SentinelResourceKind
        Type     = $_.SentinelResourceType
        Events   = $_.Events
        Statuses = ($_.Statuses -join ', ')
        LastEvent= $_.LastEvent
    }
}
$healthSummary = Read-RawArray 'sentinel-health-summary.json'
$healthSummaryRows = $healthSummary | ForEach-Object {
    [pscustomobject]@{ OperationName = $_.OperationName; Status = $_.Status; LogCount = $_.LogCount }
}
$laQueryLogs = Read-RawArray 'la-query-logs.json' | Select-Object -First 1
$laQueryLine = if ($laQueryLogs -and $laQueryLogs.QueryCount) {
    "**LAQueryLogs activity (7d):** $($laQueryLogs.QueryCount) query records (query logging is active)."
} elseif ($laQueryLogs) {
    '_LAQueryLogs table is present but empty for the last 7 days; query logging may be off._'
} else {
    '_LAQueryLogs table is not populated; query logging diagnostics are not configured._'
}
Write-Section '11-sentinel-health.md' (@"
$(Format-Banner -Title "Sentinel Health and Resilience  (TOC 4.8)")

Health events are pulled from the workspace's ``SentinelHealth`` table for the last 7 days, summarised per Sentinel resource. The table is empty on workspaces where Sentinel diagnostics have not been enabled — see [Microsoft Learn: turn on health diagnostics](https://learn.microsoft.com/azure/sentinel/health-audit) to start the data flowing.

$(Format-Table -Items $healthRows -Columns 'Resource','Kind','Type','Events','Statuses','LastEvent')

## Operations summary (per OperationName + Status)

$(Format-Table -Items $healthSummaryRows -Columns 'OperationName','Status','LogCount')

## Query logging activity

$laQueryLine

[Sentinel health, audit, and monitoring (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/health-audit)
"@)

# Section 12 — SOC Optimization Insights (TOC 4.9)
# Schema note: recommendation objects expose properties.recommendationTypeId
# (e.g. "Precision_Coverage", "Precision_DataValue"). AffectedItem comes from
# properties.additionalProperties on a per-kind basis (TableName for DataValue,
# UseCaseName for Coverage). Split into two sub-tables grouped by kind so the
# user-action drivers cluster — Coverage rows drive content-hub installs,
# DataValue rows drive ingestion-tuning.
$socOpt = Read-RawArray 'soc-optimization.json'
function _SocOptRow {
    param($Item, [string]$AffectedField)
    [pscustomobject]@{
        Title        = $Item.properties.title
        AffectedItem = $Item.properties.additionalProperties.$AffectedField
        State        = $Item.properties.state
        Description  = ($Item.properties.description -replace '\s+', ' ' | Select-Object -First 200)
    }
}
$socCovRows = $socOpt | Where-Object { $_.properties.recommendationTypeId -eq 'Precision_Coverage'  } | ForEach-Object { _SocOptRow $_ 'UseCaseName' }
$socDvRows  = $socOpt | Where-Object { $_.properties.recommendationTypeId -eq 'Precision_DataValue' } | ForEach-Object { _SocOptRow $_ 'TableName'   }
$socOther   = $socOpt | Where-Object { $_.properties.recommendationTypeId -notin @('Precision_Coverage','Precision_DataValue') } | ForEach-Object {
    [pscustomobject]@{
        Kind         = $_.properties.recommendationTypeId
        Title        = $_.properties.title
        State        = $_.properties.state
        Description  = ($_.properties.description -replace '\s+', ' ' | Select-Object -First 200)
    }
}
Write-Section '12-soc-optimization.md' (@"
$(Format-Banner -Title "SOC Optimization Insights  (TOC 4.9)")

Recommendations from the SOC Optimization service (preview). The endpoint is empty on workspaces where the service has not run, or in regions where it is not yet available. Recommendations are grouped by the kind of action they drive.

> Before tuning based on these recommendations, cross-reference [21-analytics-by-volume.md](21-analytics-by-volume.md) — the highest-volume rules are usually the right place to start, regardless of which row of this section flagged them.

## Coverage recommendations

Drives Content Hub installs and rule activation. AffectedItem is the use-case name (e.g. ``BEC (Financial Fraud)``).

$(Format-Table -Items $socCovRows -Columns 'Title','AffectedItem','State','Description')

## Data Value recommendations

Drives ingestion tuning. AffectedItem is the workspace table name. A high count here is a sign that data is arriving but no detection coverage is matching it.

$(Format-Table -Items $socDvRows -Columns 'Title','AffectedItem','State','Description')

## Other recommendations

$(Format-Table -Items $socOther -Columns 'Kind','Title','State','Description')

[SOC optimization in Microsoft Sentinel (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/soc-optimization/soc-optimization-access)
"@)

# Section 13 — Data source hygiene
$cefDevices = Read-RawArray 'cef-devices.json'
$cefInSyslog = Read-RawArray 'cef-in-syslog.json'
$secEvtDupes = Read-RawArray 'security-event-duplicates.json'
$topEventIds = Read-RawArray 'top-event-ids.json'

$cefDevRows = $cefDevices | ForEach-Object {
    [pscustomobject]@{ DeviceVendor = $_.DeviceVendor; DeviceProduct = $_.DeviceProduct; LogCount = $_.LogCount }
}
$cefSyslogRows = $cefInSyslog | ForEach-Object {
    [pscustomobject]@{ Computer = $_.Computer; LogCount = $_.LogCount }
}
$secEvtDupeRows = $secEvtDupes | ForEach-Object {
    [pscustomobject]@{ Computer = $_.Computer; LogCount = $_.LogCount; DuplicateEventIds = (@($_.DuplicateEventIds) -join ', ') }
}
$topEventIdRows = $topEventIds | ForEach-Object {
    [pscustomobject]@{ TableName = $_.TableName; EventID = $_.EventID; EventDescription = $_.EventDescription; BilledSizeGB = $_.BilledSizeGB }
}

Write-Section '13-data-source-hygiene.md' (@"
$(Format-Banner -Title "Data Source Hygiene")

Operational data-quality findings that drive ingestion-tuning actions: misrouted records, agent dual-collection, and noisy event types. Each table is independent and may show ``_None._`` when the workspace has nothing to report against that check.

## CEF devices (last 7d)

Per-vendor / per-product CEF record counts. A vendor + product combination with very low counts is usually either a misconfigured collector or a forwarder that needs filtering at source.

$(Format-Table -Items $cefDevRows -Columns 'DeviceVendor','DeviceProduct','LogCount')

## CEF records misrouted into Syslog (last 7d)

A non-empty table here means a Linux syslog forwarder is shipping CEF-formatted records to the wrong workspace table. Split the source into a dedicated CommonSecurityLog stream.

$(Format-Table -Items $cefSyslogRows -Columns 'Computer','LogCount')

## SecurityEvent duplicates (last 1h)

Computers reporting duplicate SecurityEvent records within a one-hour window. Almost always an MMA + AMA dual-collection misconfiguration; consolidate the collection path.

$(Format-Table -Items $secEvtDupeRows -Columns 'Computer','LogCount','DuplicateEventIds')

## Top 10 noisy event IDs (last 7d)

Highest-volume Windows event IDs across the Event + SecurityEvent tables, by billed size. Each row is a candidate for filtering at the DCR transform stage.

$(Format-Table -Items $topEventIdRows -Columns 'TableName','EventID','EventDescription','BilledSizeGB')

[Filter Windows Security events via DCR (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/connect-windows-security-events)
"@)

# Section 14 — Coverage breakdowns
$azAct  = Read-RawArray 'azure-activity-coverage.json'
$azDiag = Read-RawArray 'azure-diagnostics-providers.json'
$xdrPres = Read-RawArray 'xdr-table-presence.json'

$azActRows = $azAct | ForEach-Object {
    [pscustomobject]@{ SubscriptionId = $_.SubscriptionId; LogCount = $_.LogCount }
}
$azDiagRows = $azDiag | ForEach-Object {
    [pscustomobject]@{ ResourceProvider = $_.ResourceProvider; LogCount = $_.LogCount }
}
$xdrRows = $xdrPres | ForEach-Object {
    [pscustomobject]@{ Table = $_.Type; RecordCount = $_.RecordCount }
}
Write-Section '14-coverage-breakdowns.md' (@"
$(Format-Banner -Title "Coverage Breakdowns")

Per-source coverage gaps revealed by direct table queries. A subscription, resource provider, or XDR table missing from these tables is a coverage gap to triage.

## AzureActivity — per-subscription (last 7d)

Each row is a subscription shipping Activity Logs into the workspace. Subscriptions absent from this table are either not connected or have no activity in the period.

$(Format-Table -Items $azActRows -Columns 'SubscriptionId','LogCount')

## AzureDiagnostics — per resource provider (last 7d)

Resource providers emitting diagnostic settings into the workspace. Maps directly to which Azure services have diagnostic settings wired up to this workspace.

$(Format-Table -Items $azDiagRows -Columns 'ResourceProvider','LogCount')

## XDR table presence (last 7d)

Subset of well-known Defender XDR tables that have received data in the last 7 days. Empty rows would suggest XDR is connected but a particular surface (email, identity, device) is not producing data.

$(Format-Table -Items $xdrRows -Columns 'Table','RecordCount')

[Microsoft Sentinel data connector reference (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/data-connectors-reference)
"@)

# Section 15 — Incidents (TOC 4.10)
$incSummary = Read-RawArray 'incidents-summary.json' | Select-Object -First 1
$incMttr    = Read-RawArray 'incidents-mttr.json'    | Select-Object -First 1
$incByRule  = Read-RawArray 'incidents-by-rule.json'
$incDaily   = Read-RawArray 'incidents-daily-metrics.json' | Select-Object -First 1

function Format-MinutesScalar {
    param($Value, $CountAcknowledged)
    # KQL returns the literal string "NaN" when an aggregate had no rows to
    # average over (e.g. avg(int(null)) across zero rows), and Save-Json
    # writes that through verbatim. Treat any non-numeric input as
    # unavailable so the report shows "n/a" instead of the noisy "NaN min".
    if ($null -eq $Value) { return 'n/a' }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s) -or $s -eq 'NaN' -or $s -eq 'null') { return 'n/a' }
    $d = 0.0
    if (-not [double]::TryParse($s, [ref]$d)) { return 'n/a' }
    return ("$([math]::Round($d, 1)) min")
}
$mttrLine = if ($incMttr -and $incMttr.ClosedCount) {
    $ackCount = $null
    if ($incMttr.PSObject.Properties.Name -contains 'AcknowledgedCount') {
        $ackCount = $incMttr.AcknowledgedCount
    }
    $mttaStr  = Format-MinutesScalar -Value $incMttr.MTTAMinutes -CountAcknowledged $ackCount
    $mttrStr  = Format-MinutesScalar -Value $incMttr.MTTRMinutes -CountAcknowledged $incMttr.ClosedCount
    $ackSuffix = if ($null -ne $ackCount) {
        "  ·  **Acknowledged:** $ackCount of $($incMttr.ClosedCount)"
    } else { '' }
    "**MTTA:** $mttaStr  ·  **MTTR:** $mttrStr  ·  **Closed:** $($incMttr.ClosedCount) (last 30d)$ackSuffix"
} else { '_No closed incidents in the last 30 days; MTTA/MTTR not available._' }

$dailyLine = if ($incDaily -and $null -ne $incDaily.AvgDailyUniqueIncidents) {
    "**Avg daily unique incidents:** $($incDaily.AvgDailyUniqueIncidents)  ·  **Peak daily new incidents:** $($incDaily.PeakDailyNewIncidents) (last 7d)"
} else { '_No incident-flow metrics available._' }

$incidentBody = @"
$(Format-Banner -Title "Incidents  (TOC 4.10)")

> Aggregate-only. The documenter never exports incident bodies, alert payloads or entity detail — only counts and derived SOC-efficiency metrics.

$mttrLine

$dailyLine

> When triaging a high MTTR, cross-reference [21-analytics-by-volume.md](21-analytics-by-volume.md) for the rules driving raw alert load — high alert volume from a single rule usually inflates time-to-acknowledge for everything else in the queue.

## Top alerting rules (last 30d, top 25)

$(Format-Table -Items ($incByRule | ForEach-Object { [pscustomobject]@{ Rule = $_.Title; Incidents = $_.Incidents } }) -Columns 'Rule','Incidents')

## Incident detail by provider / product / first rule (last 7d)

Per-provider, per-product, per-first-rule alert counts joined to the incidents they belong to. The FirstRule ID resolves to its full name via the [20-analytics-rules.md](20-analytics-rules.md) table.

$(Format-Table -Items (Read-RawArray 'incidents-detail-by-provider.json' | ForEach-Object { [pscustomobject]@{ Provider = $_.ProviderName; Product = $_.ProductName; FirstRule = $_.FirstRule; AlertCount = $_.AlertCount } }) -Columns 'Provider','Product','FirstRule','AlertCount')

[Sentinel incidents (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/investigate-cases)
"@
Write-Section '15-incidents.md' $incidentBody

# Section 21 — Rules by alert volume (TOC 4.11.2)
$ruleVolumes = Read-RawArray 'analytics-rule-volumes.json'
Write-Section '21-analytics-by-volume.md' (@"
$(Format-Banner -Title "Analytics Rules — by Alert Volume  (TOC 4.11.2)")

The 50 most-firing rules over the last 30 days, derived from ``SecurityAlert``. A rule firing thousands of alerts a day is usually either a misconfiguration (too-low threshold) or a high-fidelity signal — review and tune.

$(Format-Table -Items ($ruleVolumes | ForEach-Object { [pscustomobject]@{ Rule = $_.AlertName; Product = $_.ProductName; Severity = $_.Severity; Alerts = $_.Alerts } }) -Columns 'Rule','Product','Severity','Alerts')
"@)

# Section 22 — Microsoft security rules (TOC 4.11.3)
$msRules = @($rules | Where-Object {
    $kind = $_.kind
    $tn = $_.properties.alertRuleTemplateName
    ($tn -and ($tn -match '^[a-f0-9-]{36}$')) -or ($kind -in @('Fusion','MicrosoftSecurityIncidentCreation','MLBehaviorAnalytics','ThreatIntelligence'))
})
Write-Section '22-analytics-microsoft-rules.md' (@"
$(Format-Banner -Title "Microsoft Security Rules  (TOC 4.11.3)")

Rules backed by a Microsoft template, or built-in Microsoft-managed kinds (Fusion, MicrosoftSecurityIncidentCreation, MLBehaviorAnalytics, ThreatIntelligence). These are not user-editable; tuning is via enable/disable and the per-rule incident-grouping config.

$(Format-Table -Items ($msRules | ForEach-Object { [pscustomobject]@{ Kind = $_.kind; Name = $_.properties.displayName; Severity = $_.properties.severity; Enabled = if ($_.properties.enabled) {'Yes'} else {'No'} } }) -Columns 'Kind','Name','Severity','Enabled')
"@)

# Section 23 — Modifications (TOC 4.11.4)
$modifiedRows = $rules | ForEach-Object {
    $lm = $null
    if ($_.properties -and ($_.properties.PSObject.Properties.Name -contains 'lastModifiedUtc')) { $lm = $_.properties.lastModifiedUtc }
    [pscustomobject]@{
        Name = $_.properties.displayName
        Kind = $_.kind
        LastModified = $lm
        Enabled = if ($_.properties.enabled) {'Yes'} else {'No'}
    }
} | Where-Object { $_.LastModified } | Sort-Object -Property LastModified -Descending | Select-Object -First 50
Write-Section '23-analytics-modifications.md' (@"
$(Format-Banner -Title "Analytics Rules — Recent Modifications  (TOC 4.11.4)")

The 50 most recently modified rules. Cross-reference with [Test-SentinelRuleDrift.ps1](../../Scripts/Test-SentinelRuleDrift.ps1) — a recent modification on a rule that has a Content Hub template or repo YAML source-of-truth indicates portal drift.

$(Format-Table -Items $modifiedRows -Columns 'Name','Kind','LastModified','Enabled')
"@)

# Section 24 — By Content Solution (TOC 4.11.5)
$metadataAll = Read-RawArray 'metadata.json'
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
Write-Section '24-analytics-by-solution.md' (@"
$(Format-Banner -Title "Analytics Rules — by Content Solution  (TOC 4.11.5)")

Rules grouped by the Content Hub solution that ships them, derived from the metadata link table. '(custom or unmapped)' covers rules that have no metadata association — typically repo-deployed custom rules.

$(Format-Table -Items $bySolution -Columns 'Solution','Rule','Enabled','Severity')
"@)

# Section 26 — UEBA (TOC 4.16)
# Two signals are surfaced:
# 1. Configuration: presence of the /settings/Ueba resource. Absence does NOT
#    imply UEBA is disabled — the portal toggle writes nothing here.
# 2. Data presence: row counts in BehaviorAnalytics, IdentityInfo,
#    UserPeerAnalytics over 12d, from `_raw/ueba-data-presence.json`. Any
#    non-zero count is the authoritative "UEBA is producing data" signal.
$settingsRaw = Read-Raw 'settings.json'
$uebaSetting = if ($null -ne $settingsRaw) { $settingsRaw.Ueba } else { $null }
$uebaSources = if ($uebaSetting -and $uebaSetting.properties) { @($uebaSetting.properties.dataSources) } else { @() }
$uebaConfigLabel = if ($uebaSetting) {
    'Yes (settings resource present)'
} else {
    'Settings resource not written — UEBA may still be enabled via the portal toggle; the configuration API has not been used to set explicit data sources on this workspace'
}
$uebaPresence = Read-RawArray 'ueba-data-presence.json'
$uebaPresenceRows = $uebaPresence | ForEach-Object {
    [pscustomobject]@{ Table = $_.TableName; Rows12d = $_.Count }
}
$uebaTotalRows = ($uebaPresenceRows | Measure-Object -Property Rows12d -Sum).Sum
$uebaActiveLabel = if ($uebaTotalRows -and $uebaTotalRows -gt 0) {
    "Yes — $uebaTotalRows rows across $(@($uebaPresenceRows | Where-Object { $_.Rows12d -gt 0 }).Count) UEBA table(s) over the last 12 days"
} elseif ($uebaPresence.Count -eq 0) {
    '_(data-presence capture not available — re-run the exporter to refresh)_'
} else {
    'No — none of BehaviorAnalytics, IdentityInfo, UserPeerAnalytics received rows in the last 12 days'
}
$uebaPresenceBlock = if ($uebaPresenceRows.Count -gt 0) {
    @"

## Data-presence inference (last 12 days)

$(Format-Table -Items $uebaPresenceRows -Columns 'Table','Rows12d')
"@
} else { '' }
Write-Section '26-ueba.md' (@"
$(Format-Banner -Title "User and Entity Behaviour Analytics  (TOC 4.16)")

UEBA enriches incidents with anomaly scores and entity-level timelines. It is enabled at the workspace level via the ``Microsoft.SecurityInsights/settings/Ueba`` resource. The configuration row reflects whether the settings resource has been written; the data-presence row reflects whether UEBA is actually producing rows.

| | |
|---|---|
| Configuration | $uebaConfigLabel |
| Data sources (configured) | $(if ($uebaSources.Count -gt 0) { ($uebaSources -join ', ') } else { '_(none configured via the settings resource)_' }) |
| Producing data | $uebaActiveLabel |
$uebaPresenceBlock
[Enable UEBA in Microsoft Sentinel (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/enable-entity-behavior-analytics)
"@)

# Section 27 — Threat Intelligence (TOC 4.17)
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
$tiMetrics = Read-RawArray 'threat-intel-metrics.json'
$tiCounts  = Read-RawArray 'threat-intel-counts.json'
$tiSourceRows = @()
$tiTypeRows   = @()
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
    $tiTypeRows   = @($tiTypeRows)   | Sort-Object -Property IndicatorCount -Descending
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
    "**Total active indicators:** $tiTotal  ·  **Distinct breakdown rows:** $(@($tiRows).Count)  ·  **Data source:** $tiSourceLabel"
} else {
    "_No threat intelligence indicators surfaced via either capture path._"
}
# Threat-type breakdown only renders when the metrics API path actually
# returned a populated array — under the KQL fallback there is no
# equivalent breakdown so the section is suppressed entirely.
$tiTypeBlock = if ($tiTypeRows.Count -gt 0 -and ($tiTypeRows | Measure-Object -Property IndicatorCount -Sum).Sum -gt 0) {
    @"

## Indicator breakdown by threat type

$(Format-Table -Items $tiTypeRows -Columns 'ThreatType','IndicatorCount')
"@
} else { '' }
Write-Section '27-threat-intelligence.md' (@"
$(Format-Banner -Title "Threat Intelligence  (TOC 4.17)")

Indicator counts and most-recent ingestion timestamp by source, last 30 days. Indicator detail is intentionally NOT exported to keep the report aggregate-only.

$tiHeadline

$(Format-Table -Items $tiRows -Columns 'SourceSystem','IndicatorCount','LastIngested')
$tiTypeBlock
[Microsoft Sentinel Threat Intelligence (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/understand-threat-intelligence)
"@)

# Section 36 — Data export (TOC 4.3.3)
$dataExports = Read-RawArray 'data-exports.json'
$exportRows = $dataExports | ForEach-Object {
    [pscustomobject]@{
        Name        = $_.name
        Destination = $_.properties.destination.resourceId
        Tables      = ($_.properties.tableNames -join ', ')
        Enabled     = $_.properties.enable
    }
}
Write-Section '36-data-export.md' (@"
$(Format-Banner -Title "Data Export  (TOC 4.3.3)")

Continuous export of selected tables to Storage Accounts or Event Hubs. Empty list = no data export configured.

$(Format-Table -Items $exportRows -Columns 'Name','Destination','Tables','Enabled')

[Log Analytics data export (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/logs/logs-data-export)
"@)

# Section 37 — Search and restore (TOC 4.3.4)
# Search jobs and restore-logs aren't always pulled per-table; surface what
# we have at workspace scope.
$searchJobs = Read-RawArray 'search-jobs.json'
$restoreJobs = Read-RawArray 'restore-logs.json'
Write-Section '37-search-restore.md' (@"
$(Format-Banner -Title "Search and Restore Tables  (TOC 4.3.4)")

Search jobs and Long-Term-Restore operations rehydrate data from archive into queryable tables. The table below shows in-flight or recently completed jobs.

## Search jobs

$(Format-Table -Items $searchJobs -Columns 'name','properties')

## Restore logs

$(Format-Table -Items $restoreJobs -Columns 'name','properties')

[Search jobs in Azure Monitor Logs](https://learn.microsoft.com/azure/azure-monitor/logs/search-jobs) · [Restore logs](https://learn.microsoft.com/azure/azure-monitor/logs/restore)
"@)

# Section 38 — Summary rules (TOC 4.3.5)
# Schema note: the capture comes from `.../workspaces/<ws>/summaryLogs` (under
# the OperationalInsights provider, not Sentinel). Each item exposes
# `properties.ruleType`, `properties.RuleDefinition.Query`,
# `properties.RuleDefinition.BinSize`, `properties.RuleDefinition.BinDelay`,
# `properties.RuleDefinition.TimeSelector`, and
# `properties.RuleDefinition.DestinationTable`. The earlier renderer read
# `properties.displayName` / `properties.source.name` / `properties.version`
# — fields that belong to the contentTemplates schema, not summaryLogs.
$summaryRules = Read-RawArray 'summary-rules.json'
$summaryRows = $summaryRules | ForEach-Object {
    [pscustomobject]@{
        Name             = $_.name
        RuleType         = $_.properties.ruleType
        DestinationTable = $_.properties.RuleDefinition.DestinationTable
        BinSize          = $_.properties.RuleDefinition.BinSize
        BinDelay         = $_.properties.RuleDefinition.BinDelay
    }
}
Write-Section '38-summary-rules.md' (@"
$(Format-Banner -Title "Summary Rules  (TOC 4.3.5)")

Summary rules pre-aggregate high-volume tables on a schedule into a derived table. They cut query cost on noisy data.

$(Format-Table -Items $summaryRows -Columns 'Name','RuleType','DestinationTable','BinSize','BinDelay')

[Summary rules (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/summary-rules)
"@)

# Section 87 — Azure Monitor Agents (TOC 4.5)
$amaAgents = Read-RawArray 'ama-agents.json'
$agentRows = $amaAgents | ForEach-Object {
    [pscustomobject]@{
        Computer  = $_.Computer
        OS        = $_.OS
        Version   = $_.Version
        Resource  = $_.Resource
        LastSeen  = $_.LastHeartbeat
    }
}

# AMA vs MMA migration status by machine type.
$migration = Read-RawArray 'ama-mma-migration.json'
$migrationRows = $migration | ForEach-Object {
    [pscustomobject]@{
        MachineType     = $_.MachineType
        MachineCount    = $_.MachineCount
        MMACount        = $_.MMACount
        AMACount        = $_.AMACount
        MigrationStatus = $_.MigrationStatus
    }
}
Write-Section '87-azure-monitor-agents.md' (@"
$(Format-Banner -Title "Azure Monitor Agents  (TOC 4.5)")

Agents heartbeating into the workspace over the last 7 days, derived from the ``Heartbeat`` table. Each row is a distinct ``SourceComputerId``.

$(Format-Table -Items $agentRows -Columns 'Computer','OS','Version','Resource','LastSeen')

## AMA vs MMA migration status

Per-machine-type breakdown of agent migration progress. ``Direct Agent`` counts the legacy MMA; ``Azure Monitor Agent`` counts the modern AMA. Migration state is **Completed** when only AMA records exist for a category, **In Progress** when both exist, and **Not Started** otherwise.

$(Format-Table -Items $migrationRows -Columns 'MachineType','MachineCount','MMACount','AMACount','MigrationStatus')

[Migrate from Log Analytics agent to Azure Monitor agent (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-migration)
[Azure Monitor Agent overview (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/agents/agents-overview)
"@)

# Section 96 — User-facing Microsoft references (TOC 6.x)
Write-Section '96-references-microsoft.md' (@"
$(Format-Banner -Title "Useful Microsoft References")

Curated Microsoft Learn entry points for the topics covered in this report. Distinct from [99-references.md](99-references.md), which catalogues the API versions and modules the documenter itself depends on.

## Microsoft Sentinel

- [Microsoft Sentinel documentation](https://learn.microsoft.com/azure/sentinel/) — landing page
- [Best practices](https://learn.microsoft.com/azure/sentinel/best-practices)
- [Skill-up resources](https://learn.microsoft.com/azure/sentinel/skill-up-resources) — training paths
- [Move to Microsoft Defender XDR](https://learn.microsoft.com/azure/sentinel/move-to-defender) — 2027-03-31 portal retirement

## Connectors

- [Data connectors reference](https://learn.microsoft.com/azure/sentinel/data-connectors-reference)
- [Connector prioritisation guide](https://learn.microsoft.com/azure/sentinel/prioritize-data-connectors)
- [Tables ↔ connectors map](https://learn.microsoft.com/azure/sentinel/sentinel-tables-connectors-reference)
- [Connector health monitoring](https://learn.microsoft.com/azure/sentinel/monitor-data-connectors-health)
- [Codeless Connector Framework authoring](https://learn.microsoft.com/azure/sentinel/create-codeless-connector)

## Troubleshooting

- [Sentinel health, audit, and monitoring](https://learn.microsoft.com/azure/sentinel/health-audit)
- [Workspace replication](https://learn.microsoft.com/azure/azure-monitor/logs/workspace-replication)
- [Logs ingestion troubleshooting](https://learn.microsoft.com/azure/azure-monitor/logs/data-ingestion-time)

## Log Analytics and KQL

- [Log Analytics overview](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview)
- [KQL quick reference](https://learn.microsoft.com/azure/data-explorer/kql-quick-reference)
- [KQL tutorial](https://learn.microsoft.com/azure/azure-monitor/logs/get-started-queries)
- [Table plans (Analytics / Basic / Auxiliary / DataLake)](https://learn.microsoft.com/azure/azure-monitor/logs/logs-table-plans)
- [Retention and archive](https://learn.microsoft.com/azure/azure-monitor/logs/data-retention-archive)
- [Data collection rules](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview)
- [Data export](https://learn.microsoft.com/azure/azure-monitor/logs/logs-data-export)

## Microsoft Sentinel pricing and cost

- [Sentinel billing overview](https://learn.microsoft.com/azure/sentinel/billing)
- [Reduce Sentinel costs](https://learn.microsoft.com/azure/sentinel/billing-reduce-costs)
- [Monitor Sentinel costs](https://learn.microsoft.com/azure/sentinel/billing-monitor-costs)
- [Cost logs](https://learn.microsoft.com/azure/azure-monitor/logs/cost-logs)
- [Daily cap](https://learn.microsoft.com/azure/azure-monitor/logs/daily-cap)
- [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices)

## Logic Apps and playbooks

- [Automate threat response with playbooks](https://learn.microsoft.com/azure/sentinel/automation/automate-responses-with-playbooks)
- [Logic Apps documentation](https://learn.microsoft.com/azure/logic-apps/)

## Azure security context

- [Sentinel roles and permissions](https://learn.microsoft.com/azure/sentinel/roles)
- [Defender XDR](https://learn.microsoft.com/defender-xdr/)
- [Azure Monitor Private Link Scope (AMPLS)](https://learn.microsoft.com/azure/azure-monitor/logs/private-link-security)
- [Customer-managed keys](https://learn.microsoft.com/azure/azure-monitor/logs/customer-managed-keys)
"@)

# ---------------------------------------------------------------------------
# Section: 99 — references
# ---------------------------------------------------------------------------
$refSrc = Join-Path $PSScriptRoot 'REFERENCES.md'
if (Test-Path $refSrc) {
    Copy-Item -Path $refSrc -Destination (Join-Path $OutputRoot '99-references.md') -Force
    Write-Information "  ↳ copied 99-references.md"
}

# ---------------------------------------------------------------------------
# Index
# ---------------------------------------------------------------------------
$indexBody = @"
# $WorkspaceName — Sentinel Documentation Index

Generated $($run.StartedAtUtc) UTC by Sentinel Documenter v$($run.DocumenterVersion).

Sections are numbered to match the formal Sentinel Configuration TOC where applicable. Customer-narrative sections (architectural diagrams, SOC operational processes, the licensing inventory) are intentionally not auto-generated — supply those separately.

| Section | TOC | Description |
|---|---|---|
| [00-overview.md](00-overview.md) | — | Headline counts, top findings, cost summary |
| [01-executive-summary.md](01-executive-summary.md) | 1 | Auto-synthesised executive summary |
| [10-data-connectors.md](10-data-connectors.md) | 4.7 | Classic + CCF connectors |
| [11-sentinel-health.md](11-sentinel-health.md) | 4.8 | SentinelHealth events last 7 days |
| [12-soc-optimization.md](12-soc-optimization.md) | 4.9 | SOC Optimization recommendations |
| [13-data-source-hygiene.md](13-data-source-hygiene.md) | — | CEF/Syslog hygiene, agent dual-collection, top noisy events |
| [14-coverage-breakdowns.md](14-coverage-breakdowns.md) | — | AzureActivity / AzureDiagnostics / XDR coverage by source |
| [15-incidents.md](15-incidents.md) | 4.10 | Incident MTTA/MTTR + top alerting rules |
| [20-analytics-rules.md](20-analytics-rules.md) | 4.11.1 | All detection rules by kind |
| [21-analytics-by-volume.md](21-analytics-by-volume.md) | 4.11.2 | Top 50 rules by alert volume (30d) |
| [22-analytics-microsoft-rules.md](22-analytics-microsoft-rules.md) | 4.11.3 | Microsoft-managed rules |
| [23-analytics-modifications.md](23-analytics-modifications.md) | 4.11.4 | Recently modified rules |
| [24-analytics-by-solution.md](24-analytics-by-solution.md) | 4.11.5 | Rules grouped by Content Hub solution |
| [25-mitre-coverage.md](25-mitre-coverage.md) | 3.2 | Tactic + technique + sub-technique coverage |
| [26-ueba.md](26-ueba.md) | 4.16 | UEBA configuration |
| [27-threat-intelligence.md](27-threat-intelligence.md) | 4.17 | Indicator counts by source |
| [30-hunting-queries.md](30-hunting-queries.md) | 4.15 | Hunting queries |
| [35-parsers-functions.md](35-parsers-functions.md) | — | Parsers and functions |
| [36-data-export.md](36-data-export.md) | 4.3.3 | Data export configuration |
| [37-search-restore.md](37-search-restore.md) | 4.3.4 | Search jobs / restore logs |
| [38-summary-rules.md](38-summary-rules.md) | 4.3.5 | Summary rules |
| [40-workbooks.md](40-workbooks.md) | 4.14 | Saved workbooks + templates |
| [50-watchlists.md](50-watchlists.md) | 4.12 | Watchlists |
| [60-automation-rules-playbooks.md](60-automation-rules-playbooks.md) | 4.13 | Automation rules + playbooks + MI grants |
| [70-content-hub.md](70-content-hub.md) | 4.6 | Solutions installed + repositories |
| [80-workspace.md](80-workspace.md) | 4.2 | SKU, retention, networking, feature flags |
| [81-table-plans-retention.md](81-table-plans-retention.md) | 4.3.1-2 | Per-table plan, retention, activity |
| [82-dedicated-cluster.md](82-dedicated-cluster.md) | 4.2.2 | Dedicated cluster, CMK, AZ |
| [83-data-collection.md](83-data-collection.md) | — | DCRs and DCEs |
| [84-cost-estimate.md](84-cost-estimate.md) | — | Estimated monthly cost |
| [85-rbac.md](85-rbac.md) | 4.4 | Role assignments |
| [86-subscription-context.md](86-subscription-context.md) | 4.1 | Subscription, tenant, RPs, locks, policy |
| [87-azure-monitor-agents.md](87-azure-monitor-agents.md) | 4.5 | AMA agents heartbeating into the workspace |
| [90-gap-analysis.md](90-gap-analysis.md) | — | Findings against MS Learn best practices |
| [96-references-microsoft.md](96-references-microsoft.md) | 6 | User-facing Microsoft references |
| [99-references.md](99-references.md) | — | Documenter's own API versions and modules |
"@
Write-Section 'index.md' $indexBody

Write-Information "✓ Renderer complete — output: $OutputRoot"
