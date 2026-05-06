<#
.SYNOPSIS
    Export every Microsoft Sentinel artefact, the supporting Log Analytics + DCR layer,
    subscription context and 30-day usage to a SecurityDocs/<workspace>/_raw/ folder.

.DESCRIPTION
    Read-only inventory tool. Designed to run in the daily 'sentinel-document' workflow
    against a workspace under a least-privilege service principal (Microsoft Sentinel
    Reader + Log Analytics Reader + Reader/Monitoring Reader at sub scope). Output is
    a directory of JSON files that the renderer (Convert-SentinelInventoryToMarkdown.ps1)
    converts into the human report.

    Splitting collector + renderer means: the cheap, deterministic markdown step can be
    re-run any time without touching Azure, and Pester fixtures can drive the renderer
    end-to-end with no auth.

    The collector uses Az.SecurityInsights / Az.OperationalInsights / Az.Monitor cmdlets
    where they exist, and Invoke-SentinelRest (Private/Invoke-SentinelRest.ps1) to fall
    back to direct REST for the documented gaps (CCF connectors, Content Hub, settings,
    full DCR JSON, etc.).

    No mutation. Every call is a GET.

.PARAMETER SubscriptionId
    Subscription ID containing the Sentinel workspace. Defaults to the active Az context.

.PARAMETER ResourceGroup
    Resource Group containing the Sentinel workspace.

.PARAMETER WorkspaceName
    Log Analytics workspace name with Sentinel onboarded.

.PARAMETER OutputRoot
    Folder root for the export. Defaults to ./SecurityDocs (gitignored). Files are written
    under <OutputRoot>/<WorkspaceName>/_raw/.

.PARAMETER IncludePreview
    Use the 2024-10-01-preview API version where applicable (Content Hub product packages,
    summary rules, pricings).

.NOTES
    Author:         noodlemctwoodle
    Component:      Sentinel Documenter
    Version:        0.1.0
    Last Updated:   2026-05-06
    Requires:       Az.Accounts, Az.SecurityInsights, Az.OperationalInsights, Az.Monitor, Az.Resources, Az.LogicApp
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot = (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'SecurityDocs'),

    [Parameter(Mandatory = $false)]
    [switch]$IncludePreview
)

#Requires -Modules Az.Accounts

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# ---------------------------------------------------------------------------
# Module bootstrap
# ---------------------------------------------------------------------------
# API versions are hardcoded here rather than read from Documenter.psd1.
# Reading the manifest at script start was failing silently on the ADO Linux
# agent, with $apiVersions arriving empty inside Try-Capture's child scope —
# every subsequent REST call then fired without an api-version and Azure
# returned 400 'MissingApiVersionParameter'. Inlining the table removes the
# external file as a moving part. Keep these values in sync with the
# 'ApiVersions' block in Documenter.psd1 and the table in REFERENCES.md.
$apiVersions = @{
    Sentinel              = '2024-09-01'
    SentinelPreview       = '2024-10-01-preview'
    OperationalInsights   = '2025-02-01'
    Tables                = '2023-09-01'
    DataCollection        = '2023-03-11'
}
$documenterVersion = '0.1.0'

. (Join-Path $PSScriptRoot 'Private/Invoke-SentinelRest.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-AzureRetailPrice.ps1')

# Add the System.Web assembly for HttpUtility used by Get-AzureRetailPrice.
Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# Output paths
# ---------------------------------------------------------------------------
$workspaceOut = Join-Path $OutputRoot $WorkspaceName
$rawOut = Join-Path $workspaceOut '_raw'

if (-not (Test-Path $rawOut)) {
    New-Item -ItemType Directory -Path $rawOut -Force | Out-Null
}

function Save-Json {
    # $Data is intentionally optional + nullable. An ARM endpoint that returns no
    # results legitimately surfaces as $null in PowerShell — the helper should
    # write '[]' for that case rather than refusing the parameter, otherwise the
    # collector emits dozens of misleading 'Cannot bind argument to parameter
    # Data because it is null' warnings on a quiet workspace.
    param(
        [Parameter(Mandatory)] [string]$FileName,
        [Parameter(Mandatory = $false)] [AllowNull()] $Data
    )
    $target = Join-Path $rawOut $FileName
    if ($null -eq $Data) {
        '[]' | Set-Content -Path $target -Encoding UTF8
    } else {
        $Data | ConvertTo-Json -Depth 32 -EnumsAsStrings | Set-Content -Path $target -Encoding UTF8
    }
    Write-Information "  ↳ wrote $FileName"
}

function Try-Capture {
    param(
        [Parameter(Mandatory)] [string]$Label,
        [Parameter(Mandatory)] [scriptblock]$Action
    )
    try {
        Write-Information "[$Label]"
        & $Action
    } catch {
        Write-Warning "$Label failed: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Azure context
# ---------------------------------------------------------------------------
$ctx = Get-AzContext -ErrorAction Stop
if ($SubscriptionId) {
    if ($ctx.Subscription.Id -ne $SubscriptionId) {
        Write-Information "Switching context to subscription $SubscriptionId"
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
        $ctx = Get-AzContext -ErrorAction Stop
    }
} else {
    $SubscriptionId = $ctx.Subscription.Id
}
$tenantId = $ctx.Tenant.Id

$workspaceResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"
$sentinelScope       = "$workspaceResourceId/providers/Microsoft.SecurityInsights"

# ---------------------------------------------------------------------------
# Run context — anchors every output
# ---------------------------------------------------------------------------
$runContext = [pscustomobject]@{
    SubscriptionId    = $SubscriptionId
    TenantId          = $tenantId
    ResourceGroup     = $ResourceGroup
    WorkspaceName     = $WorkspaceName
    WorkspaceResourceId = $workspaceResourceId
    StartedAtUtc      = (Get-Date).ToUniversalTime().ToString('o')
    ApiVersions       = $apiVersions
    DocumenterVersion = $documenterVersion
    AzPSVersion       = (Get-Module -ListAvailable Az.Accounts | Sort-Object Version -Descending | Select-Object -First 1).Version.ToString()
    IncludePreview    = [bool]$IncludePreview
    ScriptCommit      = (& git -C (Split-Path -Parent $PSScriptRoot) rev-parse HEAD 2>$null) -as [string]
}
Save-Json -FileName 'run-context.json' -Data $runContext

# ---------------------------------------------------------------------------
# Workspace + ingestion layer
# ---------------------------------------------------------------------------
Try-Capture 'workspace' {
    $ws = Invoke-SentinelRest -Path $workspaceResourceId -ApiVersion $apiVersions.OperationalInsights
    Save-Json -FileName 'workspace.json' -Data $ws[0]
    $script:WorkspaceObject = $ws[0]
}

Try-Capture 'workspace-tables' {
    $tables = Invoke-SentinelRest -Path "$workspaceResourceId/tables" -ApiVersion $apiVersions.Tables
    Save-Json -FileName 'workspace-tables.json' -Data $tables
}

Try-Capture 'sentinel-pricing' {
    # Microsoft.SecurityInsights/pricings is preview-only and the api-version
    # surface is volatile. The endpoint also doesn't exist in every region —
    # against a uksouth workspace ARM rejects the preview version. Probe the
    # GA Sentinel api-version first, fall back to preview, and treat 4xx as a
    # 'not present' signal so an empty file is still produced.
    $pricing = $null
    if ($IncludePreview) {
        try {
            $pricing = Invoke-SentinelRest -Path "$sentinelScope/pricings" -ApiVersion $apiVersions.Sentinel
        } catch {
            try {
                $pricing = Invoke-SentinelRest -Path "$sentinelScope/pricings" -ApiVersion $apiVersions.SentinelPreview
            } catch {
                Write-Information "  ↳ pricings endpoint not available; emitting empty file."
            }
        }
    }
    Save-Json -FileName 'sentinel-pricing.json' -Data $pricing
}

Try-Capture 'sentinel-onboarding-state' {
    $obs = Invoke-SentinelRest -Path "$sentinelScope/onboardingStates" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'onboarding-state.json' -Data $obs
}

# ---------------------------------------------------------------------------
# Sentinel artefacts
# ---------------------------------------------------------------------------
Try-Capture 'data-connectors-classic' {
    $connectors = Invoke-SentinelRest -Path "$sentinelScope/dataConnectors" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'data-connectors-classic.json' -Data $connectors
}

Try-Capture 'data-connector-definitions' {
    $defs = Invoke-SentinelRest -Path "$sentinelScope/dataConnectorDefinitions" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'data-connector-definitions.json' -Data $defs
}

Try-Capture 'alert-rules' {
    $rules = Invoke-SentinelRest -Path "$sentinelScope/alertRules" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'alert-rules.json' -Data $rules
}

Try-Capture 'alert-rule-templates' {
    $templates = Invoke-SentinelRest -Path "$sentinelScope/alertRuleTemplates" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'alert-rule-templates.json' -Data $templates
}

Try-Capture 'automation-rules' {
    $auto = Invoke-SentinelRest -Path "$sentinelScope/automationRules" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'automation-rules.json' -Data $auto
}

Try-Capture 'watchlists' {
    $wls = Invoke-SentinelRest -Path "$sentinelScope/watchlists" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'watchlists.json' -Data $wls

    if ($wls) {
        $itemsRoot = Join-Path $rawOut 'watchlist-items'
        if (-not (Test-Path $itemsRoot)) { New-Item -ItemType Directory -Path $itemsRoot -Force | Out-Null }
        foreach ($wl in $wls) {
            $alias = $wl.name
            try {
                $items = Invoke-SentinelRest -Path "$($wl.id)/watchlistItems" -ApiVersion $apiVersions.Sentinel
                $items | ConvertTo-Json -Depth 32 | Set-Content -Path (Join-Path $itemsRoot "$alias.json") -Encoding UTF8
            } catch {
                Write-Warning "watchlist-items[$alias] failed: $($_.Exception.Message)"
            }
        }
    }
}

Try-Capture 'bookmarks' {
    $bm = Invoke-SentinelRest -Path "$sentinelScope/bookmarks" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'bookmarks.json' -Data $bm
}

Try-Capture 'metadata' {
    $meta = Invoke-SentinelRest -Path "$sentinelScope/metadata" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'metadata.json' -Data $meta
}

Try-Capture 'content-packages' {
    $pkgs = Invoke-SentinelRest -Path "$sentinelScope/contentPackages" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'content-packages.json' -Data $pkgs
}

Try-Capture 'content-product-packages' {
    if ($IncludePreview) {
        $catalog = Invoke-SentinelRest -Path "$sentinelScope/contentProductPackages" -ApiVersion $apiVersions.SentinelPreview
        Save-Json -FileName 'content-product-packages.json' -Data $catalog
    }
}

Try-Capture 'summary-rules' {
    if ($IncludePreview) {
        $sr = Invoke-SentinelRest -Path "$sentinelScope/contentTemplates?`$filter=properties/contentKind eq 'SummaryRule'" -ApiVersion $apiVersions.SentinelPreview
        Save-Json -FileName 'summary-rules.json' -Data $sr
    }
}

Try-Capture 'repositories' {
    # sourceControls is published on a different api-version cadence than the
    # rest of Sentinel. The Sentinel GA pin '2024-09-01' returns
    # UnsupportedApiVersion against ARM. Try the GA Sentinel pin first, then
    # known-good fallbacks for sourceControls specifically. Treat all 4xx as
    # 'feature not present' rather than a failure.
    $repos = $null
    foreach ($v in @($apiVersions.Sentinel, '2023-11-01', '2023-06-01-preview', '2022-12-01-preview')) {
        try {
            $repos = Invoke-SentinelRest -Path "$sentinelScope/sourceControls" -ApiVersion $v
            break
        } catch {
            $repos = $null
        }
    }
    Save-Json -FileName 'repositories.json' -Data $repos
}

# Bundle the four settings resources into a single file with one property per setting.
Try-Capture 'sentinel-settings' {
    $settings = [ordered]@{}
    foreach ($n in @('Ueba','EntityAnalytics','EyesOn','Anomalies')) {
        try {
            $val = Invoke-SentinelRest -Path "$sentinelScope/settings/$n" -ApiVersion $apiVersions.Sentinel
            $settings[$n] = $val[0]
        } catch {
            $settings[$n] = $null
        }
    }
    Save-Json -FileName 'settings.json' -Data $settings
}

# ---------------------------------------------------------------------------
# Hunting / parsers / saved searches
# ---------------------------------------------------------------------------
Try-Capture 'kql-savedsearches' {
    $all = Invoke-SentinelRest -Path "$workspaceResourceId/savedSearches" -ApiVersion $apiVersions.OperationalInsights
    Save-Json -FileName 'kql-savedsearches.json' -Data $all

    if ($all) {
        # StrictMode-safe property access — savedSearch records do not all carry
        # 'functionAlias' on their PSObject, so a bare $_.properties.functionAlias
        # throws under StrictMode 'Latest'. Use HasMember-style probing.
        $hunting = @($all | Where-Object {
            $cat = $null
            if ($_.properties -and ($_.properties.PSObject.Properties.Name -contains 'category')) {
                $cat = $_.properties.category
            }
            $cat -eq 'Hunting Queries'
        })
        $parsers = @($all | Where-Object {
            $cat = $null; $alias = $null
            if ($_.properties) {
                if ($_.properties.PSObject.Properties.Name -contains 'category')      { $cat   = $_.properties.category }
                if ($_.properties.PSObject.Properties.Name -contains 'functionAlias') { $alias = $_.properties.functionAlias }
            }
            ($cat -eq 'Functions') -or $alias
        })
        Save-Json -FileName 'hunting-queries.json'  -Data $hunting
        Save-Json -FileName 'parsers-functions.json' -Data $parsers
    }
}

# ---------------------------------------------------------------------------
# Workbooks
# ---------------------------------------------------------------------------
Try-Capture 'workbooks-saved' {
    $sub = "/subscriptions/$SubscriptionId"
    $all = Invoke-SentinelRest -Path "$sub/providers/Microsoft.Insights/workbooks?category=sentinel" -ApiVersion '2023-06-01'
    $scoped = @($all | Where-Object { $_.properties.sourceId -eq $workspaceResourceId })
    Save-Json -FileName 'workbooks-saved.json' -Data $scoped
}

Try-Capture 'workbook-templates' {
    $tpl = Invoke-SentinelRest -Path "$sentinelScope/contentTemplates?`$filter=properties/contentKind eq 'Workbook'" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'workbook-templates.json' -Data $tpl
}

# ---------------------------------------------------------------------------
# Playbooks (Logic Apps) + their MI grants
# ---------------------------------------------------------------------------
Try-Capture 'playbooks' {
    $logicApps = Get-AzLogicApp -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
    Save-Json -FileName 'playbooks.json' -Data $logicApps

    $miAssignments = @()
    foreach ($la in @($logicApps)) {
        $mi = $la.Identity
        if ($null -eq $mi -or [string]::IsNullOrWhiteSpace($mi.PrincipalId)) { continue }
        try {
            $assignments = Get-AzRoleAssignment -ObjectId $mi.PrincipalId -ErrorAction SilentlyContinue
            $workspaceRoles = @($assignments | Where-Object { $_.Scope -eq $workspaceResourceId } | Select-Object -ExpandProperty RoleDefinitionName)
            $miAssignments += [pscustomobject]@{
                Playbook         = $la.Name
                PrincipalId      = $mi.PrincipalId
                AllAssignments   = $assignments
                WorkspaceRoles   = $workspaceRoles
            }
        } catch {
            Write-Warning "RBAC enumeration for playbook $($la.Name) failed: $($_.Exception.Message)"
        }
    }
    Save-Json -FileName 'rbac-playbook-mi.json' -Data $miAssignments
}

# ---------------------------------------------------------------------------
# Data Collection — DCRs / DCEs / DCRA / Diagnostic Settings
# ---------------------------------------------------------------------------
Try-Capture 'dcrs' {
    $dcrs = Invoke-SentinelRest -Path "/subscriptions/$SubscriptionId/providers/Microsoft.Insights/dataCollectionRules" -ApiVersion $apiVersions.DataCollection
    Save-Json -FileName 'dcrs.json' -Data $dcrs
}

Try-Capture 'dces' {
    $dces = Invoke-SentinelRest -Path "/subscriptions/$SubscriptionId/providers/Microsoft.Insights/dataCollectionEndpoints" -ApiVersion $apiVersions.DataCollection
    Save-Json -FileName 'dces.json' -Data $dces
}

Try-Capture 'diagnostic-settings' {
    $ds = Invoke-SentinelRest -Path "$workspaceResourceId/providers/Microsoft.Insights/diagnosticSettings" -ApiVersion '2021-05-01-preview'
    Save-Json -FileName 'diagnostic-settings.json' -Data $ds
}

# ---------------------------------------------------------------------------
# Cluster, replication, AMPLS, linked services, solutions
# ---------------------------------------------------------------------------
Try-Capture 'dedicated-cluster' {
    # 'clusterResourceId' is only present on the workspace.features object when
    # a Log Analytics dedicated cluster is linked. Probe for the property
    # explicitly under StrictMode rather than dotting through it blindly.
    $clusterId = $null
    if ($script:WorkspaceObject -and
        $script:WorkspaceObject.properties -and
        $script:WorkspaceObject.properties.PSObject.Properties.Name -contains 'features' -and
        $script:WorkspaceObject.properties.features -and
        $script:WorkspaceObject.properties.features.PSObject.Properties.Name -contains 'clusterResourceId') {
        $clusterId = $script:WorkspaceObject.properties.features.clusterResourceId
    }
    if ($clusterId) {
        $cluster = Invoke-SentinelRest -Path $clusterId -ApiVersion '2022-10-01'
        Save-Json -FileName 'dedicated-cluster.json' -Data $cluster[0]
    } else {
        Save-Json -FileName 'dedicated-cluster.json' -Data $null
    }
}

Try-Capture 'sentinel-data-lake' {
    if ($IncludePreview) {
        try {
            $lake = Invoke-SentinelRest -Path "$sentinelScope/dataLake" -ApiVersion $apiVersions.SentinelPreview
            Save-Json -FileName 'sentinel-data-lake.json' -Data $lake
        } catch {
            # Endpoint may not be present on workspaces without lake enabled.
            Save-Json -FileName 'sentinel-data-lake.json' -Data @()
        }
    }
}

Try-Capture 'linked-services' {
    $ls = Invoke-SentinelRest -Path "$workspaceResourceId/linkedServices" -ApiVersion $apiVersions.OperationalInsights
    Save-Json -FileName 'linked-services.json' -Data $ls
}

Try-Capture 'solutions-installed' {
    $sols = Invoke-SentinelRest -Path "/subscriptions/$SubscriptionId/providers/Microsoft.OperationsManagement/solutions" -ApiVersion '2015-11-01-preview'
    $scoped = @($sols | Where-Object { $_.properties.workspaceResourceId -eq $workspaceResourceId })
    Save-Json -FileName 'solutions-installed.json' -Data $scoped
}

# ---------------------------------------------------------------------------
# Subscription / tenant context
# ---------------------------------------------------------------------------
Try-Capture 'subscription' {
    $sub = Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop |
        Select-Object Id, Name, TenantId, State, HomeTenantId
    Save-Json -FileName 'subscription.json' -Data $sub
}

Try-Capture 'resource-providers' {
    $rps = Get-AzResourceProvider -ListAvailable -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderNamespace -in @('Microsoft.SecurityInsights','Microsoft.OperationalInsights','Microsoft.Insights','Microsoft.OperationsManagement') } |
        Select-Object ProviderNamespace, RegistrationState
    Save-Json -FileName 'resource-providers.json' -Data $rps
}

Try-Capture 'subscription-locks' {
    $locks = @()
    $locks += Get-AzResourceLock -Scope "/subscriptions/$SubscriptionId" -ErrorAction SilentlyContinue
    $locks += Get-AzResourceLock -Scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup" -ErrorAction SilentlyContinue
    $locks += Get-AzResourceLock -Scope $workspaceResourceId -ErrorAction SilentlyContinue
    Save-Json -FileName 'subscription-locks.json' -Data $locks
}

Try-Capture 'policy-assignments' {
    # Get-AzPolicyAssignment shape changed across Az.Resources versions: older
    # builds expose .Properties.DisplayName, newer ones expose .DisplayName at
    # the top level. Probe both rather than tying to a single Az version.
    $assigns = Get-AzPolicyAssignment -Scope "/subscriptions/$SubscriptionId" -ErrorAction SilentlyContinue |
        Where-Object {
            $name = $null
            if ($_.PSObject.Properties.Name -contains 'Properties' -and $_.Properties) {
                $name = $_.Properties.DisplayName
            }
            if (-not $name -and $_.PSObject.Properties.Name -contains 'DisplayName') {
                $name = $_.DisplayName
            }
            if (-not $name) { $name = $_.Name }
            ($name -as [string]) -match 'Sentinel|Log Analytics|Monitor|retention|workspace'
        }
    Save-Json -FileName 'policy-assignments.json' -Data $assigns
}

# ---------------------------------------------------------------------------
# Identity & access
# ---------------------------------------------------------------------------
Try-Capture 'rbac-workspace' {
    $assigns = Get-AzRoleAssignment -Scope $workspaceResourceId -ErrorAction SilentlyContinue
    Save-Json -FileName 'rbac-workspace.json' -Data $assigns
}

Try-Capture 'rbac-resourcegroup' {
    $rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"
    $assigns = Get-AzRoleAssignment -Scope $rgScope -ErrorAction SilentlyContinue
    Save-Json -FileName 'rbac-resourcegroup.json' -Data $assigns
}

# ---------------------------------------------------------------------------
# Cost / usage — KQL queries
# ---------------------------------------------------------------------------
Try-Capture 'tables-with-data' {
    $kql = @'
Usage
| where TimeGenerated > ago(90d)
| summarize
    BillableLast90d = sumif(Quantity, IsBillable == true) / 1024.0,
    IngestedLast90d = sum(Quantity) / 1024.0,
    BillableLast30d = sumif(Quantity, IsBillable == true and TimeGenerated > ago(30d)) / 1024.0,
    BillableLast7d  = sumif(Quantity, IsBillable == true and TimeGenerated > ago(7d))  / 1024.0,
    BillableLast24h = sumif(Quantity, IsBillable == true and TimeGenerated > ago(1d))  / 1024.0,
    FirstSeen       = min(TimeGenerated),
    LastIngested    = max(TimeGenerated),
    DayCount        = dcount(bin(TimeGenerated, 1d))
    by DataType, Solution
'@
    $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
    Save-Json -FileName 'tables-with-data.json' -Data ($result.Results)
}

Try-Capture 'ingestion-latency' {
    $kql = @'
Operation
| where TimeGenerated > ago(7d)
| where OperationCategory in ("Ingestion", "Schema")
| summarize Failures = countif(OperationStatus != "Succeeded"), Last = max(TimeGenerated)
    by OperationKey = tostring(Detail), Resource = tostring(OperationCategory)
| where Failures > 0
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'ingestion-latency.json' -Data ($result.Results)
    } catch {
        # Operation table may be empty/absent on quiet workspaces.
        Save-Json -FileName 'ingestion-latency.json' -Data @()
    }
}

Try-Capture 'retail-prices' {
    $region = $script:WorkspaceObject.location
    $prices = Get-AzureRetailPrice -Region $region -OutputRoot $rawOut
    Save-Json -FileName 'retail-prices.json' -Data $prices
}

# ---------------------------------------------------------------------------
# Sentinel health, SOC Optimization, incidents, AMA agents
# ---------------------------------------------------------------------------
Try-Capture 'sentinel-health' {
    # SentinelHealth surfaces connector / rule / playbook health events.
    # Tolerate missing table on workspaces where Sentinel health diagnostics
    # are not yet enabled.
    $kql = @'
SentinelHealth
| where TimeGenerated > ago(7d)
| summarize
    Events    = count(),
    LastEvent = max(TimeGenerated),
    Statuses  = make_set(Status, 10)
    by SentinelResourceName, SentinelResourceKind, SentinelResourceType
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'sentinel-health.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'sentinel-health.json' -Data @()
    }
}

Try-Capture 'soc-optimization' {
    # Sentinel SOC Optimization recommendations (preview surface). The endpoint
    # only exists when the workspace is onboarded and the recommendations
    # service has run at least once. 4xx is treated as 'no recommendations'.
    try {
        $opt = Invoke-SentinelRest -Path "$sentinelScope/recommendations" -ApiVersion $apiVersions.SentinelPreview
        Save-Json -FileName 'soc-optimization.json' -Data $opt
    } catch {
        Save-Json -FileName 'soc-optimization.json' -Data @()
    }
}

Try-Capture 'incidents-summary' {
    # Aggregate-only — the documenter never exports incident bodies (PII).
    $kql = @'
SecurityIncident
| where TimeGenerated > ago(30d)
| summarize arg_max(TimeGenerated, *) by IncidentNumber
| summarize
    Count   = count(),
    ByStatus   = make_bag(bag_pack(Status,    1), 100),
    BySeverity = make_bag(bag_pack(Severity,  1), 100)
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'incidents-summary.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'incidents-summary.json' -Data @()
    }
}

Try-Capture 'incidents-mttr' {
    # Mean time to acknowledge / resolve, last 30 days. Surfaces SOC efficiency
    # without exporting incident detail.
    $kql = @'
SecurityIncident
| where TimeGenerated > ago(30d)
| summarize arg_max(TimeGenerated, *) by IncidentNumber
| where Status == "Closed"
| extend AckMins  = datetime_diff('minute', FirstModifiedTime, CreatedTime)
| extend RsvMins  = datetime_diff('minute', ClosedTime,        CreatedTime)
| summarize
    ClosedCount = count(),
    MTTAMinutes = avg(AckMins),
    MTTRMinutes = avg(RsvMins)
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'incidents-mttr.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'incidents-mttr.json' -Data @()
    }
}

Try-Capture 'incidents-by-rule' {
    $kql = @'
SecurityIncident
| where TimeGenerated > ago(30d)
| summarize arg_max(TimeGenerated, *) by IncidentNumber
| mv-expand AlertIds
| summarize Incidents = dcount(IncidentNumber) by Title
| order by Incidents desc
| take 25
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'incidents-by-rule.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'incidents-by-rule.json' -Data @()
    }
}

Try-Capture 'ama-agents' {
    # Heartbeat is the canonical signal for Azure Monitor Agent presence.
    $kql = @'
Heartbeat
| where TimeGenerated > ago(7d)
| summarize
    LastHeartbeat = max(TimeGenerated),
    OS            = any(OSType),
    Version       = any(Version),
    Solutions     = any(Solutions),
    Computer      = any(Computer),
    Resource      = any(_ResourceId)
    by SourceComputerId
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'ama-agents.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'ama-agents.json' -Data @()
    }
}

Try-Capture 'data-exports' {
    $exports = Invoke-SentinelRest -Path "$workspaceResourceId/dataExports" -ApiVersion $apiVersions.OperationalInsights
    Save-Json -FileName 'data-exports.json' -Data $exports
}

Try-Capture 'threat-intel-counts' {
    # KQL on the indicator tables — counts only, never indicator detail.
    $kql = @'
union isfuzzy=true ThreatIntelligenceIndicator, ThreatIntelIndicators
| where TimeGenerated > ago(30d)
| summarize Count = count(), Last = max(TimeGenerated) by SourceSystem = coalesce(SourceSystem, Source)
| order by Count desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'threat-intel-counts.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'threat-intel-counts.json' -Data @()
    }
}

Try-Capture 'analytics-rule-volumes' {
    # Per-rule alert volume from SecurityAlert. Drives the 'top noisy rules'
    # breakout (TOC 4.11.2).
    $kql = @'
SecurityAlert
| where TimeGenerated > ago(30d)
| summarize Alerts = count() by AlertName, ProductName, Severity
| order by Alerts desc
| take 50
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'analytics-rule-volumes.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'analytics-rule-volumes.json' -Data @()
    }
}

# ---------------------------------------------------------------------------
# Cost estimate
# ---------------------------------------------------------------------------
Try-Capture 'cost-estimate' {
    . (Join-Path $PSScriptRoot 'Private/Get-SentinelCostEstimate.ps1')
    $est = Get-SentinelCostEstimate -InputRoot $rawOut -ResourcesRoot (Join-Path $PSScriptRoot 'Private/Resources')
    Save-Json -FileName 'cost-estimate.json' -Data $est
}

# ---------------------------------------------------------------------------
# Gap analysis
# ---------------------------------------------------------------------------
Try-Capture 'gap-analysis' {
    . (Join-Path $PSScriptRoot 'Private/Get-SentinelGap.ps1')
    $findings = Get-SentinelGap `
        -InputRoot $rawOut `
        -ResourcesRoot (Join-Path $PSScriptRoot 'Private/Resources') `
        -RulesPath (Join-Path $PSScriptRoot 'Private/Resources/best-practices.json') `
        -GapChecksPath (Join-Path $PSScriptRoot 'Private/GapChecks.ps1')
    Save-Json -FileName 'gap-analysis.json' -Data $findings
}

# ---------------------------------------------------------------------------
# Wrap-up
# ---------------------------------------------------------------------------
$runContext = $runContext | Add-Member -MemberType NoteProperty -Name CompletedAtUtc -Value (Get-Date).ToUniversalTime().ToString('o') -PassThru
Save-Json -FileName 'run-context.json' -Data $runContext

Write-Information "✓ Sentinel inventory exported to $rawOut"
