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

# ---------------------------------------------------------------------------
# Section: 00-overview
# ---------------------------------------------------------------------------
$workspace          = Read-Raw 'workspace.json'
$run                = Read-Raw 'run-context.json'
$rules              = @(Read-Raw 'alert-rules.json')
$connectors         = @(Read-Raw 'data-connectors-classic.json')
$workbooksSaved     = @(Read-Raw 'workbooks-saved.json')
$dcrs               = @(Read-Raw 'dcrs.json')
$tablesWithData     = @(Read-Raw 'tables-with-data.json')
$workspaceTables    = @(Read-Raw 'workspace-tables.json')
$watchlists         = @(Read-Raw 'watchlists.json')
$autoRules          = @(Read-Raw 'automation-rules.json')
$gapFindings        = @(Read-Raw 'gap-analysis.json')
$cost               = Read-Raw 'cost-estimate.json'

$enabledRules = @($rules | Where-Object { $_.properties.enabled -eq $true })
$populatedTables = @($tablesWithData | Where-Object { [double]($_.BillableLast90d) -gt 0 })
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
| Tables with schema | $($workspaceTables.Count) |
| Tables with data (90d) | $($populatedTables.Count) |

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
$ccfDefs = @(Read-Raw 'data-connector-definitions.json')

$connectorRows = $connectors | ForEach-Object {
    [pscustomobject]@{
        Name  = $_.name
        Kind  = $_.kind
        State = ($_.properties.connectorUiConfig.connectivityCriterias) -as [string]
    }
}

$connectorBody = @"
$(Format-Banner -Title "Data Connectors")

## Classic connectors

$(Format-Table -Items $connectorRows -Columns 'Name','Kind','State')

## Codeless Connector Framework definitions

$(Format-Table -Items ($ccfDefs | ForEach-Object { [pscustomobject]@{ Name = $_.name; Kind = $_.properties.connectorUiConfig.connectorKind; Title = $_.properties.connectorUiConfig.title } }) -Columns 'Name','Kind','Title')

## Connector health (24h activity)

Cross-reference: [83-data-collection.md](83-data-collection.md) shows the DCRs each connector relies on; [81-table-plans-retention.md](81-table-plans-retention.md) shows whether their target tables have recent data.

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

$rulesBody = @"
$(Format-Banner -Title "Analytics Rules")

| Total | Enabled | Disabled |
|---:|---:|---:|
| $($rules.Count) | $($enabledRules.Count) | $($rules.Count - $enabledRules.Count) |

## All rules

$(Format-Table -Items $ruleRows -Columns 'Kind','Name','Severity','Enabled','Tactics')

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
    foreach ($t in @($r.properties.tactics)) {
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

$mitreBody = @"
$(Format-Banner -Title "MITRE ATT&CK Coverage Matrix")

Coverage is computed by counting **enabled** Sentinel detection rules whose ``tactics`` array references each ATT&CK tactic.

$(Format-Table -Items $mitreRows -Columns 'ID','Tactic','EnabledRules','Coverage')

[MITRE coverage in Sentinel (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/mitre-coverage)
"@

Write-Section '25-mitre-coverage.md' $mitreBody

# ---------------------------------------------------------------------------
# Section: 30 / 35 — hunting & parsers
# ---------------------------------------------------------------------------
$hunting = @(Read-Raw 'hunting-queries.json')
$parsers = @(Read-Raw 'parsers-functions.json')

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
$workbookTemplates = @(Read-Raw 'workbook-templates.json')
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
$playbooks = @(Read-Raw 'playbooks.json')
$miAssignments = @(Read-Raw 'rbac-playbook-mi.json')
$pbRows = $playbooks | ForEach-Object {
    $mi = $miAssignments | Where-Object { $_.Playbook -eq $_.Name } | Select-Object -First 1
    [pscustomobject]@{
        Name = $_.Name
        State = $_.State
        WorkspaceRoles = if ($mi) { ($mi.WorkspaceRoles -join ', ') } else { '' }
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

$contentPackages = @(Read-Raw 'content-packages.json')
$repos           = @(Read-Raw 'repositories.json')
$cpRows = $contentPackages | ForEach-Object {
    [pscustomobject]@{ Name = $_.properties.displayName; Version = $_.properties.version; Source = $_.properties.source.kind }
}
$repoRows = $repos | ForEach-Object {
    [pscustomobject]@{ Name = $_.properties.displayName; Type = $_.properties.repoType; Url = $_.properties.repository.url }
}
Write-Section '70-content-hub.md' (@"
$(Format-Banner -Title "Content Hub and Repositories")

## Solutions installed

$(Format-Table -Items $cpRows -Columns 'Name','Version','Source')

## Repositories

$(Format-Table -Items $repoRows -Columns 'Name','Type','Url')

[Sentinel solutions (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/sentinel-solutions)
"@)

# ---------------------------------------------------------------------------
# Section: 80 — workspace
# ---------------------------------------------------------------------------
$features = $workspace.properties.features
$wsBody = @"
$(Format-Banner -Title "Workspace Inventory")

## SKU and pricing

| Property | Value |
|---|---|
| SKU name | ``$($workspace.properties.sku.name)`` |
| Capacity reservation level | $(if ($workspace.properties.sku.capacityReservationLevel) { "$($workspace.properties.sku.capacityReservationLevel) GB/day" } else { '_(n/a)_' }) |
| Default retention | $($workspace.properties.retentionInDays) days |
| Daily cap | $(if ($workspace.properties.workspaceCapping.dailyQuotaGb -eq -1) { 'Unlimited (-1)' } else { "$($workspace.properties.workspaceCapping.dailyQuotaGb) GB" }) |

## Networking

| Property | Value |
|---|---|
| Public ingestion | ``$($workspace.properties.publicNetworkAccessForIngestion)`` |
| Public query | ``$($workspace.properties.publicNetworkAccessForQuery)`` |
| Replication enabled | $($workspace.properties.replication.enabled) |
| Replication location | ``$($workspace.properties.replication.location)`` |

## Feature flags

| Flag | Value |
|---|---|
| disableLocalAuth | $($features.disableLocalAuth) |
| enableLogAccessUsingOnlyResourcePermissions | $($features.enableLogAccessUsingOnlyResourcePermissions) |
| enableDataExport | $($features.enableDataExport) |
| immediatePurgeDataOn30Days | $($features.immediatePurgeDataOn30Days) |
| clusterResourceId | $(if ($features.clusterResourceId) { "Linked → see [82-dedicated-cluster.md](82-dedicated-cluster.md)" } else { '_(none)_' }) |

[Workspace design (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/logs/workspace-design) · [Manage access](https://learn.microsoft.com/azure/azure-monitor/logs/manage-access) · [Replication](https://learn.microsoft.com/azure/azure-monitor/logs/workspace-replication)
"@
Write-Section '80-workspace.md' $wsBody

# ---------------------------------------------------------------------------
# Section: 81 — table plans + retention
# ---------------------------------------------------------------------------
$tableSchemaByName = @{}
foreach ($t in $workspaceTables) { $tableSchemaByName[$t.name] = $t }

$tableRows = foreach ($t in $workspaceTables) {
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

$active   = @($tableRows | Where-Object { $_.Last24h })
$silent   = @($tableRows | Where-Object {
    -not $_.Last24h -and ($tablesWithData | Where-Object { $_.DataType -eq $_.Name -and [double]$_.BillableLast90d -gt 0 })
})
$orphans  = @($tableRows | Where-Object { -not $_.LastIngested -and $_.Type -in @('Microsoft','CustomLog') })

$gbByPlan = $tableRows | Group-Object Plan | ForEach-Object {
    [pscustomobject]@{
        Plan = $_.Name
        Tables = $_.Count
        Gb90d = [math]::Round(($_.Group | Measure-Object Gb90d -Sum).Sum, 2)
    }
}

$tablePlansBody = @"
$(Format-Banner -Title "Table Plans, Retention and Activity")

## Summary by plan

$(Format-Table -Items $gbByPlan -Columns 'Plan','Tables','Gb90d')

## All tables

$(Format-Table -Items ($tableRows | Sort-Object -Property Gb90d -Descending) -Columns 'Name','Plan','Interactive','Total','Archive','Type','Gb90d','Last24h','LastIngested')

## Active (received data in last 24h)

Total: **$($active.Count)** table(s).

## Silent (had data ever, none in last 7d)

Total: **$($silent.Count)** table(s) — likely connector breakage.

## Orphan (schema deployed, no data in 90d)

Total: **$($orphans.Count)** table(s) — delete candidates or never-onboarded sources.

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
$dces = @(Read-Raw 'dces.json')
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
$rbacWs = @(Read-Raw 'rbac-workspace.json')
$rbacRg = @(Read-Raw 'rbac-resourcegroup.json')

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
$rps        = @(Read-Raw 'resource-providers.json')
$locks      = @(Read-Raw 'subscription-locks.json')
$policies   = @(Read-Raw 'policy-assignments.json')

$rpRows = $rps | ForEach-Object { [pscustomobject]@{ Provider = $_.ProviderNamespace; State = $_.RegistrationState } }
$lockRows = $locks | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Level = $_.Properties.level; Notes = $_.Properties.notes } }
$polRows = $policies | ForEach-Object { [pscustomobject]@{ Name = $_.Properties.DisplayName; Scope = $_.Properties.Scope } }

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

| Section | Description |
|---|---|
| [00-overview.md](00-overview.md) | Headline counts, top findings, cost summary |
| [10-data-connectors.md](10-data-connectors.md) | Classic + CCF connectors |
| [20-analytics-rules.md](20-analytics-rules.md) | Every detection rule by kind |
| [25-mitre-coverage.md](25-mitre-coverage.md) | MITRE ATT&CK coverage matrix |
| [30-hunting-queries.md](30-hunting-queries.md) | Hunting queries |
| [35-parsers-functions.md](35-parsers-functions.md) | Parsers and functions |
| [40-workbooks.md](40-workbooks.md) | Saved workbooks + templates available |
| [50-watchlists.md](50-watchlists.md) | Watchlists |
| [60-automation-rules-playbooks.md](60-automation-rules-playbooks.md) | Automation rules + playbooks + MI grants |
| [70-content-hub.md](70-content-hub.md) | Solutions installed + repositories |
| [80-workspace.md](80-workspace.md) | SKU, retention, networking, feature flags |
| [81-table-plans-retention.md](81-table-plans-retention.md) | Per-table plan, retention and activity |
| [82-dedicated-cluster.md](82-dedicated-cluster.md) | Dedicated cluster, CMK, AZ |
| [83-data-collection.md](83-data-collection.md) | DCRs and DCEs |
| [84-cost-estimate.md](84-cost-estimate.md) | Estimated monthly cost |
| [85-rbac.md](85-rbac.md) | Role assignments |
| [86-subscription-context.md](86-subscription-context.md) | Subscription, tenant, RPs, locks, policy |
| [90-gap-analysis.md](90-gap-analysis.md) | Findings against MS Learn best practices |
| [99-references.md](99-references.md) | API versions, modules, Learn references |
"@
Write-Section 'index.md' $indexBody

Write-Information "✓ Renderer complete — output: $OutputRoot"
