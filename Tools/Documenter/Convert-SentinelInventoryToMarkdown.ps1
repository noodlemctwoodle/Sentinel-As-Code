#
# Sentinel-As-Code/Tools/Documenter/Convert-SentinelInventoryToMarkdown.ps1
#
# Created by noodlemctwoodle on 06/05/2026.
#

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
    Folder containing best-practices.json, mitre-attack.json, etc. Defaults to
    Tools/Documenter/Private/Resources.

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
    # Auto-link finding mentions. Two passes:
    #   1. `[SENT-NNN]` text-in-brackets NOT followed by `(` → wrap with URL.
    #      This catches the bullet-list format already used in 00-overview
    #      and 01-live-snapshot's "Top recommendations" blocks where the
    #      square brackets are literal (Markdown treats `[X]` without a
    #      following `(...)` as plain text).
    #   2. Bare `SENT-NNN` not already inside a Markdown link → wrap.
    # On 90-gap-analysis.md itself the target collapses to just the anchor
    # so internal links work (`[SENT-001](#sent-001)`). Existing links are
    # preserved — the lookarounds skip anything already followed by `](`.
    $relTarget = if ($FileName -eq '90-gap-analysis.md') { '' } else { '90-gap-analysis.md' }

    # Walk the body line-by-line, tracking fenced-code state. Auto-link only
    # outside fences — references inside ```mermaid / ```kusto / etc must
    # render literally (Mermaid `click` directives in 85-rbac use SENT-NNN
    # in their tooltips and break if rewritten).
    $sb = New-Object System.Text.StringBuilder
    $inFence = $false
    foreach ($line in ($body -split "(`r?`n)")) {
        if ($line -match '^\s*```') { $inFence = -not $inFence; [void]$sb.Append($line); continue }
        if ($inFence) { [void]$sb.Append($line); continue }
        # Pass 1: bracketed-but-unlinked IDs.
        $line = [regex]::Replace($line, '\[(SENT-\d{3,})\](?!\()', {
            param($m)
            $id = $m.Groups[1].Value
            "[$id]($relTarget#$($id.ToLower()))"
        })
        # Pass 2: bare IDs not preceded by `[`, `(`, `#`, or `-` and not
        # followed by `]` or `)`. The leading `-` exclusion guards against
        # future composite IDs like `SENT-AUTH-001`.
        $line = [regex]::Replace($line, '(?<![\[\(#\-])\b(SENT-\d{3,})\b(?![\]\)])', {
            param($m)
            $id = $m.Groups[1].Value
            "[$id]($relTarget#$($id.ToLower()))"
        })
        [void]$sb.Append($line)
    }
    $body = $sb.ToString()
    Set-Content -Path $target -Value $body -Encoding UTF8
    Write-Information "  ↳ rendered $FileName"
}

function Format-DateUtc {
    # Renders any datetime-ish input (string ISO, [datetime]) as
    # `yyyy-MM-dd HH:mm` — locale-invariant, seconds dropped to reduce
    # column width. Empty / null / unparseable inputs return ''.
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
        return $parsed.ToUniversalTime().ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $s
}

function Format-Gb {
    # Renders any numeric-ish input as a GB value to 3 decimal places.
    # Values below 0.001 GB render as `<0.001` so a meaningful "non-zero
    # but tiny" signal isn't lost to rounding. Empty / null / non-numeric
    # inputs return ''.
    param($Value)
    if ($null -eq $Value) { return '' }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $d = 0.0
    if (-not [double]::TryParse($s, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $s }
    if ($d -eq 0) { return '0' }
    if ($d -gt 0 -and $d -lt 0.001) { return '<0.001' }
    return $d.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Format-Banner {
    param([string]$Title)
    $run = Read-Raw 'run-context.json'
    $started = if ($run) { Format-DateUtc $run.StartedAtUtc } else { '' }
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

# Rule ↔ watchlist cross-reference. Scans every rule's KQL query for
# `_GetWatchlist("alias")` calls (the canonical helper). The output is
# two hashtables consumed by sections 20 and 50:
#   $rulesByWatchlistAlias   alias  -> @(rule display names)
#   $watchlistsByRuleId      ruleId -> @(aliases)
# Both quote styles and a forgiving whitespace pattern are accepted —
# matches `_GetWatchlist("X")`, `_GetWatchlist('X')`, and `_GetWatchlist
# (  "X"  )` with case-insensitive function-name match.
$rulesByWatchlistAlias = @{}
$watchlistsByRuleId    = @{}
$rxWatchlistRef = [regex]::new("_GetWatchlist\s*\(\s*['""]([^'""]+)['""]\s*\)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
foreach ($r in $rules) {
    $q = $r.properties.query
    if (-not $q) { continue }
    $matches = $rxWatchlistRef.Matches([string]$q)
    if ($matches.Count -eq 0) { continue }
    $ruleName = $r.properties.displayName
    $ruleId   = $r.name
    $aliases  = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in $matches) { [void]$aliases.Add($m.Groups[1].Value) }
    $watchlistsByRuleId[$ruleId] = @($aliases)
    foreach ($a in $aliases) {
        if (-not $rulesByWatchlistAlias.ContainsKey($a)) { $rulesByWatchlistAlias[$a] = New-Object System.Collections.Generic.List[string] }
        [void]$rulesByWatchlistAlias[$a].Add($ruleName)
    }
}

# Severity + category counters hoisted up here (was computed twice further
# down at the gap-analysis and live-snapshot section blocks). Single
# computation drives the Mermaid pie/bar charts in 00, 01 and 90.
$gapBySeverity = @{ Critical = 0; Warning = 0; Info = 0 }
$gapByCategory = @{}
foreach ($f in $gapFindings) {
    if ($gapBySeverity.ContainsKey($f.Severity)) { $gapBySeverity[$f.Severity]++ }
    $cat = if ($f.Category) { [string]$f.Category } else { 'Other' }
    if (-not $gapByCategory.ContainsKey($cat)) { $gapByCategory[$cat] = @{ Warning = 0; Info = 0; Critical = 0 } }
    if ($gapByCategory[$cat].ContainsKey($f.Severity)) { $gapByCategory[$cat][$f.Severity]++ }
}

$overviewBody = @"
$(Format-Banner -Title "Microsoft Sentinel Workspace — Overview")

## Findings at a glance

``````mermaid
pie showData title Open findings by severity
    "Critical" : $($gapBySeverity.Critical)
    "Warning"  : $($gapBySeverity.Warning)
    "Info"     : $($gapBySeverity.Info)
``````

$($gapFindings.Count) open findings against the best-practice catalogue. Drill into [90-gap-analysis.md](90-gap-analysis.md) for the per-category breakdown.

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
"**$($cost.MonthlyTotal) $($cost.Currency)** for the workspace, computed from the last 30 days of `Usage` against the Azure Retail Prices API on $(Format-DateUtc $cost.AsOfUtc). See [84-cost-estimate.md](84-cost-estimate.md) for breakdown and methodology."
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
            if ($row.LastIngested) { $lastIngested = Format-DateUtc $row.LastIngested }
            if ($null -ne $row.BillableLast24h) { $last24h = Format-Gb $row.BillableLast24h }
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
$workspaceResourceId = if ($workspace.id) { [string]$workspace.id } else { '' }
$effective = Get-EffectiveConnectors `
    -ClassicConnectors   $connectors `
    -CcfDefinitions      $ccfDefs `
    -Dcrs                $dcrs `
    -DiagnosticSettings  $diagSettings `
    -TablesWithData      $tablesWithData `
    -WorkspaceResourceId $workspaceResourceId

# Connector-kind distribution for the headline pie. Excludes CCF defs
# (counted separately) since they're not deployed instances per se.
$kindCounts = @{}
foreach ($c in $connectors) {
    $k = if ($c.kind) { [string]$c.kind } else { 'unknown' }
    if (-not $kindCounts.ContainsKey($k)) { $kindCounts[$k] = 0 }
    $kindCounts[$k]++
}
$kindPieRows = $kindCounts.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}

$connectorBody = @"
$(Format-Banner -Title "Data Connectors")

## Connector mix

``````mermaid
pie showData title Connectors by kind
$($kindPieRows -join [Environment]::NewLine)
``````

$($connectors.Count) connector(s) deployed across $($kindCounts.Count) distinct kinds.

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

See ``Docs/Tools/Documenter/Sentinel-Documenter.md`` for the design note.

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

# Rule-kind distribution for the headline.
$ruleKindCounts = @{}
foreach ($r in $rules) {
    $k = if ($r.kind) { [string]$r.kind } else { 'unknown' }
    if (-not $ruleKindCounts.ContainsKey($k)) { $ruleKindCounts[$k] = 0 }
    $ruleKindCounts[$k]++
}
$schedNote = if ($ruleKindCounts.ContainsKey('Scheduled')) { "$($ruleKindCounts['Scheduled']) deployed" } else { 'not deployed' }
$msicNote  = if ($ruleKindCounts.ContainsKey('MicrosoftSecurityIncidentCreation')) { "$($ruleKindCounts['MicrosoftSecurityIncidentCreation']) deployed" } else { 'not deployed' }

# Fusion vs Defender XDR Correlation Engine state. When a workspace is
# onboarded to the Microsoft Defender unified portal (USOP), Microsoft
# automatically disables the Fusion analytic rule and the Defender XDR
# Correlation Engine takes over alert-to-incident correlation. The
# canonical, capture-derivable signal is the combination of:
#   - whether a Fusion rule exists and is enabled, AND
#   - whether the Microsoft Defender XDR connector
#     (kind = MicrosoftThreatProtection) is enabled.
# The four (fusion × defender) cells map to four reader-facing narratives
# below.
$fusionRules    = @($rules | Where-Object { $_.kind -eq 'Fusion' })
$fusionPresent  = $fusionRules.Count -gt 0
$fusionEnabled  = @($fusionRules | Where-Object { $_.properties.enabled }).Count -gt 0

$m365DefenderConnected = $false
foreach ($c in $connectors) {
    if ($c.kind -ne 'MicrosoftThreatProtection') { continue }
    $dts = $c.properties.dataTypes
    if ($dts) {
        foreach ($p in $dts.PSObject.Properties) {
            if ($p.Value.state -eq 'Enabled') { $m365DefenderConnected = $true; break }
        }
    }
    if ($m365DefenderConnected) { break }
}

$correlationState = if ($fusionEnabled -and $m365DefenderConnected) {
    '**Fusion enabled, Defender XDR connector enabled.** If this workspace is onboarded to the Microsoft Defender unified portal (USOP), Microsoft auto-disables Fusion regardless of the displayed state above and the Defender XDR Correlation Engine performs alert-to-incident correlation. Confirm by checking the workspace''s onboarding state in the Defender portal — if onboarded, treat the displayed Fusion state as informational only.'
} elseif ((-not $fusionEnabled) -and $m365DefenderConnected) {
    '**Fusion disabled, Defender XDR connector enabled.** This workspace is using the **Defender XDR Correlation Engine** for alert-to-incident correlation. Microsoft auto-disables the Fusion rule on workspaces onboarded to the Defender unified portal — Defender XDR''s correlation replaces it.'
} elseif ($fusionEnabled -and (-not $m365DefenderConnected)) {
    '**Fusion enabled, no Defender XDR connector.** Fusion is performing multi-source ML-based incident correlation across Sentinel data sources. Onboarding the workspace to the Defender unified portal would auto-disable Fusion and hand correlation to Defender XDR.'
} elseif ($fusionPresent -and -not $fusionEnabled -and -not $m365DefenderConnected) {
    '**Fusion present but disabled, no Defender XDR connector.** No ML-based incident correlation is active on this workspace.'
} else {
    '**No Fusion rule deployed, no Defender XDR connector.** No ML-based incident correlation. Either enable the Fusion rule for multi-source correlation, or onboard to the Defender unified portal to inherit the Defender XDR Correlation Engine.'
}

$rulesBody = @"
$(Format-Banner -Title "Analytics Rules")

## Rule taxonomy

Sentinel's ``alertRules`` API surfaces five kinds of detection logic under a single base. The class diagram documents the polymorphism — useful when later sections refer to "MS Incident Creation rules" because those rules have a completely different shape from Scheduled:

``````mermaid
classDiagram
    class AlertRule {
        +string id
        +string kind
        +string displayName
        +string severity
        +bool enabled
        +datetime lastModifiedUtc
        +string[] tactics
        +string[] techniques
    }

    class Scheduled {
        +string queryFrequency
        +string queryPeriod
        +int triggerThreshold
        +string query
    }

    class NRT {
        +string query
        +bool eventGrouping
    }

    class Fusion {
        +string alertRuleTemplateName
        +string[] sourceSettings
    }

    class MicrosoftSecurityIncidentCreation {
        +string productFilter
        +string[] severitiesFilter
        +string[] displayNamesFilter
        +string[] displayNamesExcludeFilter
    }

    class ThreatIntelligence {
        +string templateVersion
    }

    AlertRule <|-- Scheduled
    AlertRule <|-- NRT
    AlertRule <|-- Fusion
    AlertRule <|-- MicrosoftSecurityIncidentCreation
    AlertRule <|-- ThreatIntelligence

    note for Scheduled "$schedNote on this workspace"
    note for MicrosoftSecurityIncidentCreation "$msicNote (legacy pre-Defender XDR pattern)"
``````

## Incident correlation engine

$correlationState

[Microsoft Sentinel Fusion technology (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/fusion)
[Microsoft Defender XDR correlation in the unified SecOps portal (Microsoft Learn)](https://learn.microsoft.com/defender-xdr/microsoft-365-defender)

## Per-kind / per-state aggregate

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
# Catalogue file (resource-bundled) carries:
#   tactics[]    { id, name, shortname (kebab, STIX), sentinelShortName
#                  (PascalCase, what Sentinel rules return in tactics[]) }
#   techniques[] { id, name, tactics (kebab), tacticsSentinel (PascalCase),
#                  isSubtechnique, parentId, url, platforms, dataSources }
# The renderer joins each rule's `properties.techniques` against the
# catalogue so cells show "T1078 — Valid Accounts" rather than a bare ID.
$mitreFile = Join-Path $ResourcesRoot 'mitre-attack.json'
$tactics = @()
$mitreTechniques = @()
if (Test-Path $mitreFile) {
    $mitreCatalogue = Get-Content $mitreFile -Raw | ConvertFrom-Json
    $tactics = @($mitreCatalogue.tactics)
    $mitreTechniques = @($mitreCatalogue.techniques)
}

# Build a technique-id -> name lookup so every render path resolves names
# consistently. Sub-techniques also get their parent's name prefixed in a
# separate fullName lookup so a row reading "T1078.004 — Cloud Accounts" can
# fall back to "Valid Accounts: Cloud Accounts" when richer context helps.
$techNameById = @{}
$techFullNameById = @{}
foreach ($t in $mitreTechniques) {
    if (-not $t.id) { continue }
    $techNameById[$t.id] = $t.name
    if ($t.PSObject.Properties.Name -contains 'parentId' -and $t.parentId) {
        $parent = $techNameById[$t.parentId]
        if ($parent) { $techFullNameById[$t.id] = "${parent}: $($t.name)" }
    }
}
function Format-MitreTechniqueCell {
    param([string]$Id, [bool]$Sub = $false)
    if (-not $Id) { return '' }
    $name = $techNameById[$Id]
    $urlId = if ($Sub) { $Id.Replace('.', '/') } else { $Id }
    if ($name) {
        return "[$Id — $name](https://attack.mitre.org/techniques/$urlId/)"
    }
    return "[$Id](https://attack.mitre.org/techniques/$urlId/)"
}

$tacticCounts = @{}
foreach ($t in $tactics) { $tacticCounts[$t.sentinelShortName] = 0 }
foreach ($r in $enabledRules) {
    # Some rule kinds (e.g. MicrosoftSecurityIncidentCreation) omit the
    # tactics property entirely; @($null) iterates once with $t = $null
    # which would throw on ContainsKey. Filter nulls.
    foreach ($t in @($r.properties.tactics | Where-Object { $_ })) {
        if ($tacticCounts.ContainsKey($t)) { $tacticCounts[$t]++ }
    }
}

$mitreRows = foreach ($t in $tactics) {
    $count = $tacticCounts[$t.sentinelShortName]
    [pscustomobject]@{
        ID = $t.id
        Tactic = $t.name
        EnabledRules = $count
        Coverage = if ($count -eq 0) { '🔴 None' } elseif ($count -lt 3) { '🟠 Thin' } else { '🟢 Covered' }
    }
}

# Build the full hierarchy: tactic → base technique → subtechniques → rules.
# Sentinel rules carry both 'tactics' (PascalCase shortnames matching the
# tactic.sentinelShortName field) and 'techniques' (raw IDs like T1078 or
# T1078.001). The catalogue lookup above resolves IDs to names for display.
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
    $key = $t.sentinelShortName
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
    $key = $t.sentinelShortName
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
            (($bucket.Subs | Sort-Object) | ForEach-Object { Format-MitreTechniqueCell -Id $_ -Sub $true }) -join ', '
        } else { '_(base only)_' }
        [pscustomobject]@{
            Technique     = Format-MitreTechniqueCell -Id $techId -Sub $false
            SubTechniques = $subs
            Rules         = $bucket.Rules.Count
            SampleRules   = (($bucket.Rules | Sort-Object) | Select-Object -First 3) -join '; '
        }
    }
    [void]$detailSections.AppendLine((Format-Table -Items $techRows -Columns 'Technique','SubTechniques','Rules','SampleRules'))
}

# Build the bar-chart inputs from $mitreRowsRich (already sorted by tactic).
# Short labels per tactic so x-axis fits 14 entries; full names live in the
# matrix table below.
$labelMap = @{
    'Reconnaissance' = 'Recon'; 'ResourceDevelopment' = 'ResDev'; 'InitialAccess' = 'Initial'
    'Execution' = 'Exec'; 'Persistence' = 'Persist'; 'PrivilegeEscalation' = 'PrivEsc'
    'DefenseEvasion' = 'DefEva'; 'CredentialAccess' = 'CredAcc'; 'Discovery' = 'Discov'
    'LateralMovement' = 'LatMov'; 'Collection' = 'Collect'; 'CommandAndControl' = 'C2'
    'Exfiltration' = 'Exfil'; 'Impact' = 'Impact'
}
$mitreAxis = ($tactics | ForEach-Object {
    $key = $_.sentinelShortName
    $lbl = if ($labelMap.ContainsKey($key)) { $labelMap[$key] } else { $key.Substring(0, [math]::Min(7, $key.Length)) }
    "`"$lbl`""
}) -join ', '
$mitreBars = ($mitreRowsRich | ForEach-Object { $_.EnabledRules }) -join ', '
$mitreMax = 1
foreach ($r in $mitreRowsRich) { if ($r.EnabledRules -gt $mitreMax) { $mitreMax = $r.EnabledRules } }
$mitreYmax = [int]([math]::Ceiling(($mitreMax + 1) / 10.0)) * 10

$mitreBody = @"
$(Format-Banner -Title "MITRE ATT&CK Coverage")

Coverage is derived from the ``tactics`` and ``techniques`` arrays on every **enabled** Sentinel detection rule. Rules that carry sub-technique IDs (e.g. ``T1078.001``) contribute to both the parent technique and the sub-technique counts. Every ID in the breakdown below links to its canonical entry on attack.mitre.org.

## Coverage shape — rules per tactic

``````mermaid
---
config:
  xyChart:
    width: 1400
    height: 480
---
xychart-beta
    title "Enabled rules per MITRE tactic"
    x-axis [$mitreAxis]
    y-axis "Enabled rules" 0 --> $mitreYmax
    bar [$mitreBars]
``````

**$tacticsCoveredFull 🟢 Covered · $tacticsThin 🟠 Thin · $tacticsNone 🔴 None** of $tacticsTotal tactics. Thin or uncovered tactics surface above any chart bar shorter than the threshold.

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
# Aggregate hunting queries by tactic (parsed from the tactics= tag value).
$huntByTactic = @{}
foreach ($h in $hunting) {
    $tactics = @($h.properties.tags | Where-Object { $_.name -eq 'tactics' } | ForEach-Object { $_.value })
    if (-not $tactics) { $tactics = @('Untagged') }
    foreach ($t in $tactics) {
        # tactics tag can be a comma-separated list
        foreach ($tac in ($t -split ',')) {
            $key = $tac.Trim()
            if (-not $key) { continue }
            if (-not $huntByTactic.ContainsKey($key)) { $huntByTactic[$key] = 0 }
            $huntByTactic[$key]++
        }
    }
}
$huntPieRows = $huntByTactic.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8 | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}
$huntChartBlock = if ($hunting.Count -gt 0 -and $huntPieRows.Count -gt 0) {
    @"

## Hunting queries by tactic

``````mermaid
pie showData title Hunting queries by MITRE tactic
$($huntPieRows -join [Environment]::NewLine)
``````

$($hunting.Count) hunting query(ies). Tactic distribution reveals where the SOC's free-form investigation library is strongest and where the gaps live.
"@
} else { '' }

Write-Section '30-hunting-queries.md' (@"
$(Format-Banner -Title "Hunting Queries")
$huntChartBlock

$(Format-Table -Items $huntingRows -Columns 'Name','Tags')
"@)

$parserRows = $parsers | ForEach-Object {
    [pscustomobject]@{
        Name = $_.properties.displayName
        Alias = $_.properties.functionAlias
        Category = $_.properties.category
    }
}

# Pie of parsers/functions by category.
$parserByCat = @{}
foreach ($p in $parserRows) {
    $c = if ($p.Category) { [string]$p.Category } else { 'Uncategorised' }
    if (-not $parserByCat.ContainsKey($c)) { $parserByCat[$c] = 0 }
    $parserByCat[$c]++
}
$parserPieRows = $parserByCat.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8 | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}
$parserChartBlock = if ($parserRows.Count -gt 0 -and $parserPieRows.Count -gt 0) {
    @"

## Parsers by category

``````mermaid
pie showData title Parsers and functions by category
$($parserPieRows -join [Environment]::NewLine)
``````

$($parserRows.Count) parser(s) / function(s). Each entry is a `let`-style KQL definition reusable across rules and hunting queries.
"@
} else { '' }

Write-Section '35-parsers-functions.md' (@"
$(Format-Banner -Title "Parsers and Functions")
$parserChartBlock

$(Format-Table -Items $parserRows -Columns 'Name','Alias','Category')
"@)

# ---------------------------------------------------------------------------
# Section: 40 / 50 / 60 / 70
# ---------------------------------------------------------------------------
$workbookTemplates = Read-RawArray 'workbook-templates.json'
$wbRows = $workbooksSaved | ForEach-Object {
    [pscustomobject]@{ Name = $_.properties.displayName; Category = $_.properties.category }
}
$wbUnsaved = [math]::Max(0, $workbookTemplates.Count - $workbooksSaved.Count)
Write-Section '40-workbooks.md' (@"
$(Format-Banner -Title "Workbooks")

## Adoption

``````mermaid
pie showData title Workbook coverage
    "Saved (deployed)" : $($workbooksSaved.Count)
    "Available templates not deployed" : $wbUnsaved
``````

$($workbooksSaved.Count) of $($workbookTemplates.Count) available templates deployed in this workspace. The "templates not deployed" gap is where new visibility opportunities live.

## Saved workbooks

$(Format-Table -Items $wbRows -Columns 'Name','Category')

## Templates available (Content Hub)

Total available: $($workbookTemplates.Count)
"@)

$wlRows = $watchlists | ForEach-Object {
    $alias = $_.properties.watchlistAlias
    $desc  = if ($_.properties.description) { [string]$_.properties.description } else { '' }
    if ($desc.Length -gt 90) { $desc = $desc.Substring(0, 87) + '...' }
    $usedBy = if ($alias -and $rulesByWatchlistAlias.ContainsKey($alias)) { $rulesByWatchlistAlias[$alias].Count } else { 0 }
    [pscustomobject]@{
        Name           = $_.properties.displayName
        Provider       = if ($_.properties.provider) { [string]$_.properties.provider } else { '' }
        UsedByRules    = $usedBy
        ItemsSearchKey = $_.properties.itemsSearchKey
        Source         = $_.properties.source
        Updated        = Format-DateUtc $_.properties.updated
        Description    = $desc
    }
}

# Detailed rule-by-watchlist mapping rendered as a separate subsection.
# Orphan watchlists (zero rule references) are surfaced explicitly —
# they may still be used by hunting queries, workbooks, or analyst
# KQL, but the absence of any analytics-rule reference is a useful
# signal that the watchlist might be stale.
$wlUsageRows = New-Object System.Collections.Generic.List[object]
foreach ($wl in $watchlists) {
    $alias = $wl.properties.watchlistAlias
    if (-not $alias) { continue }
    $ruleNames = if ($rulesByWatchlistAlias.ContainsKey($alias)) { @($rulesByWatchlistAlias[$alias]) } else { @() }
    $wlUsageRows.Add([pscustomobject]@{
        Alias     = $alias
        RuleCount = $ruleNames.Count
        Rules     = if ($ruleNames.Count -gt 0) { ($ruleNames | Sort-Object -Unique) -join '; ' } else { '_(no analytics rule references)_' }
    })
}

# Watchlist aliases referenced by rules but NOT present in the captured
# watchlist set. These are 'broken' references — the rule queries will
# fail at runtime. Surfaced as a separate subsection only when present.
$wlAliasSet = @{}
foreach ($wl in $watchlists) {
    $a = $wl.properties.watchlistAlias
    if ($a) { $wlAliasSet[$a] = $true }
}
$brokenWatchlistRefs = New-Object System.Collections.Generic.List[object]
foreach ($alias in $rulesByWatchlistAlias.Keys) {
    if (-not $wlAliasSet.ContainsKey($alias)) {
        $brokenWatchlistRefs.Add([pscustomobject]@{
            MissingAlias = $alias
            RuleCount    = $rulesByWatchlistAlias[$alias].Count
            Rules        = ($rulesByWatchlistAlias[$alias] | Sort-Object -Unique) -join '; '
        })
    }
}

# Watchlists by provider for the headline pie (was "by source", but the
# source field is just the seed filename so all rows have a different
# value — useless as a pie distribution). Provider groups by who
# manages the watchlist (Microsoft vs first-party customer content).
$wlByProvider = @{}
foreach ($w in $wlRows) {
    $p = if ($w.Provider) { [string]$w.Provider } else { 'Unknown' }
    if (-not $wlByProvider.ContainsKey($p)) { $wlByProvider[$p] = 0 }
    $wlByProvider[$p]++
}
$wlPieRows = $wlByProvider.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}

# Pie only when 2+ provider buckets — single-slice pies are uninformative.
$wlChartBlock = if ($wlRows.Count -gt 0 -and $wlByProvider.Count -ge 2) {
    @"

## Watchlists by provider

``````mermaid
pie showData title Watchlists by provider
$($wlPieRows -join [Environment]::NewLine)
``````

"@
} else { '' }

$brokenRefsBlock = if ($brokenWatchlistRefs.Count -gt 0) { @"

## Broken watchlist references

Analytics rule(s) reference watchlist aliases that don't exist in this workspace. These rule queries will fail at runtime — investigate whether the watchlist was deleted or the alias is mistyped.

$(Format-Table -Items $brokenWatchlistRefs -Columns 'MissingAlias','RuleCount','Rules')
"@ } else { '' }

Write-Section '50-watchlists.md' (@"
$(Format-Banner -Title "Watchlists")
$wlChartBlock
**$($wlRows.Count) watchlist(s)** on this workspace. A watchlist is a CSV-backed reference table queryable via the ``_GetWatchlist()`` KQL function — use them for static lookups (asset inventories, allow-lists, geofences) that shouldn't change every alert run. Item bodies are not captured by the documenter; the source-of-truth for watchlist contents is the IaC repository (``Watchlists/*.csv``).

$(Format-Table -Items $wlRows -Columns 'Name','Provider','UsedByRules','ItemsSearchKey','Source','Updated','Description')

## Used by analytics rules

Cross-reference of every captured watchlist against every Scheduled / NRT analytics rule's KQL ``query`` field. Each row lists the rules that call ``_GetWatchlist("<alias>")`` against this watchlist. A "_(no analytics rule references)_" row doesn't necessarily mean the watchlist is orphaned — hunting queries, workbooks, and ad-hoc KQL aren't scanned — but no rule reference is a useful signal that the watchlist may be stale.

$(Format-Table -Items $wlUsageRows -Columns 'Alias','RuleCount','Rules')
$brokenRefsBlock

[Microsoft Sentinel watchlists overview (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/watchlists)
[``_GetWatchlist`` function reference (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/watchlists-queries)
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
$autoCount = $arRows.Count
$pbCount   = $pbRows.Count
Write-Section '60-automation-rules-playbooks.md' (@"
$(Format-Banner -Title "Automation Rules and Playbooks")

**$autoCount automation rule(s) · $pbCount playbook(s)** on this workspace.

## Alert-to-response chain — target shape

The sequence below documents the handoff path an automation-enriched response chain follows. A workspace with zero automation rules has a sparse version of this — gaps in the diagram map directly to the gap-engine findings: missing steps 6-8 = [SENT-034], missing step 9's MI role = [SENT-011], missing step 11's analyst ack = [SENT-030].

``````mermaid
sequenceDiagram
    autonumber
    participant DS as Data source
    participant DCR as DCR / Logs Ingest
    participant Tbl as Workspace table
    participant Rule as Analytics rule
    participant Inc as Incident
    participant Auto as Automation rule
    participant PB as Playbook
    participant Teams as MS Teams
    participant SOC as SOC analyst

    DS->>DCR: Event
    DCR->>Tbl: Ingest (after transform)
    Note over Tbl: ~5 min ingestion latency
    Rule->>Tbl: KQL query on schedule
    Rule-->>Inc: Create incident
    Inc->>Auto: Trigger: incident created
    Auto->>Inc: Assign owner, tag tactic, set Active
    Auto->>PB: Run playbook
    PB->>Inc: Add enrichment comment
    PB->>Teams: Post to SOC channel
    Teams-->>SOC: Notification
    SOC->>Inc: Acknowledge + investigate
``````

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
# Content-source distribution for the headline pie.
$sourceCounts = @{}
foreach ($p in $cpRows) {
    $s = if ($p.Source) { [string]$p.Source } else { 'Custom / unknown' }
    if (-not $sourceCounts.ContainsKey($s)) { $sourceCounts[$s] = 0 }
    $sourceCounts[$s]++
}
$sourcePieRows = $sourceCounts.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}

Write-Section '70-content-hub.md' (@"
$(Format-Banner -Title "Content Hub and Repositories")

## Source mix

``````mermaid
pie showData title Installed Content Hub packages by source
$($sourcePieRows -join [Environment]::NewLine)
``````

$($cpRows.Count) package(s) installed across $($sourceCounts.Count) source kind(s).

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
# Timeline-line dates. wsCreatedShort = yyyy-MM-dd for the workspace
# creation event in the timeline diagram. Format-DateUtc returns
# "yyyy-MM-dd HH:mm" — the timeline expects just date so we split on space.
$wsCreatedShort = if ($wsCreated) { (Format-DateUtc $wsCreated).Split(' ')[0] } else { 'unknown' }
$todayShort = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)

# Build the workspace + platform history timeline as a sorted list.
# Mermaid `timeline` renders entries in source order — without an
# explicit chronological sort the entries appeared in the order they
# were declared in the heredoc, not by date. Each entry is a hashtable
# with Date (yyyy-MM-dd) and Lines (one or more colon-suffixed strings).
# Platform deprecation events pre-dating the workspace's creation are
# filtered out — they're irrelevant historical context for a new
# workspace (e.g. a 2026-created workspace doesn't need an MMA-retired
# bullet from 2024).
$timelineEvents = @()
$timelineEvents += [pscustomobject]@{
    Date  = $wsCreatedShort
    Lines = @(
        "Workspace created ($($workspace.properties.sku.name), $($workspace.properties.retentionInDays)d retention)",
        "First captured connector inventory"
    )
}
$timelineEvents += [pscustomobject]@{ Date = '2024-08-31'; Lines = @('Microsoft MMA / OMS retired') }
$timelineEvents += [pscustomobject]@{ Date = '2025-02-01'; Lines = @('MMA ingestion degraded') }
$timelineEvents += [pscustomobject]@{ Date = '2025-07-31'; Lines = @('Legacy ThreatIntelligenceIndicator ingestion stopped') }
# Tables-in-use: operational subset (tables that have received billable
# data in 90 days, plus CustomLog tables). The 800+ Microsoft-defined
# schemas the workspace never ingested are catalogue, not deployment —
# surfaced as a separate number to avoid misreading "836 tables in
# catalogue" as "836 tables in use".
$timelineEvents += [pscustomobject]@{
    Date  = $todayShort
    Lines = @(
        "This documentation generated ($wsAgeDays-day-old workspace)",
        "$($enabledRules.Count) rules enabled · $($connectors.Count) connectors · $($operationalTables.Count) tables receiving data ($($workspaceTables.Count) in catalogue)"
    )
}
$timelineEvents += [pscustomobject]@{ Date = '2026-09-14'; Lines = @('HTTP Data Collector API retires — verify no _CL tables affected') }
$timelineEvents += [pscustomobject]@{ Date = '2027-03-31'; Lines = @('Sentinel Azure portal retires (forced Defender XDR move)') }

if ($wsCreatedShort -ne 'unknown') {
    $timelineEvents = @($timelineEvents | Where-Object { $_.Date -ge $wsCreatedShort })
}
$timelineEvents = @($timelineEvents | Sort-Object Date)

$timelineBody = ($timelineEvents | ForEach-Object {
    $lines = @($_.Lines)
    $first = "    $($_.Date) : $($lines[0])"
    if ($lines.Count -gt 1) {
        $rest = @($lines[1..($lines.Count - 1)] | ForEach-Object { "                    : $_" })
        ($first + [Environment]::NewLine + ($rest -join [Environment]::NewLine))
    } else { $first }
}) -join [Environment]::NewLine

$wsBody = @"
$(Format-Banner -Title "Workspace Inventory")

## Workspace + platform history

``````mermaid
timeline
    title Workspace history — $WorkspaceName
$timelineBody
``````

Mixes platform-side deprecations with workspace-specific events (created date, current ingest profile, upcoming deadlines).

## Provenance

| Property | Value |
|---|---|
| Resource ID | ``$($workspace.id)`` |
| Created | $(Format-DateUtc $wsCreated) |
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
        LastIngested = if ($usage) { Format-DateUtc $usage.LastIngested } else { '' }
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

# Plan pie inputs.
$planPieAnalytics  = ($gbByPlan | Where-Object { $_.Plan -eq 'Analytics' }  | Measure-Object -Property Tables -Sum).Sum
$planPieBasic      = ($gbByPlan | Where-Object { $_.Plan -eq 'Basic' }      | Measure-Object -Property Tables -Sum).Sum
$planPieAuxiliary  = ($gbByPlan | Where-Object { $_.Plan -eq 'Auxiliary' }  | Measure-Object -Property Tables -Sum).Sum
if (-not $planPieAnalytics) { $planPieAnalytics = 0 }
if (-not $planPieBasic)     { $planPieBasic = 0 }
if (-not $planPieAuxiliary) { $planPieAuxiliary = 0 }

$tablePlansBody = @"
$(Format-Banner -Title "Table Plans, Retention and Activity")

## Plan adoption

``````mermaid
pie showData title Operational tables by plan
    "Analytics" : $planPieAnalytics
    "Basic" : $planPieBasic
    "Auxiliary" : $planPieAuxiliary
``````

[SENT-016] flags high-volume Analytics tables that could move to Basic / Auxiliary for cost savings; this chart shows the current tier distribution at a glance.

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

# Split DCRs into in-scope (at least one LA destination targets this
# workspace) and out-of-scope (targeting other workspaces in the same
# subscription). The exporter captures DCRs at subscription scope, so
# without this filter a workspace's report lists every DCR the
# executing identity can see — even ones that have nothing to do with
# this workspace, which is confusing.
function _DcrTargetsWorkspace {
    param($Dcr, [string]$WorkspaceId)
    if (-not $WorkspaceId) { return $true }
    if (-not $Dcr.properties.PSObject.Properties.Name -contains 'destinations' -or -not $Dcr.properties.destinations) { return $false }
    if (-not $Dcr.properties.destinations.PSObject.Properties.Name -contains 'logAnalytics') { return $false }
    foreach ($d in @($Dcr.properties.destinations.logAnalytics)) {
        if ([string]::Equals([string]$d.workspaceResourceId, $WorkspaceId, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

$dcrsInScope    = @()
$dcrsOutOfScope = @()
foreach ($d in $dcrs) {
    if (_DcrTargetsWorkspace -Dcr $d -WorkspaceId $workspaceResourceId) { $dcrsInScope += $d } else { $dcrsOutOfScope += $d }
}

$dcrRows = $dcrsInScope | ForEach-Object {
    $streams = ($_.properties.dataFlows | ForEach-Object { $_.streams } | Sort-Object -Unique) -join ', '
    [pscustomobject]@{
        Name         = $_.name
        Kind         = $_.kind
        Streams      = $streams
        HasTransform = if (($_.properties.dataFlows.transformKql) -ne $null) { '✓' } else { '' }
    }
}
$dcrOutOfScopeRows = $dcrsOutOfScope | ForEach-Object {
    # For each out-of-scope DCR, surface which workspace(s) it actually
    # targets so the reader can see why it's been excluded.
    $targets = @()
    if ($_.properties.PSObject.Properties.Name -contains 'destinations' -and $_.properties.destinations) {
        if ($_.properties.destinations.PSObject.Properties.Name -contains 'logAnalytics') {
            foreach ($la in @($_.properties.destinations.logAnalytics)) {
                $wsName = ($la.workspaceResourceId -split '/')[-1]
                if ($wsName) { $targets += $wsName }
            }
        }
    }
    [pscustomobject]@{
        Name      = $_.name
        Kind      = $_.kind
        TargetsWs = if ($targets.Count -gt 0) { ($targets | Sort-Object -Unique) -join ', ' } else { '_(no LA destination)_' }
    }
}

$dceRows = $dces | ForEach-Object {
    [pscustomobject]@{ Name = $_.name; Location = $_.location }
}
# Topology flowchart — sourced from the synthesised $effective view
# rather than $connectors alone, so DCR-driven and diagnostic-settings-
# driven ingestion (the bulk of any modern workspace) appears too.
# Tables are grouped into source buckets via the same name-matching
# logic as the cost Sankey for consistency. Top 15 buckets render
# individually; anything beyond rolls up into "Other sources (N)".
function _TopologyBucketFor {
    param([string]$Table, [string]$Source, [string]$Identifier)
    if ($Source -eq 'CCF' -and $Identifier) { return $Identifier }
    if ($Source -eq 'Classic') {
        # Identifier is "kind/dataType"; the friendly title comes from
        # the Get-ConnectorFriendlyTitle helper above. Strip to kind.
        $kind = ($Identifier -split '/')[0]
        return (Get-ConnectorFriendlyTitle -Kind $kind -Connector $null -CcfTitleByName $ccfTitleByName)
    }
    if (-not $Table) { return 'Other sources' }
    switch -Regex ($Table) {
        '^ThreatIntel'                                                                                  { return 'Microsoft Defender TI' }
        '^(SigninLogs|AuditLogs|AAD.*|MicrosoftGraphActivityLogs|MicrosoftServicePrincipalSignInLogs)$' { return 'Microsoft Entra ID' }
        '^(Device|Email|Url|Alert|Cloud|Identity).*'                                                    { return 'Microsoft Defender XDR' }
        '^ASim'                                                                                         { return 'ASIM normaliser' }
        '^Office'                                                                                       { return 'Office 365' }
        '^(CommonSecurityLog|Syslog)$'                                                                  { return 'CEF / Syslog' }
        '^(SecurityEvent|WindowsEvent|Event)$'                                                          { return 'Windows events' }
        '^(AzureActivity)$'                                                                             { return 'Azure Activity' }
        '^(AzureDiagnostics|AzureMetrics)$'                                                             { return 'Azure resource diagnostics' }
        '^Intune'                                                                                       { return 'Intune' }
        '^App'                                                                                          { return 'Application Insights' }
        '^Dataverse'                                                                                    { return 'Power Platform' }
        '^(LAQueryLogs|Usage|Heartbeat|Operation|Perf|SentinelAudit)$'                                  { return 'Workspace operations' }
        '_CL$'                                                                                          { return 'Custom logs (CCF / DCR)' }
        default                                                                                         { return 'Other sources' }
    }
}

$sourceBuckets = @{}
foreach ($e in $effective) {
    $bucket = _TopologyBucketFor -Table $e.Table -Source $e.Source -Identifier $e.Identifier
    if (-not $sourceBuckets.ContainsKey($bucket)) { $sourceBuckets[$bucket] = 0 }
    $sourceBuckets[$bucket]++
}
# Order: highest item-count first, with the "Other sources" catch-all
# always last regardless of count.
$sortedBuckets = $sourceBuckets.GetEnumerator() |
    Sort-Object @{ Expression = { if ($_.Key -eq 'Other sources') { 1 } else { 0 } } }, @{ Expression = { -$_.Value } } |
    ForEach-Object { @{ Name = $_.Key; Count = $_.Value } }
$displayBuckets = @($sortedBuckets | Select-Object -First 15)
$overflowBuckets = @($sortedBuckets | Select-Object -Skip 15)
$overflowTotal = 0
foreach ($b in $overflowBuckets) { $overflowTotal += $b.Count }

$sourceEdges = @()
$srcIdx = 0
$srcLines = foreach ($b in $displayBuckets) {
    $srcIdx++
    $shortId = "S$srcIdx"
    $sourceEdges += "    $shortId --> WS"
    $label = if ($b.Count -gt 1) { "$($b.Name) · $($b.Count)" } else { $b.Name }
    # Wrap label in double quotes — Mermaid flowchart treats `(` as a
    # node-shape directive, so unquoted labels containing parens parse-
    # error with "Expecting SQE/PE/STADIUMEND etc.".
    "    $shortId[`"$label`"]"
}
if ($overflowBuckets.Count -gt 0) {
    $srcLines += "    S99[`"Other sources · $overflowTotal`"]"
    $sourceEdges += "    S99 --> WS"
}

# Workspace-side node selection. Each cell renders only when the
# underlying capture supports it — a workspace with no Sentinel Data
# Lake should NOT show the Data Lake node, and a workspace with no
# Basic/Auxiliary tables should NOT show those plan nodes either.
#
# Data Lake detection signals (primary first):
#   (a) sentinel-data-lake.json — captures the
#       Microsoft.SentinelPlatformServices/sentinelPlatformServices
#       resource (the tenant-wide Sentinel Data Lake provisioning),
#       resolved via Resource Graph. Non-empty array == Lake exists
#       in the tenant. Authoritative.
#   (b) workspace.properties.features.unifiedSentinelBillingOnly —
#       workspace-level flag set when the workspace is onboarded to
#       the unified Sentinel/Defender billing model. Necessary but
#       not strictly sufficient for Lake (Lake also needs the
#       platform-services resource), so kept as a secondary check.
#   (c) Any workspace table on the 'DataLake' plan — confirms data is
#       actively routed to the Lake-only tier.
$sentinelDataLake = Read-RawArray 'sentinel-data-lake.json'
$unifiedBilling = $false
if ($workspace.properties.PSObject.Properties.Name -contains 'features' -and $workspace.properties.features) {
    if ($workspace.properties.features.PSObject.Properties.Name -contains 'unifiedSentinelBillingOnly') {
        $unifiedBilling = [bool]$workspace.properties.features.unifiedSentinelBillingOnly
    }
}

$plansInUse = @{}
$archiveTables = 0
foreach ($t in $workspaceTables) {
    $p = $t.properties.plan
    if ($p) { $plansInUse[[string]$p] = $true }
    $r  = [int]($t.properties.retentionInDays | ForEach-Object { if ($_) { $_ } else { 0 } })
    $tr = [int]($t.properties.totalRetentionInDays | ForEach-Object { if ($_) { $_ } else { 0 } })
    if ($tr -gt $r -and $tr -gt 0) { $archiveTables++ }
}
$hasBasic     = $plansInUse.ContainsKey('Basic')
$hasAuxiliary = $plansInUse.ContainsKey('Auxiliary')
$hasDataLake  = $plansInUse.ContainsKey('DataLake') -or @($sentinelDataLake).Count -gt 0 -or $unifiedBilling
$hasArchive   = $archiveTables -gt 0

$wspNodes = @('        WS[(Log Analytics workspace)]', "        RUL[Analytics rules · $($enabledRules.Count)]", '        INC[Incidents]')
$wspEdges = @('    WS --> RUL', '    RUL --> INC')
if ($hasBasic)     { $wspNodes += '        BAS[Basic plan tables]';     $wspEdges += '    WS --> BAS' }
if ($hasAuxiliary) { $wspNodes += '        AUX[Auxiliary plan tables]'; $wspEdges += '    WS --> AUX' }
if ($hasDataLake)  { $wspNodes += '        DL[(Sentinel Data Lake)]';   $wspEdges += '    WS --> DL' }
if ($hasArchive)   { $wspNodes += "        ARC[(Long-term archive · $archiveTables tables)]"; $wspEdges += '    WS --> ARC' }

# Downstream — render only the destinations the capture supports.
$dataExports = Read-RawArray 'data-exports.json'
$dataExportCount = @($dataExports).Count
$hasPlaybooks = @($playbooks).Count -gt 0

$dstNodes = @()
$dstEdges = @()
if ($m365DefenderConnected) {
    $dstNodes += '        XDR[Defender XDR portal]'
    $dstEdges += '    INC --> XDR'
}
if ($hasPlaybooks) {
    $dstNodes += "        PB[Playbooks · $(@($playbooks).Count)]"
    $dstEdges += '    INC --> PB'
}
if ($dataExportCount -gt 0) {
    $dstNodes += "        EXP[Data export · $dataExportCount destination(s)]"
    $dstEdges += '    WS --> EXP'
}
# Always-on destination — workbooks consume workspace data regardless
# of incidents. Surface it so the topology shows the reporting flow.
if (@($workbooksSaved).Count -gt 0) {
    $dstNodes += "        WB[Workbooks · $(@($workbooksSaved).Count)]"
    $dstEdges += '    WS --> WB'
}
$hasDownstream = $dstNodes.Count -gt 0
$dstClassLine = ''
if ($hasDownstream) {
    $dstIds = $dstNodes | ForEach-Object { ($_ -split '\[')[0].Trim() }
    $dstClassLine = "    class $($dstIds -join ',') dst"
}
$dcBody = @"
$(Format-Banner -Title "Data Collection Rules and Endpoints")

## Workspace topology

Every captured ingestion source appears on the left, grouped into product-family buckets (the count after the bucket name is the number of distinct sources contributing). Workspace-side and downstream nodes only render when the underlying state supports them — a workspace with no Data Lake won't show a Data Lake node; the Defender XDR portal only appears when the M365 Defender connector is enabled.

``````mermaid
flowchart LR
    subgraph SRC["Connected sources"]
        direction TB
$($srcLines -join [Environment]::NewLine)
    end

    subgraph WSP["Sentinel workspace"]
        direction TB
$($wspNodes -join [Environment]::NewLine)
    end
$(if ($hasDownstream) { @"

    subgraph DST["Downstream"]
        direction TB
$($dstNodes -join [Environment]::NewLine)
    end
"@ })

$($sourceEdges -join [Environment]::NewLine)
$($wspEdges -join [Environment]::NewLine)
$(if ($hasDownstream) { $dstEdges -join [Environment]::NewLine })

    classDef src fill:#1a3b5b,stroke:#37a,color:#dfd
    classDef wsp fill:#5b3a1a,stroke:#a73,color:#fed
    classDef dst fill:#1a3b1a,stroke:#3a3,color:#dfd
    class $((@('WS','RUL','INC') + @(if ($hasBasic){'BAS'}) + @(if ($hasAuxiliary){'AUX'}) + @(if ($hasDataLake){'DL'}) + @(if ($hasArchive){'ARC'})) -join ',') wsp
$dstClassLine
``````

## DCRs

Only DCRs whose ``destinations.logAnalytics`` includes this workspace appear here. DCRs that live in this subscription but route to other workspaces are excluded from the primary table (see *Other DCRs in subscription* below).

$(Format-Table -Items $dcrRows -Columns 'Name','Kind','Streams','HasTransform')

$(if ($dcrOutOfScopeRows.Count -gt 0) { @"

## Other DCRs in subscription (targeting different workspaces)

These DCRs were captured at subscription scope but their LA destinations point at workspaces other than ``$WorkspaceName``. Useful for cleanup audits (orphaned DCRs from decommissioned workspaces, mis-routed DCRs after a workspace migration, etc.) — not relevant to this workspace's ingestion.

$(Format-Table -Items $dcrOutOfScopeRows -Columns 'Name','Kind','TargetsWs')
"@ })

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

# ---------------------------------------------------------------------
# Sankey prep — computed outside the heredoc so $sankeyFlowText and
# $sankeyHeight can be interpolated, and the long-tail collapse logic
# is testable in isolation.
# ---------------------------------------------------------------------
function _CostSourceFor {
    param([string]$Table)
    switch -Regex ($Table) {
        '^ThreatIntel'                                             { return 'Microsoft Defender TI' }
        '^(SigninLogs|AuditLogs|AAD.*|MicrosoftGraphActivityLogs|MicrosoftServicePrincipalSignInLogs)$' { return 'Microsoft Entra ID' }
        '^(Device|Email|Url|Alert|Cloud|Identity).*'               { return 'Microsoft Defender XDR' }
        '^ASim'                                                    { return 'ASIM normaliser' }
        '^Office'                                                  { return 'Office 365' }
        '^(CommonSecurityLog|Syslog)$'                             { return 'CEF / Syslog' }
        '^(SecurityEvent|WindowsEvent|Event)$'                     { return 'Windows events' }
        '^(AzureActivity|AzureDiagnostics|AzureMetrics)$'          { return 'Azure platform' }
        '^Intune'                                                  { return 'Intune' }
        '^Unifi'                                                   { return 'UniFi' }
        '^Tailscale'                                               { return 'Tailscale' }
        '^App(Traces|Metrics|Requests|Dependencies|Exceptions|PageViews|PerformanceCounters|Events|SystemEvents|ServiceHTTPLogs|ServiceConsoleLogs|ServicePlatformLogs|ServiceFileAuditLogs|ServiceIPSecAuditLogs|ServiceAntivirusScanAuditLogs)$' { return 'Application Insights' }
        '^(LAQueryLogs|Usage|Heartbeat|Operation|Perf)$'           { return 'Workspace operations' }
        '^Dataverse'                                               { return 'Power Platform' }
        '_CL$'                                                     { return 'Custom (CCF / DCR)' }
        default                                                    { return 'Other' }
    }
}

# Use the full per-table cost list when the exporter wrote it; fall back
# to Top-10 for older captures so the chart still renders.
$allTables = if ($cost.PSObject.Properties.Name -contains 'AllTablesByCost' -and $cost.AllTablesByCost) {
    @($cost.AllTablesByCost)
} else {
    @($cost.Top10TablesByCost)
}

$flowFiltered = New-Object System.Collections.Generic.List[object]
foreach ($t in $allTables) {
    $gb = [double]$t.Gb30d
    if ($gb -lt 0.01) { continue }
    $tier = if ($t.Plan -eq 'Analytics') { 'Sentinel-rate billing' } else { 'LA-rate billing' }
    $flowFiltered.Add([pscustomobject]@{
        Table  = $t.Table
        Gb     = $gb
        Source = (_CostSourceFor $t.Table)
        Tier   = $tier
    })
}

# Decide which tables keep their own middle-column node. On a busy
# workspace with ~80+ tables the Sankey middle column becomes an
# unreadable wall — fix by collapsing the cost-insignificant tail into
# per-source bucket nodes. Rule: tables in the top 90% of billable GB
# stay individual; the remainder collapse to "<source> tail (N)".
# Workspaces with ≤25 tables skip the collapse entirely.
$totalGb = ($flowFiltered | Measure-Object -Property Gb -Sum).Sum
$sorted = $flowFiltered | Sort-Object -Property Gb -Descending
$keepIndividual = @{}
if ($sorted.Count -le 25 -or $totalGb -le 0) {
    foreach ($r in $sorted) { $keepIndividual[$r.Table] = $true }
} else {
    $cum = 0.0
    $threshold = $totalGb * 0.90
    foreach ($r in $sorted) {
        $keepIndividual[$r.Table] = $true
        $cum += $r.Gb
        if ($cum -ge $threshold) { break }
    }
}

# Promote single-occupant tail sources — a bucket of one is uglier than
# just showing the table.
$tailCount = @{}
foreach ($r in $flowFiltered) {
    if (-not $keepIndividual.ContainsKey($r.Table)) {
        if (-not $tailCount.ContainsKey($r.Source)) { $tailCount[$r.Source] = 0 }
        $tailCount[$r.Source]++
    }
}
foreach ($r in $flowFiltered) {
    if (-not $keepIndividual.ContainsKey($r.Table) -and $tailCount[$r.Source] -lt 2) {
        $keepIndividual[$r.Table] = $true
    }
}
# Recompute counts after promotions so the bucket labels show the
# accurate post-promotion count.
$tailCount = @{}
foreach ($r in $flowFiltered) {
    if (-not $keepIndividual.ContainsKey($r.Table)) {
        if (-not $tailCount.ContainsKey($r.Source)) { $tailCount[$r.Source] = 0 }
        $tailCount[$r.Source]++
    }
}

$bySourceTable = @{}
$byTableTier   = @{}
foreach ($r in $flowFiltered) {
    $tableNode = if ($keepIndividual.ContainsKey($r.Table)) {
        $r.Table
    } else {
        "$($r.Source) tail ($($tailCount[$r.Source]))"
    }
    $stKey = "$($r.Source)||$tableNode"
    $ttKey = "$tableNode||$($r.Tier)"
    if (-not $bySourceTable.ContainsKey($stKey)) { $bySourceTable[$stKey] = 0.0 }
    if (-not $byTableTier.ContainsKey($ttKey))   { $byTableTier[$ttKey]   = 0.0 }
    $bySourceTable[$stKey] += $r.Gb
    $byTableTier[$ttKey]   += $r.Gb
}

$flowRowsList = New-Object System.Collections.Generic.List[string]
foreach ($k in $bySourceTable.Keys) {
    $parts = $k -split '\|\|'
    $flowRowsList.Add("$($parts[0]),$($parts[1]),$([math]::Round($bySourceTable[$k], 3))")
}
foreach ($k in $byTableTier.Keys) {
    $parts = $k -split '\|\|'
    $flowRowsList.Add("$($parts[0]),$($parts[1]),$([math]::Round($byTableTier[$k], 3))")
}
$sankeyFlowText = $flowRowsList -join [Environment]::NewLine

# Dynamic height — Mermaid sankey-beta crams labels when nodes exceed
# the configured height. Scale with the middle-column count (the wide
# axis) and the source-column count, whichever's larger.
$middleNodeCount = @(($bySourceTable.Keys | ForEach-Object { ($_ -split '\|\|')[1] }) | Sort-Object -Unique).Count
$sourceCount     = @(($bySourceTable.Keys | ForEach-Object { ($_ -split '\|\|')[0] }) | Sort-Object -Unique).Count
$tallestColumn   = [Math]::Max($middleNodeCount, $sourceCount)
$sankeyHeight    = [Math]::Max(720, 24 * $tallestColumn + 200)

# Disclosure line used in the section narrative — accurate whether the
# long-tail collapse fired or not.
$sankeyTailNote = if ($flowFiltered.Count -gt $middleNodeCount) {
    $tailTables = $flowFiltered.Count - ($keepIndividual.Keys.Count)
    " The bottom 10% of billable GB has been collapsed into per-source ``tail (N)`` buckets to keep the middle column readable ($tailTables small table(s) bucketed)."
} else { '' }

@"
$(Format-Banner -Title "Estimated Monthly Cost")

> **Headline** **$($cost.MonthlyTotal) $($cost.Currency)** for the workspace, based on the last 30 days of `Usage` × Azure Retail Prices for ``$($cost.Region)`` as of ``$(Format-DateUtc $cost.AsOfUtc)``.

## By plan

$(Format-Table -Items $planRows -Columns 'Plan','Gb30d','MonthlyCost')

## Top tables by cost

``````mermaid
---
config:
  xyChart:
    width: 1400
    height: 480
---
xychart-beta
    title "Top tables by 30d billable GB"
    x-axis [$(($cost.Top10TablesByCost | ForEach-Object {
        $t = if ($_.Table.Length -gt 14) { $_.Table.Substring(0,14) } else { $_.Table }
        "`"$t`""
    }) -join ', ')]
    y-axis "GB" 0 --> $([math]::Ceiling(([double]($cost.Top10TablesByCost | Measure-Object -Property Gb30d -Maximum).Maximum + 0.5)))
    bar [$(($cost.Top10TablesByCost | ForEach-Object { $_.Gb30d }) -join ', ')]
``````

Long-tail concentration: the loudest table is always the right first cost-optimisation target. Full table names in the table below (short labels above are truncated for chart-axis fit).

$(Format-Table -Items $cost.Top10TablesByCost -Columns 'Table','Plan','Gb30d','MonthlyCost')

## Cost concentration — mindmap

``````mermaid
mindmap
    root((30-day billable<br/>$([math]::Round([double]($cost.Top10TablesByCost | Measure-Object -Property Gb30d -Sum).Sum, 2)) GB))
$(($cost.Top10TablesByCost | Select-Object -First 8 | ForEach-Object {
    # Two-line label — Mermaid mindmap nodes have a tight horizontal
    # fit-to-text bound that clips long single-line labels. Stacking
    # the table name above the GB value keeps both fully visible.
    # Round-to-significance: ≥100 GB no decimals, ≥10 GB one decimal,
    # below that two — strips the noisy ".42" tails that contributed
    # to the overflow without losing information for small tables.
    $gb = [double]$_.Gb30d
    $gbLabel = if ($gb -ge 100) {
        [math]::Round($gb, 0).ToString()
    } elseif ($gb -ge 10) {
        [math]::Round($gb, 1).ToString()
    } else {
        [math]::Round($gb, 2).ToString()
    }
    "        $($_.Table)<br/>$gbLabel GB"
}) -join [Environment]::NewLine)
``````

Tree view of where the chargeable footprint lands. Pair with the top-tables bar above — same data, different shape, easier scan for "is one source dominating?".

## Cost flow — source → table → billing tier

``````mermaid
---
config:
  sankey:
    showValues: true
    nodeAlignment: justify
    nodePadding: 28
    height: $sankeyHeight
    width: 1200
    useMaxWidth: true
    linkColor: gradient
---
sankey-beta

$sankeyFlowText
``````

Three columns: source on the left, workspace table in the middle, billing tier on the right. Sentinel-rate billing covers tables on the Analytics plan; LA-rate billing covers Basic / Auxiliary. Findings [SENT-043] / [SENT-044] / [SENT-046] flag tables that could re-route from Sentinel-rate to LA-rate via DCR-based splits.$sankeyTailNote

## Cost flow — table → billing tier (compact view)

Top-10 cost-bearing tables routed to their billing tier. Sentinel-rate covers tables on the Analytics plan; LA-rate covers Basic / Auxiliary. Billing-tier nodes only render when at least one table routes to them — a workspace with no LA-rate tables won't display an LA-rate node.

$(
$compactSource = if ($cost.PSObject.Properties.Name -contains 'AllTablesByCost' -and $cost.AllTablesByCost) {
    @($cost.AllTablesByCost) | Select-Object -First 10
} else {
    @($cost.Top10TablesByCost)
}
$compactEdges = @()
$compactNeedsSent = $false
$compactNeedsLa   = $false
foreach ($t in $compactSource) {
    $tbl = $t.Table
    $tblId = ($tbl -replace '[^a-zA-Z0-9]', '')
    $gb = $t.Gb30d
    $plan = $t.Plan
    $billing = if ($plan -eq 'Analytics') { 'SENT' } else { 'LA' }
    if ($billing -eq 'SENT') { $compactNeedsSent = $true } else { $compactNeedsLa = $true }
    $compactEdges += "    $tblId[`"$tbl<br/>$gb GB`"] --> $billing"
}
$compactNodes = @()
if ($compactNeedsSent) { $compactNodes += '    SENT[Sentinel-rate billing]' }
if ($compactNeedsLa)   { $compactNodes += '    LA[LA-rate billing]' }
$compactClasses = @()
if ($compactNeedsSent) { $compactClasses += '    class SENT sentinel' }
if ($compactNeedsLa)   { $compactClasses += '    class LA la' }
@"
``````mermaid
flowchart LR
$($compactEdges -join [Environment]::NewLine)
$($compactNodes -join [Environment]::NewLine)
    classDef sentinel fill:#5b1a1a,stroke:#a33,color:#fdd
    classDef la fill:#1a3b1a,stroke:#3a3,color:#dfd
$($compactClasses -join [Environment]::NewLine)
``````
"@
)

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

# Principal fallback chain — DisplayName is empty for some assignments
# (deleted SPs, certain group types, MIs without a friendly name). Fall
# back to SignInName, then to the GUID ObjectId so the column always
# has content. An ObjectId-only row is a signal the principal may have
# been deleted but the role assignment lingers — itself a useful audit
# finding.
function _RbacPrincipal {
    param($Row)
    if ($Row.DisplayName) { return [string]$Row.DisplayName }
    if ($Row.SignInName)  { return [string]$Row.SignInName }
    if ($Row.ObjectId)    { return "_(no display name)_ ``$($Row.ObjectId)``" }
    return '_(unknown)_'
}
$wsRows = $rbacWs | ForEach-Object {
    [pscustomobject]@{ Principal = (_RbacPrincipal $_); Type = $_.ObjectType; Role = $_.RoleDefinitionName }
}
$rgRows = $rbacRg | ForEach-Object {
    [pscustomobject]@{ Principal = (_RbacPrincipal $_); Type = $_.ObjectType; Role = $_.RoleDefinitionName }
}

# Build the RBAC flowchart. Group principals by role to keep the flow readable.
# Mark broad-role paths (Owner / Contributor) as warnings via dotted edges.
$rolesSeen = New-Object System.Collections.Generic.HashSet[string]
foreach ($r in $rbacWs) {
    $role = $r.RoleDefinitionName
    if ($role) { [void]$rolesSeen.Add($role) }
}
$roleNodeLines = @()
$roleIdMap = @{}
$roleIdx = 0
foreach ($role in $rolesSeen) {
    $roleIdx++
    $rId = "R$roleIdx"
    $roleIdMap[$role] = $rId
    $roleNodeLines += "        $rId[$role]"
}

# Per-role principal counts so the diagram doesn't list every individual SP.
$principalsByRole = @{}
foreach ($r in $rbacWs) {
    $role = $r.RoleDefinitionName
    $type = $r.ObjectType
    if (-not $principalsByRole.ContainsKey($role)) { $principalsByRole[$role] = @{ User = 0; Group = 0; ServicePrincipal = 0 } }
    if ($principalsByRole[$role].ContainsKey($type)) { $principalsByRole[$role][$type]++ }
}

$principalNodes = @()
$principalEdges = @()
$principalClicks = @()
$prinIdx = 0
foreach ($role in $rolesSeen) {
    foreach ($t in @('User', 'Group', 'ServicePrincipal')) {
        $n = $principalsByRole[$role][$t]
        if ($n -eq 0) { continue }
        $prinIdx++
        $prinId = "P$prinIdx"
        $principalNodes += "        $prinId[$n $t$(if ($n -gt 1) { 's' })]"
        if ($role -in @('Owner', 'Contributor')) {
            $sentId = if ($t -eq 'ServicePrincipal') { 'sent-039' } else { 'sent-009' }
            $principalEdges += "    $prinId -.->|broad| $($roleIdMap[$role])"
            $principalClicks += "    click $prinId href ""90-gap-analysis.md#$sentId"" ""$($sentId.ToUpper()) — broad role recommendation"""
        } else {
            $principalEdges += "    $prinId --> $($roleIdMap[$role])"
        }
    }
}

Write-Section '85-rbac.md' (@"
$(Format-Banner -Title "RBAC")

$($rbacWs.Count) workspace-scope assignment(s) across $($rolesSeen.Count) distinct role(s). Dotted amber edges below mark broad-role paths (Owner / Contributor) — see [SENT-009] and [SENT-039] in the gap analysis.

## Who-grants-what-to-whom

``````mermaid
flowchart LR
    subgraph PRIN["Principals"]
        direction TB
$($principalNodes -join [Environment]::NewLine)
    end

    subgraph ROLES["Roles at workspace scope"]
        direction TB
$($roleNodeLines -join [Environment]::NewLine)
    end

$($principalEdges -join [Environment]::NewLine)

    classDef sentinelRole fill:#1a3b1a,stroke:#3a3,color:#dfd
    classDef broadRole fill:#5b1a1a,stroke:#a33,color:#fdd
$(($rolesSeen | ForEach-Object {
    if ($_ -in @('Owner', 'Contributor')) { "    class $($roleIdMap[$_]) broadRole" }
    elseif ($_ -like 'Microsoft Sentinel*') { "    class $($roleIdMap[$_]) sentinelRole" }
}) -join [Environment]::NewLine)
$($principalClicks -join [Environment]::NewLine)
``````

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

# Resource-provider registration-state pie for the headline.
$rpStateCounts = @{}
foreach ($r in $rpRows) {
    $s = if ($r.State) { [string]$r.State } else { 'Unknown' }
    if (-not $rpStateCounts.ContainsKey($s)) { $rpStateCounts[$s] = 0 }
    $rpStateCounts[$s]++
}
$rpPieRows = $rpStateCounts.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}
$rpChartBlock = if ($rpRows.Count -gt 0) {
    @"

## Resource-provider registration state

``````mermaid
pie showData title Required resource providers — registration state
$($rpPieRows -join [Environment]::NewLine)
``````

[SENT-022] fires whenever any required provider is not in the `Registered` state. The pie surfaces that ratio at a glance.
"@
} else { '' }

Write-Section '86-subscription-context.md' (@"
$(Format-Banner -Title "Subscription and Tenant Context")

## Subscription

| | |
|---|---|
| Name | $($sub.Name) |
| ID   | ``$($sub.Id)`` |
| Tenant ID | ``$($sub.TenantId)`` |
| State | $($sub.State) |
$rpChartBlock

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
        ID       = "[$($_.Id)](#$(($_.Id).ToLower()))"
        Severity = Format-Severity-Badge $_.Severity
        Category = $_.Category
        Title    = $_.Title
    }
}

# Evidence + Learn link formatters for the detailed remediation cards
# below. Evidence text from gap rules can be very long with semicolon-
# separated lists (e.g. 657 disabled rule names). Cramming that into a
# narrow table cell is unreadable. The detail-card form splits long
# semicolon lists into bullet items and renders short evidence inline.
function _FormatGapEvidence {
    param([string]$Evidence)
    if (-not $Evidence) { return '_(none)_' }
    # Threshold: only expand to bullets when the evidence is both long
    # AND list-shaped (4+ semicolons). Short evidence ("X 75% threshold
    # exceeded") stays inline.
    $semis = ([regex]::Matches($Evidence, ';')).Count
    if ($Evidence.Length -lt 200 -or $semis -lt 3) { return $Evidence }

    # Split on the colon-then-list pattern so the lead-in prose stays
    # before the bulleted list. Example:
    #   "Recommended connectors not deployed: A, B, C"
    #   -> "Recommended connectors not deployed:\n- A\n- B\n- C"
    $leadEnd = $Evidence.IndexOf(':')
    if ($leadEnd -gt 0 -and $leadEnd -lt 200) {
        $lead  = $Evidence.Substring(0, $leadEnd + 1).Trim()
        $tail  = $Evidence.Substring($leadEnd + 1).Trim()
        $items = $tail -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        return @"
$lead

$(($items | ForEach-Object { "  - $_" }) -join [Environment]::NewLine)
"@
    }
    # No leading colon — bullet the whole list.
    $items = $Evidence -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    return ($items | ForEach-Object { "  - $_" }) -join [Environment]::NewLine
}

function _FormatGapLearnLink {
    param([string]$Url)
    if (-not $Url) { return '_(no reference)_' }
    # Use a friendly title rather than a bare URL. Extract the last URL
    # path segment, replace hyphens with spaces, and title-case the
    # result. Falls back to "Microsoft Learn" if the path is empty.
    try {
        $u = [uri]$Url
        $last = ($u.AbsolutePath.TrimEnd('/') -split '/')[-1]
        if (-not $last) { $last = 'Microsoft Learn' }
        $words = ($last -replace '-', ' ')
        $titled = (Get-Culture).TextInfo.ToTitleCase($words.ToLower())
        if (-not $titled) { $titled = 'Microsoft Learn' }
        return "[$titled (Microsoft Learn)]($Url)"
    } catch {
        return "[Microsoft Learn]($Url)"
    }
}
# Findings landscape — grouped bar by category × severity. Sort categories
# by Warning-then-Info count desc so the worst buckets land on the left.
$catOrder = $gapByCategory.Keys | Sort-Object {
    -(1000 * ($gapByCategory[$_].Critical) + 10 * ($gapByCategory[$_].Warning) + ($gapByCategory[$_].Info))
}
$catAxis = ($catOrder | ForEach-Object { "`"$_`"" }) -join ', '
$catWarn = ($catOrder | ForEach-Object { $gapByCategory[$_].Warning }) -join ', '
$catInfo = ($catOrder | ForEach-Object { $gapByCategory[$_].Info }) -join ', '
$catMax = 1
foreach ($c in $catOrder) {
    $t = $gapByCategory[$c].Warning + $gapByCategory[$c].Info + $gapByCategory[$c].Critical
    if ($t -gt $catMax) { $catMax = $t }
}

Write-Section '90-gap-analysis.md' (@"
$(Format-Banner -Title "Gap Analysis")

The gap engine compares the live workspace against the rule set in [Private/Resources/best-practices.json](../../Tools/Documenter/Private/Resources/best-practices.json). Each row is a Test-* function in [Private/GapChecks.ps1](../../Tools/Documenter/Private/GapChecks.ps1) — adding a new rule is a two-line change.

## Findings landscape

``````mermaid
xychart-beta
    title "Findings by category — split by severity"
    x-axis [$catAxis]
    y-axis "Findings" 0 --> $($catMax + 1)
    bar "Warning" [$catWarn]
    bar "Info"    [$catInfo]
``````

**$($gapFindings.Count) findings.** Categories sorted worst-first (Critical → Warning → Info weighting). Each bar is a category; adjacent Warning + Info bars per category make the severity mix visible at a glance.

## Findings summary

Each ID links to the detail card below. Severity badge is colour-coded; full evidence, remediation and reference links live in the per-finding cards. Sort by severity first, then by category.

$(if ($gapRows.Count -gt 0) { Format-Table -Items $gapRows -Columns 'ID','Severity','Category','Title' } else { '_No findings — clean run._' })

## Findings detail

$(if ($gapFindings.Count -gt 0) {
    ($gapFindings | ForEach-Object { @"
<a id="$($_.Id.ToLower())"></a>

### $($_.Id) — $($_.Title)

**Severity:** $(Format-Severity-Badge $_.Severity)  ·  **Category:** $($_.Category)

**Evidence**

$(_FormatGapEvidence $_.Evidence)

**Remediation**

$($_.Remediation)

**Reference:** $(_FormatGapLearnLink $_.Learn)

---
"@ }) -join [Environment]::NewLine
} else { '' })
"@)

# ---------------------------------------------------------------------------
# New sections aligned to the formal Sentinel Configuration TOC
# (TOC numbering shown alongside each MD filename).
# ---------------------------------------------------------------------------

# Section 01 — Live snapshot  (TOC 1)
# Living-documentation framing: this page is regenerated from the live
# workspace on every CI/CD pipeline trigger and every pull request, so the
# numbers reflect the workspace at the render timestamp — not a periodic
# audit deliverable. Title and description avoid "report" / "summary"
# language to reinforce that this is documentation-as-code, not a
# point-in-time deck.
# Synthesised from headline counts + cost + top gap findings + MITRE coverage.
# $gapBySeverity / $gapByCategory are computed up at the top of the file
# (around line 285) so 00-overview can also use them. Don't recompute here.

# Today + days-until calculations drive the deprecation gantt bar widths.
$today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
function _DaysUntilFromToday {
    param([string]$IsoDate)
    $target = [datetime]::Parse($IsoDate, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
    $delta = $target.ToUniversalTime() - (Get-Date).ToUniversalTime()
    [int][math]::Ceiling($delta.TotalDays)
}
$clv1Days = _DaysUntilFromToday '2026-09-14'
$tipDays  = _DaysUntilFromToday '2027-06-30'
$xdrDays  = _DaysUntilFromToday '2027-03-31'

# MITRE coverage rollup. Reuse $mitreRowsRich from section 25 — that view
# already does the intersect-with-catalogue (rules' tactic shortnames must
# match a catalogue.sentinelShortName) and categorises each tactic as
# Covered / Thin / None against the 3-rule threshold. Counting from the
# same source guarantees the headline and the section-25 matrix agree.
$tacticsTotal         = if ($tactics) { $tactics.Count } else { 14 }
$tacticsCoveredFull   = @($mitreRowsRich | Where-Object { $_.Coverage -eq '🟢 Covered' }).Count
$tacticsThin          = @($mitreRowsRich | Where-Object { $_.Coverage -eq '🟠 Thin'    }).Count
$tacticsNone          = @($mitreRowsRich | Where-Object { $_.Coverage -eq '🔴 None'    }).Count
$thinTacticNames      = @($mitreRowsRich | Where-Object { $_.Coverage -eq '🟠 Thin'    } | Select-Object -ExpandProperty Tactic)
$noneTacticNames      = @($mitreRowsRich | Where-Object { $_.Coverage -eq '🔴 None'    } | Select-Object -ExpandProperty Tactic)
$mitreSuffix          = if ($thinTacticNames.Count -gt 0 -or $noneTacticNames.Count -gt 0) {
    $parts = @()
    if ($noneTacticNames.Count -gt 0) { $parts += "uncovered: $($noneTacticNames -join ', ')" }
    if ($thinTacticNames.Count -gt 0) { $parts += "thin: $($thinTacticNames -join ', ')" }
    "  ·  $($parts -join '  ·  ')"
} else { '' }

$execBody = @"
$(Format-Banner -Title "Live snapshot")

> Living documentation for the Microsoft Sentinel workspace ``$WorkspaceName``. Every page in this set is regenerated from the live workspace on every CI/CD pipeline run and every pull request, so the numbers below describe the workspace as it stands at the timestamp above — not a periodic audit deliverable. If a value looks stale, re-run the pipeline; there is no separate refresh cycle.

## Findings by severity

``````mermaid
pie showData title Findings by severity (current run)
    "Critical" : $($gapBySeverity.Critical)
    "Warning"  : $($gapBySeverity.Warning)
    "Info"     : $($gapBySeverity.Info)
``````

## Platform deprecation runway

``````mermaid
gantt
    title Microsoft Sentinel platform deprecation runway
    dateFormat YYYY-MM-DD
    axisFormat %b %Y

    section Past deadlines
    MMA / OMS agent retired                :done,  mma,  2024-08-31, 1d
    MMA ingestion degraded                 :done,  mmaI, 2025-02-01, 1d
    Legacy TI ingestion stopped            :done,  ti,   2025-07-31, 1d

    section Upcoming
    Today                                  :milestone, today, $today, 0d
    HTTP Data Collector API retires        :crit,  clv1, $today, ${clv1Days}d
    Legacy TIP connector deprecates        :active, tip,  $today, ${tipDays}d
    Sentinel Azure portal retires (→ XDR)  :crit,  xdr,  $today, ${xdrDays}d
``````

## Workspace at a glance

| Indicator | Value |
|---|---:|
| Workspace SKU | ``$($workspace.properties.sku.name)`` |
| Default retention | $($workspace.properties.retentionInDays) days |
| Daily cap | $(if ($workspace.properties.workspaceCapping.dailyQuotaGb -eq -1) { 'Unlimited' } else { "$($workspace.properties.workspaceCapping.dailyQuotaGb) GB" }) |
| Estimated monthly cost | $(if ($cost) { "$($cost.MonthlyTotal) $($cost.Currency)" } else { 'n/a' }) |
| Data connectors | $($connectors.Count) |
| Analytics rules (enabled / total) | $($enabledRules.Count) / $($rules.Count) |
| MITRE tactics — Covered / Thin / None | $tacticsCoveredFull / $tacticsThin / $tacticsNone of $tacticsTotal$mitreSuffix |
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
Write-Section '01-live-snapshot.md' $execBody

# Section 11 — Sentinel health (TOC 4.8)
$health = Read-RawArray 'sentinel-health.json'
$healthRows = $health | ForEach-Object {
    [pscustomobject]@{
        Resource = $_.SentinelResourceName
        Kind     = $_.SentinelResourceKind
        Type     = $_.SentinelResourceType
        Events   = $_.Events
        Statuses = ($_.Statuses -join ', ')
        LastEvent= Format-DateUtc $_.LastEvent
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
# Chart inputs: bucket health events by Status across all operations.
$healthByStatus = @{}
foreach ($r in $healthSummary) {
    $s = if ($r.Status) { [string]$r.Status } else { 'Unknown' }
    if (-not $healthByStatus.ContainsKey($s)) { $healthByStatus[$s] = 0 }
    $healthByStatus[$s] += [long]$r.LogCount
}
$healthPieRows = $healthByStatus.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}
$healthChartBlock = if ($healthSummary.Count -gt 0) {
    @"

## Health-event status mix

``````mermaid
pie showData title SentinelHealth events by status (last 7d)
$($healthPieRows -join [Environment]::NewLine)
``````

Mostly-Success workspaces are operating cleanly. A non-trivial Failure / PartialSuccess slice means a Sentinel resource (rule, connector) has misfired recently.
"@
} else { '' }

Write-Section '11-sentinel-health.md' (@"
$(Format-Banner -Title "Sentinel Health and Resilience  (TOC 4.8)")

Health events are pulled from the workspace's ``SentinelHealth`` table for the last 7 days, summarised per Sentinel resource. The table is empty on workspaces where Sentinel diagnostics have not been enabled — see [Microsoft Learn: turn on health diagnostics](https://learn.microsoft.com/azure/sentinel/health-audit) to start the data flowing.
$healthChartBlock

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
# Chart input: bucket recommendations by category for the headline pie.
$socCategoryCounts = [ordered]@{
    'Coverage' = $socCovRows.Count
    'Data Value' = $socDvRows.Count
    'Other' = $socOther.Count
}
$socPieRows = $socCategoryCounts.GetEnumerator() | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}
$socTotal = $socCategoryCounts.Values | Measure-Object -Sum | Select-Object -ExpandProperty Sum
$socChartBlock = if ($socTotal -gt 0) {
    @"

## Recommendation mix

``````mermaid
pie showData title SOC Optimization recommendations by category
$($socPieRows -join [Environment]::NewLine)
``````

$socTotal recommendations grouped by what action they drive. Coverage = onboard content; Data Value = tune ingestion; Other = MITRE tagging, UEBA, customers-like-me.
"@
} else { '' }

Write-Section '12-soc-optimization.md' (@"
$(Format-Banner -Title "SOC Optimization Insights  (TOC 4.9)")

Recommendations from the SOC Optimization service (preview). The endpoint is empty on workspaces where the service has not run, or in regions where it is not yet available. Recommendations are grouped by the kind of action they drive.
$socChartBlock

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

# Aggregate CEF logs by DeviceVendor for the headline pie.
$cefByVendor = @{}
foreach ($r in $cefDevices) {
    $v = if ($r.DeviceVendor) { [string]$r.DeviceVendor } else { 'Unknown' }
    if (-not $cefByVendor.ContainsKey($v)) { $cefByVendor[$v] = 0 }
    $cefByVendor[$v] += [long]$r.LogCount
}
$cefPieRows = $cefByVendor.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 6 | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}
$cefChartBlock = if ($cefDevices.Count -gt 0) {
    @"

## CEF vendor mix

``````mermaid
pie showData title CommonSecurityLog by DeviceVendor (last 7d)
$($cefPieRows -join [Environment]::NewLine)
``````

A single vendor dominating means CEF ingestion is mostly that source — likely a candidate for SENT-043 (`_CL` split) if volume is high.
"@
} else { '' }

Write-Section '13-data-source-hygiene.md' (@"
$(Format-Banner -Title "Data Source Hygiene")

Operational data-quality findings that drive ingestion-tuning actions: misrouted records, agent dual-collection, and noisy event types. Each table is independent and may show ``_None._`` when the workspace has nothing to report against that check.
$cefChartBlock

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
# XDR-table-presence inputs for the bar chart. Short-label-axis with full
# names in the table below.
$xdrChartBlock = if ($xdrPres.Count -gt 0) {
    $xdrAxis = ($xdrRows | Select-Object -First 12 | ForEach-Object {
        $n = $_.Table
        $s = if ($n.Length -gt 12) { $n.Substring(0,12) } else { $n }
        "`"$s`""
    }) -join ', '
    $xdrBars = ($xdrRows | Select-Object -First 12 | ForEach-Object { [long]$_.RecordCount }) -join ', '
    $xdrYmax = [long]1
    foreach ($r in $xdrRows | Select-Object -First 12) { if ([long]$r.RecordCount -gt $xdrYmax) { $xdrYmax = [long]$r.RecordCount } }
    @"

## XDR table activity (last 7d)

``````mermaid
---
config:
  xyChart:
    width: 1400
    height: 480
---
xychart-beta
    title "Defender XDR tables — records ingested last 7d"
    x-axis [$xdrAxis]
    y-axis "Records" 0 --> $($xdrYmax + ([math]::Ceiling($xdrYmax * 0.1)))
    bar [$xdrBars]
``````

A short bar means that XDR surface (email / device / identity / cloud-app) isn't producing data. Bar at 0 = the workspace's XDR connector is silent for that table — investigate or accept (some XDR products gate certain tables behind licensing).
"@
} else { '' }

Write-Section '14-coverage-breakdowns.md' (@"
$(Format-Banner -Title "Coverage Breakdowns")

Per-source coverage gaps revealed by direct table queries. A subscription, resource provider, or XDR table missing from these tables is a coverage gap to triage.
$xdrChartBlock

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

$incidentBody = @"
$(Format-Banner -Title "Incidents  (TOC 4.10)")

> Aggregate-only. The documenter never exports incident bodies, alert payloads or entity detail — only counts and derived SOC-efficiency metrics.

$mttrLine

$dailyLine

> When triaging a high MTTR, cross-reference [21-analytics-by-volume.md](21-analytics-by-volume.md) for the rules driving raw alert load — high alert volume from a single rule usually inflates time-to-acknowledge for everything else in the queue.

## Incident lifecycle

``````mermaid
stateDiagram-v2
    [*] --> New : Alert fires
    New --> Active : Analyst opens
    New --> Closed : Auto-suppress<br/>(SENT-030 fires here)
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
        $totalIncidents incidents in 30d
        $closedCount reached Closed
        $unackCount closed without acknowledgement
    end note
``````

## Analyst journey — typical high-severity incident

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
    title Analyst journey — typical high-severity incident
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

Dips at "KQL hunt for context" and "Identify scope" mark the SOC pain points. Workspaces firing [SENT-034] (no automation) see steeper dips because every step is manual.

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
$volChartBlock = if ($ruleVolumes.Count -gt 0) {
    $top10 = $ruleVolumes | Select-Object -First 10
    $volAxis = ($top10 | ForEach-Object {
        $n = $_.AlertName
        # Use first significant word, max 12 chars, no parens
        $clean = ($n -replace '\(.*?\)', '' -replace '\[.*?\]', '').Trim()
        $words = $clean -split '\s+'
        $label = if ($words.Count -gt 0) { $words[0] } else { 'rule' }
        if ($label.Length -gt 12) { $label = $label.Substring(0,12) }
        "`"$label`""
    }) -join ', '
    $volBars = ($top10 | ForEach-Object { [long]$_.Alerts }) -join ', '
    $volMax = [long]1
    foreach ($r in $top10) { if ([long]$r.Alerts -gt $volMax) { $volMax = [long]$r.Alerts } }
    @"

## Top 10 noisy rules — alert volume

``````mermaid
---
config:
  xyChart:
    width: 1400
    height: 480
---
xychart-beta
    title "Top 10 alerting rules — alert count (last 30d)"
    x-axis [$volAxis]
    y-axis "Alerts" 0 --> $($volMax + ([math]::Ceiling($volMax * 0.1) + 1))
    bar [$volBars]
``````

Short labels chart-axis-only — full rule names in the table below. A single tall bar usually means a tuning candidate (over-broad threshold, missing suppression).
"@
} else { '' }

Write-Section '21-analytics-by-volume.md' (@"
$(Format-Banner -Title "Analytics Rules — by Alert Volume  (TOC 4.11.2)")

The 50 most-firing rules over the last 30 days, derived from ``SecurityAlert``. A rule firing thousands of alerts a day is usually either a misconfiguration (too-low threshold) or a high-fidelity signal — review and tune.
$volChartBlock

$(Format-Table -Items ($ruleVolumes | ForEach-Object { [pscustomobject]@{ Rule = $_.AlertName; Product = $_.ProductName; Severity = $_.AlertSeverity; Alerts = $_.Alerts } }) -Columns 'Rule','Product','Severity','Alerts')
"@)

# Section 22 — Microsoft security rules (TOC 4.11.3)
$msRules = @($rules | Where-Object {
    $kind = $_.kind
    $tn = $_.properties.alertRuleTemplateName
    ($tn -and ($tn -match '^[a-f0-9-]{36}$')) -or ($kind -in @('Fusion','MicrosoftSecurityIncidentCreation','MLBehaviorAnalytics','ThreatIntelligence'))
})
# Microsoft rules by severity for the headline pie.
$msSevCounts = @{ 'High' = 0; 'Medium' = 0; 'Low' = 0; 'Informational' = 0 }
foreach ($r in $msRules) {
    $sev = if ($r.properties.severity) { [string]$r.properties.severity } else { 'Unknown' }
    if (-not $msSevCounts.ContainsKey($sev)) { $msSevCounts[$sev] = 0 }
    $msSevCounts[$sev]++
}
$msPieRows = $msSevCounts.GetEnumerator() | Where-Object { $_.Value -gt 0 } | Sort-Object Value -Descending | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}
$msChartBlock = if ($msRules.Count -gt 0) {
    @"

## Microsoft rules by severity

``````mermaid
pie showData title Microsoft-managed rules by severity
$($msPieRows -join [Environment]::NewLine)
``````

$($msRules.Count) Microsoft-managed rule(s). High-severity bias is the norm — these rules are pre-tuned by Microsoft.
"@
} else { '' }

Write-Section '22-analytics-microsoft-rules.md' (@"
$(Format-Banner -Title "Microsoft Security Rules  (TOC 4.11.3)")

Rules backed by a Microsoft template, or built-in Microsoft-managed kinds (Fusion, MicrosoftSecurityIncidentCreation, MLBehaviorAnalytics, ThreatIntelligence). These are not user-editable; tuning is via enable/disable and the per-rule incident-grouping config.
$msChartBlock

$(Format-Table -Items ($msRules | ForEach-Object { [pscustomobject]@{ Kind = $_.kind; Name = $_.properties.displayName; Severity = $_.properties.severity; Enabled = if ($_.properties.enabled) {'Yes'} else {'No'} } }) -Columns 'Kind','Name','Severity','Enabled')
"@)

# Section 23 — Modifications (TOC 4.11.4)
# Sort uses ISO-formatted strings — ISO 8601 sorts lexically in the same
# order as chronologically, so Format-DateUtc output preserves ordering.
$modifiedRows = $rules | ForEach-Object {
    $lm = $null
    if ($_.properties -and ($_.properties.PSObject.Properties.Name -contains 'lastModifiedUtc')) { $lm = $_.properties.lastModifiedUtc }
    [pscustomobject]@{
        Name = $_.properties.displayName
        Kind = $_.kind
        LastModified = Format-DateUtc $lm
        Enabled = if ($_.properties.enabled) {'Yes'} else {'No'}
    }
} | Where-Object { $_.LastModified } | Sort-Object -Property LastModified -Descending | Select-Object -First 50
# Modifications-per-month bar over the last 12 months.
$monthBuckets = [ordered]@{}
$now = (Get-Date).ToUniversalTime()
for ($i = 11; $i -ge 0; $i--) {
    $m = $now.AddMonths(-$i)
    $key = $m.ToString('yyyy-MM', [System.Globalization.CultureInfo]::InvariantCulture)
    $monthBuckets[$key] = 0
}
foreach ($r in $rules) {
    $lm = if ($r.properties -and ($r.properties.PSObject.Properties.Name -contains 'lastModifiedUtc')) { $r.properties.lastModifiedUtc } else { $null }
    if (-not $lm) { continue }
    $parsed = [datetime]::MinValue
    if ($lm -is [datetime]) { $parsed = $lm }
    elseif (-not [datetime]::TryParse([string]$lm, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { continue }
    $key = $parsed.ToUniversalTime().ToString('yyyy-MM', [System.Globalization.CultureInfo]::InvariantCulture)
    if ($monthBuckets.Contains($key)) { $monthBuckets[$key]++ }
}
$modAxis = ($monthBuckets.Keys | ForEach-Object { "`"$($_.Substring(5,2))`"" }) -join ', '
$modBars = ($monthBuckets.Values) -join ', '
$modMax = 1
foreach ($v in $monthBuckets.Values) { if ($v -gt $modMax) { $modMax = $v } }

Write-Section '23-analytics-modifications.md' (@"
$(Format-Banner -Title "Analytics Rules — Recent Modifications  (TOC 4.11.4)")

## Modifications per month (last 12 months)

``````mermaid
xychart-beta
    title "Rule modifications per month — last 12 months"
    x-axis [$modAxis]
    y-axis "Modifications" 0 --> $($modMax + 1)
    bar [$modBars]
``````

Each bar is one calendar month (MM). Tempo reveals release cadence — sustained months at zero suggest abandoned content; periodic spikes usually align with vendor content-pack updates.

The 50 most recently modified rules. Cross-reference with [Test-SentinelRuleDrift.ps1](../../Tools/Test-SentinelRuleDrift.ps1) — a recent modification on a rule that has a Content Hub template or repo YAML source-of-truth indicates portal drift.

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
# Top solutions by rule count (top 8 + Other) for the headline pie.
$solCounts = @{}
foreach ($r in $bySolution) {
    $s = if ($r.Solution) { [string]$r.Solution } else { 'Unknown' }
    if (-not $solCounts.ContainsKey($s)) { $solCounts[$s] = 0 }
    $solCounts[$s]++
}
$topSols = $solCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8
$otherSolCount = 0
$counted = 0
foreach ($e in $solCounts.GetEnumerator()) { $counted += $e.Value }
$top8Sum = ($topSols | ForEach-Object { $_.Value } | Measure-Object -Sum).Sum
$otherSolCount = $counted - $top8Sum

$solPieRows = $topSols | ForEach-Object { "    `"$($_.Key)`" : $($_.Value)" }
if ($otherSolCount -gt 0) { $solPieRows += "    `"Other`" : $otherSolCount" }

Write-Section '24-analytics-by-solution.md' (@"
$(Format-Banner -Title "Analytics Rules — by Content Solution  (TOC 4.11.5)")

## Top contributing solutions

``````mermaid
pie showData title Analytics rules by Content Hub solution (top 8)
$($solPieRows -join [Environment]::NewLine)
``````

$($solCounts.Count) distinct solution(s) contributing $counted total rule(s). A heavy long-tail "(custom or unmapped)" slice usually means repo-deployed content not registered against any Content Hub solution.

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
# Pie of rows per UEBA table when there's something to chart.
$uebaPiePresenceBlock = if ($uebaPresenceRows.Count -gt 0 -and $uebaTotalRows -gt 0) {
    $uebaPieRows = $uebaPresenceRows | Where-Object { $_.Rows12d -gt 0 } | ForEach-Object {
        "    `"$($_.Table)`" : $([long]$_.Rows12d)"
    }
    @"

## UEBA table activity (last 12d)

``````mermaid
pie showData title UEBA rows by table (last 12 days)
$($uebaPieRows -join [Environment]::NewLine)
``````

A workspace producing data in BehaviorAnalytics + IdentityInfo + UserPeerAnalytics has the full UEBA pipeline active. A single-table dominance suggests one anchor source feeding the rest.
"@
} else { '' }

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
$uebaPiePresenceBlock$uebaPresenceBlock
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
# Pie of TI sources (top 6 + Other).
$tiPieBlock = if ($tiRows -and ($tiRows | Measure-Object -Property IndicatorCount -Sum).Sum -gt 0) {
    $top6Sources = @($tiRows) | Select-Object -First 6
    $tiPieRows = $top6Sources | ForEach-Object {
        "    `"$($_.SourceSystem)`" : $([long]$_.IndicatorCount)"
    }
    @"

## Indicator distribution by source

``````mermaid
pie showData title TI indicators by source
$($tiPieRows -join [Environment]::NewLine)
``````
"@
} else { '' }

Write-Section '27-threat-intelligence.md' (@"
$(Format-Banner -Title "Threat Intelligence  (TOC 4.17)")

Indicator counts and most-recent ingestion timestamp by source, last 30 days. Indicator detail is intentionally NOT exported to keep the report aggregate-only.

$tiHeadline
$tiPieBlock

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
# `properties.ruleType`, `properties.ruleDefinition.query`,
# `properties.ruleDefinition.binSize`, `properties.ruleDefinition.timeSelector`,
# `properties.ruleDefinition.destinationTable`, `properties.isActive`,
# `properties.statusCode`. The previous renderer included a `BinDelay` column
# that doesn't exist in the API response (always-empty). `isActive` and
# `statusCode` ARE present and signal whether the rule is actually running —
# the first rule on stl-sec-siem-law has isActive=false + status=DataPlaneError,
# evidence of a broken rule that the old shape never surfaced. Field names
# round-trip through ConvertFrom-Json as camelCase; PowerShell's PSObject
# property access is case-insensitive so the old PascalCase access "worked"
# accidentally for the fields that happened to exist.
$summaryRules = Read-RawArray 'summary-rules.json'
$summaryRows = $summaryRules | ForEach-Object {
    $props = $_.properties
    $isActive = if ($props.PSObject.Properties.Name -contains 'isActive') { $props.isActive } else { $null }
    $status   = if ($props.PSObject.Properties.Name -contains 'statusCode') { [string]$props.statusCode } else { '' }
    [pscustomobject]@{
        Name             = $_.name
        RuleType         = $props.ruleType
        DestinationTable = $props.ruleDefinition.destinationTable
        BinSize          = $props.ruleDefinition.binSize
        TimeSelector     = $props.ruleDefinition.timeSelector
        Active           = if ($null -eq $isActive) { '?' } elseif ($isActive) { 'Yes' } else { 'No' }
        Status           = if ($status) { $status } else { 'Ok' }
    }
}
$brokenSummary = @($summaryRows | Where-Object { $_.Active -eq 'No' -or $_.Status -ne 'Ok' })
$summaryWarning = if ($brokenSummary.Count -gt 0) {
    "`n> **$($brokenSummary.Count) summary rule(s) are inactive or in error.** Inspect the `Status` column — `DataPlaneError` typically means the underlying source table is missing or the query failed at last execution.`n"
} else { '' }
# Active vs Errored pie (only when there's something to chart).
$summaryActiveCount = @($summaryRows | Where-Object { $_.Active -eq 'Yes' -and $_.Status -eq 'Ok' }).Count
$summaryBrokenCount = @($summaryRows | Where-Object { $_.Active -ne 'Yes' -or $_.Status -ne 'Ok' }).Count
$summaryChartBlock = if ($summaryRows.Count -gt 0) {
    @"

## Health

``````mermaid
pie showData title Summary rules — health
    "Active & Ok" : $summaryActiveCount
    "Inactive or errored" : $summaryBrokenCount
``````
"@
} else { '' }

Write-Section '38-summary-rules.md' (@"
$(Format-Banner -Title "Summary Rules  (TOC 4.3.5)")

Summary rules pre-aggregate high-volume tables on a schedule into a derived table. They cut query cost on noisy data.
$summaryWarning$summaryChartBlock

$(Format-Table -Items $summaryRows -Columns 'Name','RuleType','DestinationTable','BinSize','TimeSelector','Active','Status')

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
        LastSeen  = Format-DateUtc $_.LastHeartbeat
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
# Chart inputs. When the total agent count is < 3 the renderer skips the
# chart entirely — 1-vs-0 splits are visually meaningless. Otherwise emit
# a grouped bar with AMA and MMA per machine type.
$totalAgents = 0
foreach ($r in $migrationRows) { $totalAgents += [int]$r.MachineCount }
$agentChartBlock = if ($totalAgents -ge 3 -and $migrationRows.Count -gt 0) {
    $mtAxis = ($migrationRows | ForEach-Object { "`"$($_.MachineType)`"" }) -join ', '
    $amaArr = ($migrationRows | ForEach-Object { [int]$_.AMACount }) -join ', '
    $mmaArr = ($migrationRows | ForEach-Object { [int]$_.MMACount }) -join ', '
    $yMax = 1
    foreach ($r in $migrationRows) {
        $t = [int]$r.AMACount + [int]$r.MMACount
        if ($t -gt $yMax) { $yMax = $t }
    }
    @"

``````mermaid
xychart-beta
    title "Agent fleet — AMA vs MMA per machine type"
    x-axis [$mtAxis]
    y-axis "Machines" 0 --> $($yMax + 1)
    bar [$amaArr]
    bar [$mmaArr]
``````

Two bars per machine type — AMA first, MMA second. A workspace mid-migration shows MMA bars sitting alongside AMA; a fully-migrated workspace has zero MMA bars across the board.
"@
} else {
    "`n> **Agent migration:** $totalAgents agent(s) heartbeating; chart suppressed because the count is too small for a meaningful visual. The migration-status table below carries the per-machine detail."
}

Write-Section '87-azure-monitor-agents.md' (@"
$(Format-Banner -Title "Azure Monitor Agents  (TOC 4.5)")

Agents heartbeating into the workspace over the last 7 days, derived from the ``Heartbeat`` table. Each row is a distinct ``SourceComputerId``.
$agentChartBlock

$(Format-Table -Items $agentRows -Columns 'Computer','OS','Version','Resource','LastSeen')

## AMA vs MMA migration status

Per-machine-type breakdown of agent migration progress. ``Direct Agent`` counts the legacy MMA; ``Azure Monitor Agent`` counts the modern AMA. Migration state is **Completed** when only AMA records exist for a category, **In Progress** when both exist, and **Not Started** otherwise.

$(Format-Table -Items $migrationRows -Columns 'MachineType','MachineCount','MMACount','AMACount','MigrationStatus')

[Migrate from Log Analytics agent to Azure Monitor agent (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-migration)
[Azure Monitor Agent overview (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/agents/agents-overview)
"@)

# ---------------------------------------------------------------------------
# Section 88 — Microsoft Sentinel Data Lake
# ---------------------------------------------------------------------------
# Lake-tier tables surfaced from $workspaceTables (those on plan='DataLake').
# Migration candidates surfaced from $cost.AllTablesByCost — high-volume
# tables on the Analytics plan are typical Lake-migration targets for
# cost optimisation. The enrollment signals were computed in section 83's
# block ($hasDataLake / $unifiedBilling / $sentinelDataLake / $plansInUse)
# so this block consumes them rather than recomputing.

$dlTables = @($workspaceTables | Where-Object { $_.properties.plan -eq 'DataLake' })
$dlTableRows = $dlTables | ForEach-Object {
    [pscustomobject]@{
        Table            = $_.name
        RetentionDays    = $_.properties.retentionInDays
        TotalRetention   = $_.properties.totalRetentionInDays
    }
}

# Tier-distribution stats. When Lake is enrolled every Analytics-plan
# table is auto-mirrored to the Lake at the same retention. A table
# that has totalRetentionInDays > retentionInDays is also storing
# additional time in the Lake beyond the Analytics period. Tables on
# plan = 'DataLake' route exclusively to the Lake (no Analytics tier).
# Catalogue-only tables (zero ingest in the workspace) are excluded
# from the tier-distribution chart because they don't contribute to
# the Lake state.
$tierStats = @{ AnalyticsOnly = 0; MirroredOnly = 0; MirroredExtended = 0; LakeOnly = 0 }
$retentionRows = New-Object System.Collections.Generic.List[object]
foreach ($t in $operationalTables) {
    $plan = [string]$t.properties.plan
    $r  = [int]($t.properties.retentionInDays   | ForEach-Object { if ($_) { $_ } else { 0 } })
    $tr = [int]($t.properties.totalRetentionInDays | ForEach-Object { if ($_) { $_ } else { 0 } })
    $lakeOnlyDays = if ($tr -gt $r) { $tr - $r } else { 0 }

    $tierCategory = if ($plan -eq 'DataLake') {
        'LakeOnly'
    } elseif ($hasDataLake -and $lakeOnlyDays -gt 0) {
        'MirroredExtended'
    } elseif ($hasDataLake) {
        'MirroredOnly'
    } else {
        'AnalyticsOnly'
    }
    $tierStats[$tierCategory]++

    if ($lakeOnlyDays -gt 0 -or $plan -eq 'DataLake') {
        $retentionRows.Add([pscustomobject]@{
            Table          = $t.name
            Plan           = $plan
            AnalyticsDays  = $r
            LakeOnlyDays   = $lakeOnlyDays
            TotalDays      = $tr
        })
    }
}

# Asset-data system tables that Sentinel Data Lake auto-ingests on
# tenant onboarding. Detecting these by name confirms the Lake's
# Microsoft Entra / Microsoft 365 / Azure Resource Graph asset
# pipelines are actually populating the workspace.
$assetTableNames = @(
    @{ Pattern = '^IdentityInfo$';                 Family = 'Microsoft Entra (identity)' },
    @{ Pattern = '^EntityGraph';                   Family = 'Microsoft Sentinel graph (entities)' },
    @{ Pattern = '^Asset';                         Family = 'Azure Resource Graph (assets)' },
    @{ Pattern = '^Office(SharePoint|Exchange|Teams)';  Family = 'Microsoft 365 (activity)' },
    @{ Pattern = '^Behavior(Analytics)?$';         Family = 'Microsoft Sentinel UEBA (asset enrichment)' }
)
$assetDataRows = New-Object System.Collections.Generic.List[object]
foreach ($t in $workspaceTables) {
    foreach ($m in $assetTableNames) {
        if ($t.name -match $m.Pattern) {
            $hasData = $populatedTableNames.ContainsKey($t.name)
            $assetDataRows.Add([pscustomobject]@{
                Table       = $t.name
                Family      = $m.Family
                IngestState = if ($hasData) { 'Receiving data' } else { 'Defined, no data' }
                Retention   = $t.properties.retentionInDays
            })
            break
        }
    }
}

# Lake billing meters reference. Static per Microsoft Sentinel
# pricing docs — surfaces all five Lake-specific cost surfaces so
# reviewers know what to expect on the bill when Lake is in use.
$lakeBillingMeters = @(
    [pscustomobject]@{ Meter = 'Data lake ingestion';      ChargedPer = 'GB';            AppliesTo = 'Data ingested into tables with retention set to Lake-only. Mirrored-to-Lake ingest is not charged.' }
    [pscustomobject]@{ Meter = 'Data processing';          ChargedPer = 'GB';            AppliesTo = 'Transformations (redaction, splitting, filtering, normalization) on Lake-only ingest. Not charged for mirrored ingest.' }
    [pscustomobject]@{ Meter = 'Data lake storage';        ChargedPer = 'GB · month';    AppliesTo = 'Data remaining in Lake AFTER the analytics-tier retention period ends. Compression 6:1 applied before billing.' }
    [pscustomobject]@{ Meter = 'Data lake query';          ChargedPer = 'GB scanned';    AppliesTo = 'KQL queries and KQL jobs over Lake-tier data. Charged per uncompressed GB scanned.' }
    [pscustomobject]@{ Meter = 'Advanced data insights';   ChargedPer = 'compute hour';  AppliesTo = 'Jupyter notebook sessions, scheduled notebook jobs, custom graph build/query. Per vCore-hour (pools of 12, 32, or 80 vCores).' }
)

# Lake-derived capabilities — features that unlock automatically when
# the tenant onboards to Lake. Helps the reader connect "Lake is
# enrolled" to the operational surfaces they'd see in Defender portal.
$lakeCapabilities = @(
    [pscustomobject]@{ Capability = 'KQL exploration over Lake';          Surface = 'Defender portal · Investigate · KQL editor';   Billing = 'Data lake query (GB scanned)' }
    [pscustomobject]@{ Capability = 'KQL jobs (promote Lake → Analytics)'; Surface = 'Defender portal · Microsoft Sentinel · Jobs'; Billing = 'Data lake query (job execution)' }
    [pscustomobject]@{ Capability = 'Jupyter notebooks';                   Surface = 'Defender portal · Microsoft Sentinel · Notebooks · VS Code extension'; Billing = 'Advanced data insights (compute hour)' }
    [pscustomobject]@{ Capability = 'Microsoft Sentinel graph (embedded)'; Surface = 'Defender portal hunting graph · Blast radius'; Billing = 'No additional charge for embedded graphs' }
    [pscustomobject]@{ Capability = 'Custom graphs';                       Surface = 'Notebooks · Graph Query APIs · MCP graph tools'; Billing = 'Advanced data insights (compute hour, graph build/query)' }
    [pscustomobject]@{ Capability = 'MCP server (data exploration)';       Surface = 'Sentinel MCP server (AI agents)';              Billing = 'No charge for the server; tools invoke Lake-query meter' }
    [pscustomobject]@{ Capability = 'MCP entity analyzer';                 Surface = 'Sentinel MCP server';                           Billing = 'Security Compute Units (SCU) + Lake-query meter' }
    [pscustomobject]@{ Capability = 'Auto-ingested asset data';            Surface = 'System tables (Entra, M365, Azure Resource Graph)'; Billing = 'Ingestion + storage charged like any Lake table' }
    [pscustomobject]@{ Capability = '12-year affordable retention';         Surface = 'Manage data tiers in Defender portal';          Billing = 'Lake storage (per GB-month, 6:1 compression)' }
)

# Top-by-Lake-only-retention chart inputs (top 10 tables paying for
# extended Lake retention beyond Analytics). xychart-beta-friendly
# axis labels truncated to 14 chars.
$topRetention = @($retentionRows | Sort-Object LakeOnlyDays -Descending | Select-Object -First 10)
$retAxis  = ($topRetention | ForEach-Object {
    $n = $_.Table
    $s = if ($n.Length -gt 14) { $n.Substring(0,14) } else { $n }
    "`"$s`""
}) -join ', '
$retLakeBars = ($topRetention | ForEach-Object { $_.LakeOnlyDays }) -join ', '
$retAnaBars  = ($topRetention | ForEach-Object { $_.AnalyticsDays }) -join ', '
$retYmax = 1
foreach ($r in $topRetention) { $sum = $r.AnalyticsDays + $r.LakeOnlyDays; if ($sum -gt $retYmax) { $retYmax = $sum } }

# Lake-side ingest + cost split from $cost.ByPlan. Defensive lookups because
# older cost captures may not include DataLake.
$lakeGb = 0.0
$lakeCost = 0.0
$analyticsGb = 0.0
$analyticsCost = 0.0
if ($cost -and $cost.ByPlan) {
    if ($cost.ByPlan.PSObject.Properties.Name -contains 'DataLake') {
        $lakeGb   = [double]$cost.ByPlan.DataLake.Gb30d
        $lakeCost = [double]$cost.ByPlan.DataLake.MonthlyCost
    }
    if ($cost.ByPlan.PSObject.Properties.Name -contains 'Analytics') {
        $analyticsGb   = [double]$cost.ByPlan.Analytics.Gb30d
        $analyticsCost = [double]$cost.ByPlan.Analytics.MonthlyCost
    }
}

# Migration candidates: Analytics-plan tables with ≥0.5 GB/30d are typical
# Lake-tier candidates, particularly verbose Defender XDR advanced hunting
# tables (Device*, Email*) and verbose security logs that don't drive
# real-time detection. Cap to the top 10 to keep the table readable.
$dlCandidateRows = @()
if ($cost -and $cost.PSObject.Properties.Name -contains 'AllTablesByCost' -and $cost.AllTablesByCost) {
    $dlCandidateRows = @($cost.AllTablesByCost |
        Where-Object { $_.Plan -eq 'Analytics' -and [double]$_.Gb30d -ge 0.5 } |
        Select-Object -First 10 |
        ForEach-Object {
            [pscustomobject]@{
                Table         = $_.Table
                Gb30d         = $_.Gb30d
                MonthlyCost   = $_.MonthlyCost
                Recommendation = 'Consider DataLake plan if rule queries are infrequent'
            }
        })
}

# Headline narrative — one of four states based on the captured signals.
$lakeHeadline = if ($hasDataLake -and $dlTables.Count -gt 0) {
    "**Sentinel Data Lake is enrolled and active.** $($dlTables.Count) table(s) route to the Lake at the DataLake-rate ingestion meter (~$([math]::Round($lakeGb, 2)) GB / 30d, est. `$$([math]::Round($lakeCost, 2)) / month). Analytics-plan tables continue to bill at the higher Sentinel-rate meter."
} elseif ($hasDataLake -and $dlTables.Count -eq 0) {
    "**Sentinel Data Lake is enrolled on this workspace** (``features.unifiedSentinelBillingOnly = true``), but no tables currently route to the Lake. All ingest is on the Analytics plan billed at the full Sentinel-rate meter. See *Migration candidates* below for verbose tables that could move to the Lake to reduce monthly cost — the Lake-rate per-GB ingestion meter is typically a fraction of the Sentinel-rate."
} elseif (-not $hasDataLake -and $analyticsGb -gt 30) {
    "**Sentinel Data Lake is not enrolled.** This workspace ingests $([math]::Round($analyticsGb, 1)) GB / 30d on the Analytics plan at the full Sentinel-rate meter. For high-volume workspaces, onboarding to the unified Sentinel/Defender billing model unlocks the DataLake plan, which routes verbose, low-query tables (Defender XDR advanced hunting, raw firewall, EDR telemetry) to a cheaper ingestion tier with longer affordable retention."
} else {
    "**Sentinel Data Lake is not enrolled.** This workspace is on the legacy per-GB billing model with no Lake-tier ingest. Lake becomes cost-relevant once steady-state ingest exceeds a few hundred GB/month, particularly for verbose Defender XDR tables; below that the per-GB Analytics rate is competitive."
}

# Enrollment-signal table — primary signal is the
# Microsoft.SentinelPlatformServices resource; the workspace billing
# flag and table-plan signals are supporting checks.
$lakeResource = @($sentinelDataLake) | Select-Object -First 1
$lakeSignals = @(
    [pscustomobject]@{
        Signal      = 'Microsoft.SentinelPlatformServices/sentinelPlatformServices'
        Value       = if ($lakeResource) { "$($lakeResource.name) ($($lakeResource.location))" } else { '(not found)' }
        Interpretation = if ($lakeResource) { "Lake provisioned at tenant scope, region '$($lakeResource.location)', billing subscription '$($lakeResource.subscriptionId)' / RG '$($lakeResource.resourceGroup)'" } else { 'No Sentinel Data Lake resource found in the visible subscriptions — tenant is not onboarded to Lake' }
    },
    [pscustomobject]@{
        Signal      = 'workspace.properties.features.unifiedSentinelBillingOnly'
        Value       = if ($unifiedBilling) { 'true' } else { 'false / absent' }
        Interpretation = if ($unifiedBilling) { 'Workspace on unified Sentinel/Defender billing — eligible for Lake' } else { 'Workspace on legacy per-GB billing — not on the unified model' }
    },
    [pscustomobject]@{
        Signal      = "Tables on plan='DataLake'"
        Value       = "$($dlTables.Count) table(s)"
        Interpretation = if ($dlTables.Count -gt 0) { 'Data actively routed to Lake-only tier' } else { 'No tables route to Lake-only tier (mirrored data still flows when Lake is enrolled)' }
    }
)

# Lake resource detail block, only rendered when the platform-services
# resource exists. Surfaces the audit trail (createdBy/At) so reviewers
# can answer "when was this onboarded and by whom" from the doc.
$lakeResourceBlock = if ($lakeResource) {
    $createdAt = if ($lakeResource.systemData.createdAt) { Format-DateUtc $lakeResource.systemData.createdAt } else { '_(unknown)_' }
    $modifiedAt = if ($lakeResource.systemData.lastModifiedAt) { Format-DateUtc $lakeResource.systemData.lastModifiedAt } else { '_(unknown)_' }
    @"

## Lake resource detail

| Property | Value |
|---|---|
| Resource ID | ``$($lakeResource.id)`` |
| Resource name | ``$($lakeResource.name)`` |
| Region | ``$($lakeResource.location)`` |
| Subscription | ``$($lakeResource.subscriptionId)`` |
| Resource group | ``$($lakeResource.resourceGroup)`` |
| Provisioning state | ``$($lakeResource.properties.provisioningState)`` |
| System-assigned MI principal | ``$($lakeResource.identity.principalId)`` |
| Onboarded by | ``$($lakeResource.systemData.createdBy)`` |
| Onboarded at | $createdAt |
| Last modified | $modifiedAt |

The Sentinel Data Lake is a tenant-wide capability but it's provisioned as a single resource pinned to one subscription / resource group / region. Workspaces in **other regions** still mirror to the Lake — see [Onboard to Microsoft Sentinel data lake (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-onboarding) for the cross-region behaviour.
"@
} else { '' }

# Tier-distribution pie chart inputs.
$tierPieRows = @()
if ($tierStats.AnalyticsOnly    -gt 0) { $tierPieRows += "    `"Analytics only`" : $($tierStats.AnalyticsOnly)" }
if ($tierStats.MirroredOnly     -gt 0) { $tierPieRows += "    `"Analytics + Lake mirror`" : $($tierStats.MirroredOnly)" }
if ($tierStats.MirroredExtended -gt 0) { $tierPieRows += "    `"Analytics + Lake extended`" : $($tierStats.MirroredExtended)" }
if ($tierStats.LakeOnly         -gt 0) { $tierPieRows += "    `"Lake only`" : $($tierStats.LakeOnly)" }

$tierChartBlock = if ($tierPieRows.Count -ge 2) { @"

## Tier distribution

Pie of every operational table (a table that has received data in the last 90 days, plus all CustomLog tables) by tier configuration. *Analytics + Lake mirror* is the default state on a Lake-enrolled tenant — every Analytics-plan table is auto-mirrored to the Lake at the same retention at no extra cost. *Analytics + Lake extended* means the table also stores beyond the Analytics retention in the Lake (Lake-storage meter applies). *Lake only* means the table bypasses the Analytics tier entirely (Lake-ingestion meter applies; no real-time analytics or detection rules).

``````mermaid
pie showData title Operational tables by tier configuration
$($tierPieRows -join [Environment]::NewLine)
``````
"@ } else { '' }

# Retention split bar chart — only render when at least one table has
# extended retention (otherwise the chart would be empty).
$retentionChartBlock = if ($topRetention.Count -gt 0) { @"

## Retention split — top tables by extended Lake retention

Top 10 tables paying for retention beyond the Analytics-tier interactive period. Each bar is the table's *Lake-only* retention days — the portion of total retention that bills against the Lake-storage meter (per GB · month, with 6:1 compression). Tables with the same Analytics retention as total retention don't appear here because they sit entirely within the Analytics retention window and incur no Lake-storage charge.

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
    y-axis "Days" 0 --> $($retYmax + 30)
    bar [$retLakeBars]
``````

$(Format-Table -Items $topRetention -Columns 'Table','Plan','AnalyticsDays','LakeOnlyDays','TotalDays')
"@ } else { '' }

# Lake architecture flowchart — static visual showing the three tiers
# and the ingestion / mirror / promote / query paths. Always rendered
# when Lake is enrolled because it's instructional rather than
# data-driven.
$lakeArchitectureBlock = if ($hasDataLake) { @"

## Lake architecture

How data flows once the tenant is onboarded to the Lake. Source → Analytics tier → automatic mirror to Lake → optional KQL job to promote summarised data back to Analytics for detection. Notebooks and graph operate against the Lake tier directly. Lake-only tables skip the Analytics tier entirely.

``````mermaid
flowchart LR
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
"@ } else { '' }

# Lake-tier tables block — only when there are explicit Lake-only
# tables on the workspace.
$lakeTablesBlock = if ($dlTableRows.Count -gt 0) { @"

## Lake-only tables

Tables explicitly configured to bypass the Analytics tier and route exclusively to the Lake. These tables bill against the **Data lake ingestion** + **Data processing** meters at a lower per-GB rate than Analytics, but **analytics rules cannot query them in real time**. Use the *Manage table* page in the Defender portal to switch a table's tier.

$(Format-Table -Items $dlTableRows -Columns 'Table','RetentionDays','TotalRetention')
"@ } else { @"

## Lake-only tables

_No tables currently route to the Lake-only tier on this workspace._ When Lake is enrolled, the default behaviour is to mirror all Analytics-tier tables to the Lake at the same retention — see the tier distribution above. *Lake-only* requires explicitly switching a table's tier in **Defender portal → Microsoft Sentinel → Data management → Tables**.
"@ }

# Asset-data block — present when at least one asset-family table is
# detected. Helps confirm the Lake's auto-onboarded system tables
# (Entra, M365, Azure Resource Graph) are flowing.
$assetDataBlock = if ($assetDataRows.Count -gt 0) { @"

## Auto-ingested asset data

Sentinel Data Lake automatically creates and ingests asset-data tables on tenant onboarding (Microsoft Entra identity records, Microsoft 365 activity, Azure Resource Graph asset snapshots, plus UEBA enrichment). These tables appear in the Lake exploration UI as *System tables*. Receiving-data status confirms each pipeline is active.

$(Format-Table -Items $assetDataRows -Columns 'Table','Family','IngestState','Retention')
"@ } else { '' }

$lakeBody = @"
$(Format-Banner -Title "Microsoft Sentinel Data Lake")

$lakeHeadline

## Enrollment signals

The documenter's primary signal is the **Microsoft.SentinelPlatformServices/sentinelPlatformServices** resource — captured via Resource Graph across every visible subscription. Presence of this resource means the tenant is onboarded to Sentinel Data Lake; absence means the tenant is not. The other two rows are supporting checks: the workspace-level billing flag and the table-plan routing state.

$(Format-Table -Items $lakeSignals -Columns 'Signal','Value','Interpretation')
$lakeResourceBlock
$lakeArchitectureBlock
$tierChartBlock
$retentionChartBlock
$lakeTablesBlock
$assetDataBlock

## Cost split — Analytics vs Lake (last 30d)

| Plan | Ingest (GB) | Estimated monthly cost |
|---|---:|---:|
| Analytics | $([math]::Round($analyticsGb, 2)) | `$$([math]::Round($analyticsCost, 2)) |
| DataLake  | $([math]::Round($lakeGb, 2)) | `$$([math]::Round($lakeCost, 2)) |

## Lake billing meters

When Lake is enrolled, five new meters can appear on the bill. The table below documents what each one charges for so a billing surprise can be traced to its source.

$(Format-Table -Items $lakeBillingMeters -Columns 'Meter','ChargedPer','AppliesTo')

> Notes
>
> - **Mirrored data is free** — mirroring an Analytics-plan table to the Lake at the same retention incurs no Lake-storage charge. Extended Lake-only retention beyond the Analytics period is where Lake-storage starts billing.
> - **Compression is 6:1** — Lake-storage bills the compressed footprint. 600 GB of raw logs is billed as 100 GB of compressed Lake storage.
> - **Long-term retention, search-jobs, and auxiliary-logs meters fold into the Lake meters** once the workspace is onboarded — see the onboarding doc for the exact mapping.

## Lake-derived capabilities

Features that unlock when the tenant is onboarded to the Lake. Each surface points at where it lives in the portal plus which Lake meter it bills against.

$(Format-Table -Items $lakeCapabilities -Columns 'Capability','Surface','Billing')

## Migration candidates

Top Analytics-plan tables (≥0.5 GB/30d) that are typical Lake-tier candidates — high ingest volume, low real-time-query frequency. Defender XDR advanced hunting surfaces (Device*, Email*, Url*) and raw EDR/firewall telemetry are the usual wins. Confirm a table's analytics-rule references first before migrating — a rule whose query joins against the candidate table will start failing if the table is moved without re-pointing the query.

$(if ($dlCandidateRows.Count -gt 0) { Format-Table -Items $dlCandidateRows -Columns 'Table','Gb30d','MonthlyCost','Recommendation' } else { '_No Analytics-plan tables above the 0.5 GB / 30d threshold — Lake migration is not currently cost-justified on this workspace._' })

## When to enroll

- **Sustained ingest > 500 GB/month** of verbose / low-query telemetry (Defender XDR raw events, firewall syslog, EDR process telemetry).
- **Long-tail investigations need affordable retention** — Lake supports up to 12 years at storage rates with 6:1 compression, vs Analytics' high per-GB interactive retention rate.
- **Already onboarded to the Defender unified SecOps portal** — Lake is the implicit storage tier for unified-portal workflows (graph, MCP, notebooks).
- **Compliance retention requirements** — regulatory retention obligations (SOX, GDPR audit, PCI-DSS) often demand multi-year retention that's prohibitively expensive on Analytics-tier storage.

## When to stay on the legacy model

- **Ingest < ~100 GB/month** — Analytics-plan per-GB rate is competitive at low volumes and avoids the operational complexity of plan-routing.
- **Every table queries in near-real-time** — the Lake's higher query latency makes it a poor fit for detection-rule-heavy workloads.
- **CMK encryption is required** — Sentinel Data Lake does **not** support Customer-Managed Keys; workspaces using CMK cannot use Lake experiences.
- **Compliance / contract requires PerGB2018 billing** — some enterprise agreements lock to legacy meters that don't include the Lake meter set.

[Microsoft Sentinel Data Lake overview (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-overview)
[Onboard to Microsoft Sentinel data lake (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-onboarding)
[Data lake tier billing (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/billing#data-lake-tier)
[Manage data tiers and retention (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/manage-data-overview)
[KQL and the Microsoft Sentinel data lake (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/kql-overview)
[KQL jobs (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/kql-jobs)
[Jupyter notebooks in the Sentinel data lake (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/notebooks-overview)
[Sentinel graph (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-graph-overview)
"@
Write-Section '88-sentinel-data-lake.md' $lakeBody

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
$refSrc = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Docs/Tools/Documenter/Documenter-References.md'
if (Test-Path $refSrc) {
    Copy-Item -Path $refSrc -Destination (Join-Path $OutputRoot '99-references.md') -Force
    Write-Information "  ↳ copied 99-references.md"
}

# ---------------------------------------------------------------------------
# Index
# ---------------------------------------------------------------------------
$indexBody = @"
# $WorkspaceName — Sentinel Documentation Index

Generated $(Format-DateUtc $run.StartedAtUtc) UTC by Sentinel Documenter v$($run.DocumenterVersion).

Sections are numbered to match the formal Sentinel Configuration TOC where applicable. Customer-narrative sections (architectural diagrams, SOC operational processes, the licensing inventory) are intentionally not auto-generated — supply those separately.

| Section | TOC | Description |
|---|---|---|
| [00-overview.md](00-overview.md) | — | Headline counts, top findings, cost summary |
| [01-live-snapshot.md](01-live-snapshot.md) | 1 | Workspace-at-a-glance — regenerates every pipeline run |
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
| [88-sentinel-data-lake.md](88-sentinel-data-lake.md) | — | Sentinel Data Lake enrollment, Lake-tier tables, migration candidates |
| [90-gap-analysis.md](90-gap-analysis.md) | — | Findings against MS Learn best practices |
| [96-references-microsoft.md](96-references-microsoft.md) | 6 | User-facing Microsoft references |
| [99-references.md](99-references.md) | — | Documenter's own API versions and modules |
"@
Write-Section 'index.md' $indexBody

Write-Information "✓ Renderer complete — output: $OutputRoot"
