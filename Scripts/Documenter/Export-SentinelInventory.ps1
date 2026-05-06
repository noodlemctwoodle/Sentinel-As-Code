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
$manifestPath = Join-Path $PSScriptRoot 'Documenter.psd1'
$manifest = Import-PowerShellDataFile -Path $manifestPath
$apiVersions = $manifest.ApiVersions

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
    param(
        [Parameter(Mandatory)] [string]$FileName,
        [Parameter(Mandatory)] $Data
    )
    $target = Join-Path $rawOut $FileName
    $json = $Data | ConvertTo-Json -Depth 32 -EnumsAsStrings
    $json | Set-Content -Path $target -Encoding UTF8
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
    DocumenterVersion = $manifest.Version
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
    if ($IncludePreview) {
        $pricing = Invoke-SentinelRest -Path "$sentinelScope/pricings" -ApiVersion $apiVersions.SentinelPreview
        Save-Json -FileName 'sentinel-pricing.json' -Data $pricing
    }
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
    $repos = Invoke-SentinelRest -Path "$sentinelScope/sourceControls" -ApiVersion $apiVersions.Sentinel
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
        $hunting = @($all | Where-Object { $_.properties.category -eq 'Hunting Queries' })
        $parsers = @($all | Where-Object { $_.properties.category -eq 'Functions'        -or $_.properties.functionAlias })
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
    $clusterId = $script:WorkspaceObject.properties.features.clusterResourceId
    if ($clusterId) {
        $cluster = Invoke-SentinelRest -Path $clusterId -ApiVersion '2022-10-01'
        Save-Json -FileName 'dedicated-cluster.json' -Data $cluster[0]
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
    $assigns = Get-AzPolicyAssignment -Scope "/subscriptions/$SubscriptionId" -ErrorAction SilentlyContinue |
        Where-Object {
            $name = $_.Properties.DisplayName
            $name -match 'Sentinel|Log Analytics|Monitor|retention|workspace'
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
