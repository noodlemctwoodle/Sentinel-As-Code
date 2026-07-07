#
# Sentinel-As-Code/Tools/Documenter/Export-SentinelInventory.ps1
#
# Created by noodlemctwoodle on 06/05/2026.
#

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

    # Logic Apps resource group. Sentinel-As-Code allows playbooks to live in a
    # separate resource group from the workspace (the `playbookResourceGroup`
    # pipeline variable). Defaults to the Sentinel resource group when unset.
    [Parameter(Mandatory = $false)]
    [string]$PlaybookResourceGroup,

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
# agent, with $apiVersions arriving empty inside Try-Capture's child scope, 
# every subsequent REST call then fired without an api-version and Azure
# returned 400 'MissingApiVersionParameter'. Inlining the table removes the
# external file as a moving part. Keep these values in sync with the
# 'ApiVersions' block in Documenter.psd1 and the table in Documenter-References.md.
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
    # results legitimately surfaces as $null in PowerShell, the helper should
    # write '[]' for that case rather than refusing the parameter, otherwise the
    # collector emits dozens of misleading 'Cannot bind argument to parameter
    # Data because it is null' warnings on a quiet workspace.
    #
    # -AsArray on every save protects against PowerShells unwrap-single-element
    # quirk where a one-item array is serialized as a single object, which then
    # breaks downstream array-shaped readers (Read-RawArray + ForEach-Object).
    param(
        [Parameter(Mandatory)] [string]$FileName,
        [Parameter(Mandatory = $false)] [AllowNull()] $Data
    )
    $target = Join-Path $rawOut $FileName
    $singleObjectFiles = @(
        'workspace.json','run-context.json','settings.json','cost-estimate.json',
        'subscription.json','dedicated-cluster.json'
    )
    if ($null -eq $Data) {
        if ($singleObjectFiles -contains $FileName) {
            '{}' | Set-Content -Path $target -Encoding UTF8
        } else {
            '[]' | Set-Content -Path $target -Encoding UTF8
        }
    }
    elseif ($singleObjectFiles -contains $FileName) {
        $Data | ConvertTo-Json -Depth 32 -EnumsAsStrings | Set-Content -Path $target -Encoding UTF8
    }
    else {
        # Collection-shape file. Pipe through ConvertTo-Json so each item is
        # treated as a separate input, pipe + -AsArray always emits a JSON
        # array, including the single-element and empty cases. Using
        # -InputObject would treat the whole array as one input, which then
        # double-wraps under -AsArray.
        $items = @($Data)
        if ($items.Count -eq 0) {
            '[]' | Set-Content -Path $target -Encoding UTF8
        } else {
            $items | ConvertTo-Json -Depth 32 -EnumsAsStrings -AsArray | Set-Content -Path $target -Encoding UTF8
        }
    }
    Write-Information "  ↳ wrote $FileName"
}

$script:CaptureErrors = New-Object System.Collections.Generic.List[pscustomobject]
function Try-Capture {
    param(
        [Parameter(Mandatory)] [string]$Label,
        [Parameter(Mandatory)] [scriptblock]$Action
    )
    try {
        Write-Information "[$Label]"
        & $Action
    } catch {
        $msg = $_.Exception.Message
        # Surface the failure prominently. Try-Capture used to log only a
        # Write-Warning which is easy to miss in long ADO logs and silently
        # leaves the corresponding _raw/<file>.json absent or stale. We now
        # also accumulate the failure into a summary written at the end.
        Write-Warning "[$Label] FAILED: $msg"
        $script:CaptureErrors.Add([pscustomobject]@{
            Label   = $Label
            Message = $msg
        })
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
# Run context, anchors every output
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
    # surface is volatile. The endpoint also doesn't exist in every region, 
    # against a uksouth workspace ARM rejects the preview version. Probe the
    # GA Sentinel api-version first, fall back to preview, and treat 4xx as a
    # 'not present' signal so an empty file is still produced.
    #
    # Always probe regardless of -IncludePreview: the GA version usually
    # succeeds, and the inner try/catch handles the regional 4xx case. The
    # earlier IncludePreview gate meant production runs without the switch
    # produced no file at all.
    $pricing = $null
    try {
        $pricing = Invoke-SentinelRest -Path "$sentinelScope/pricings" -ApiVersion $apiVersions.Sentinel
    } catch {
        try {
            $pricing = Invoke-SentinelRest -Path "$sentinelScope/pricings" -ApiVersion $apiVersions.SentinelPreview
        } catch {
            Write-Information "  ↳ pricings endpoint not available; emitting empty file."
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

# Playbooks (Logic Apps) capture is consolidated into the single block further
# down in the script that uses Get-AzLogicApp. That block writes both
# playbooks.json AND rbac-playbook-mi.json so the previous standalone REST
# capture here would just have been overwritten. The single Get-AzLogicApp
# block uses the conventional Az.LogicApp cmdlet, which is the canonical
# way to enumerate workflows in PowerShell.

Try-Capture 'watchlists' {
    # Enumerate watchlist definitions only. Item contents are intentionally not
    # captured, on workspaces with large lookup lists (GeoIP ranges, asset
    # inventories) the per-watchlist /watchlistItems pagination dominates the
    # collector runtime, and the rendered report never embeds item bodies.
    # Watchlist contents in a customer environment are expected to be sourced
    # from the IaC repository (Watchlists/*.csv), not from the live API.
    $wls = Invoke-SentinelRest -Path "$sentinelScope/watchlists" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'watchlists.json' -Data $wls
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
    # Content Hub catalogue. Was gated behind -IncludePreview which meant
    # production runs without the switch produced no catalogue file at all, 
    # which then broke the "Update Available" column in section 70.
    # contentProductPackages is GA via the preview api-version; treat
    # missing-file outcomes as endpoint unavailability rather than gate-skip.
    try {
        $catalog = Invoke-SentinelRest -Path "$sentinelScope/contentProductPackages" -ApiVersion $apiVersions.SentinelPreview
        Save-Json -FileName 'content-product-packages.json' -Data $catalog
    } catch {
        Save-Json -FileName 'content-product-packages.json' -Data @()
    }
}

Try-Capture 'summary-rules' {
    # Summary rules are owned by the OperationalInsights provider, not Sentinel
    #, the API path is `.../workspaces/<ws>/summaryLogs`, not the Content Hub
    # `.../contentTemplates?$filter=contentKind eq 'SummaryRule'` (which would
    # only return installable templates, not deployed rule instances). The
    # earlier implementation queried the wrong endpoint AND gated the call on
    # -IncludePreview, so production runs without that switch returned nothing
    # regardless of how many summary rules the workspace actually has.
    $sr = Invoke-SentinelRest -Path "$workspaceResourceId/summaryLogs" -ApiVersion '2023-01-01-preview'
    Save-Json -FileName 'summary-rules.json' -Data $sr
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
#
# Per-setting null in the produced file does NOT mean the corresponding feature
# is disabled. It means the workspace has no explicit settings resource at
# /providers/Microsoft.SecurityInsights/settings/<name>. UEBA, Entity Analytics,
# Eyes-On, and Anomalies can be toggled on via the portal without writing the
# settings resource, in which case the GET returns 404 and Invoke-SentinelRest
# converts that to an empty array (see Invoke-SentinelRest.ps1 line ~104).
# $val[0] then correctly unwraps the single-element response when the resource
# does exist, and resolves to null when it does not.
#
# To answer the operational question "is UEBA actually producing data?" the
# more robust signal is row counts in BehaviorAnalytics / IdentityInfo /
# UserPeerAnalytics. That data-presence inference is captured separately by
# a future commit; the settings capture here is the configuration-side signal.
Try-Capture 'sentinel-settings' {
    $settings = [ordered]@{}
    foreach ($n in @('Ueba','EntityAnalytics','EyesOn','Anomalies')) {
        try {
            # Invoke-SentinelRest always returns an array (single-resource
            # responses get wrapped in a one-element array, 404s yield @()).
            # When the workspace has the settings resource present, $val has
            # exactly one element; when the toggle lives only in the portal
            # the endpoint 404s and $val is empty -> $null is stored. The
            # renderer treats $null as "settings resource not written" and
            # falls back to the data-presence capture below for the real
            # "is UEBA producing data?" signal.
            $val = Invoke-SentinelRest -Path "$sentinelScope/settings/$n" -ApiVersion $apiVersions.Sentinel
            $settings[$n] = if ($val -and @($val).Count -gt 0) { $val[0] } else { $null }
        } catch {
            $settings[$n] = $null
        }
    }
    Save-Json -FileName 'settings.json' -Data $settings
}

# UEBA data-presence inference.
# The /settings/Ueba endpoint only reflects the configuration-side state and
# returns 404 when UEBA is toggled on via the portal without an explicit
# settings resource being written. The operational question users ask
# ("is UEBA producing data?") is better answered by counting rows in the
# tables UEBA writes to: BehaviorAnalytics, IdentityInfo, UserPeerAnalytics.
# Capture the per-table row counts over the last 12 days so the renderer can
# surface "data flowing -> Yes" even when the settings GET reported absence.
Try-Capture 'ueba-data-presence' {
    # Stamp the table name onto every row BEFORE union, `union withsource`
    # only labels rows present at the moment of the union, and the inner
    # `summarize count()` collapsed each arm to a single row, so withsource
    # fell back to synthetic positional names (union_arg0/1/2) instead of
    # the real table name. The fix: extend Table at the source, summarize
    # by Table after the union. `isfuzzy=true` also handles a workspace
    # that hasn't enabled UEBA yet (UserPeerAnalytics may be missing), 
    # KQL skips the missing arm rather than throwing.
    $kql = @'
union isfuzzy=true
    (BehaviorAnalytics  | where TimeGenerated > ago(12d) | extend TableName = "BehaviorAnalytics"),
    (IdentityInfo       | where TimeGenerated > ago(12d) | extend TableName = "IdentityInfo"),
    (UserPeerAnalytics  | where TimeGenerated > ago(12d) | extend TableName = "UserPeerAnalytics")
| summarize Count = count() by TableName
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'ueba-data-presence.json' -Data ($r.Results)
    } catch { Save-Json -FileName 'ueba-data-presence.json' -Data @() }
}

# ---------------------------------------------------------------------------
# Hunting / parsers / saved searches
# ---------------------------------------------------------------------------
Try-Capture 'kql-savedsearches' {
    $all = Invoke-SentinelRest -Path "$workspaceResourceId/savedSearches" -ApiVersion $apiVersions.OperationalInsights
    Save-Json -FileName 'kql-savedsearches.json' -Data $all

    if ($all) {
        # StrictMode-safe property access, savedSearch records do not all carry
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
    # Use the configurable playbook RG when set (Sentinel-As-Code convention),
    # otherwise default to the Sentinel resource group.
    #
    # Why REST and not Get-AzLogicApp: the cmdlet's list-style call returns
    # PSWorkflow objects without the `Identity` property populated even when
    # the workflow has a managed identity attached. Verified against the live
    # workspace where the REST API saw `identity.principalId` for a playbook
    # the cmdlet listed without any Identity at all.
    $playbookRg = if ($PlaybookResourceGroup) { $PlaybookResourceGroup } else { $ResourceGroup }
    $workflows = Invoke-SentinelRest `
        -Path "/subscriptions/$SubscriptionId/resourceGroups/$playbookRg/providers/Microsoft.Logic/workflows" `
        -ApiVersion '2016-06-01'
    Save-Json -FileName 'playbooks.json' -Data $workflows

    # Resolve the per-playbook MI workspace-scoped role assignments.
    #
    # The REST shape of `identity` depends on the assignment type:
    #   SystemAssigned                  : identity.principalId at top level
    #   UserAssigned                    : identity.userAssignedIdentities.<resourceId>.principalId (no top-level principalId)
    #   SystemAssignedAndUserAssigned   : both
    # Strict mode forbids reading a property that isn't present, so every read
    # is guarded with PSObject.Properties.Name -contains '<name>'. A workflow
    # with no managed identity has the `identity` member absent entirely.
    $miAssignments = @()
    foreach ($wf in @($workflows)) {
        if (-not ($wf.PSObject.Properties.Name -contains 'identity')) { continue }
        $mi = $wf.identity
        if ($null -eq $mi) { continue }

        $principalIds = New-Object System.Collections.Generic.List[string]
        if ($mi.PSObject.Properties.Name -contains 'principalId' -and -not [string]::IsNullOrWhiteSpace($mi.principalId)) {
            $principalIds.Add([string]$mi.principalId)
        }
        if ($mi.PSObject.Properties.Name -contains 'userAssignedIdentities' -and $null -ne $mi.userAssignedIdentities) {
            foreach ($uaProp in $mi.userAssignedIdentities.PSObject.Properties) {
                $ua = $uaProp.Value
                if ($null -ne $ua -and $ua.PSObject.Properties.Name -contains 'principalId' -and -not [string]::IsNullOrWhiteSpace($ua.principalId)) {
                    $principalIds.Add([string]$ua.principalId)
                }
            }
        }
        if ($principalIds.Count -eq 0) { continue }

        foreach ($principalId in ($principalIds | Sort-Object -Unique)) {
            try {
                $assignments = Get-AzRoleAssignment -ObjectId $principalId -ErrorAction SilentlyContinue
                $workspaceRoles = @($assignments | Where-Object { $_.Scope -eq $workspaceResourceId } | Select-Object -ExpandProperty RoleDefinitionName)
                $miAssignments += [pscustomobject]@{
                    Playbook         = $wf.name
                    PrincipalId      = $principalId
                    AllAssignments   = $assignments
                    WorkspaceRoles   = $workspaceRoles
                }
            } catch {
                Write-Warning "RBAC enumeration for playbook $($wf.name) failed: $($_.Exception.Message)"
            }
        }
    }
    Save-Json -FileName 'rbac-playbook-mi.json' -Data $miAssignments
}

# ---------------------------------------------------------------------------
# Data Collection, DCRs / DCEs / DCRA / Diagnostic Settings
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
    # Sentinel Data Lake is provisioned as a Microsoft.SentinelPlatformServices/
    # sentinelPlatformServices resource. It's a tenant-wide capability but
    # the resource lives in a specific subscription / resource group / region
    # that the operator chose during Defender-portal onboarding, typically
    # NOT the same RG as the Sentinel workspace. Workspace-scoped GETs against
    # Microsoft.SecurityInsights/dataLake return 400 because no such
    # subresource is registered there. Resource Graph finds the platform-
    # services resource wherever it lives.
    #
    # Strategy: query Resource Graph across every subscription the executing
    # identity can read. A tenant with Lake onboarded returns exactly one
    # `microsoft.sentinelplatformservices/sentinelplatformservices` row;
    # without Lake onboarding the result is empty.
    try {
        $visibleSubs = @(Get-AzSubscription -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
        if ($visibleSubs.Count -eq 0) { $visibleSubs = @($SubscriptionId) }
        $rgBody = @{
            subscriptions = $visibleSubs
            query = 'Resources | where type =~ "microsoft.sentinelplatformservices/sentinelplatformservices" | project id, name, location, resourceGroup, subscriptionId, properties, identity, systemData'
        } | ConvertTo-Json -Compress -Depth 5
        $raw = Invoke-AzRestMethod -Path '/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' -Method POST -Payload $rgBody -ErrorAction Stop
        if ($raw.StatusCode -lt 400 -and $raw.Content) {
            $body = $raw.Content | ConvertFrom-Json
            Save-Json -FileName 'sentinel-data-lake.json' -Data @($body.data)
        } else {
            Save-Json -FileName 'sentinel-data-lake.json' -Data @()
        }
    } catch {
        Save-Json -FileName 'sentinel-data-lake.json' -Data @()
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
    # Get-AzSubscription -SubscriptionId still tries to enumerate every other
    # tenant the signed-in account can see in some Az.Accounts builds, which
    # produces a stream of "Authentication failed against tenant <guid> ...
    # rerun Connect-AzAccount with -TenantId <guid>" warnings even though
    # we only asked for one specific subscription. Pass -TenantId explicitly
    # (from the active context) and silence warnings for the call so the
    # production transcript stays clean.
    $activeTenantId = (Get-AzContext).Tenant.Id
    $sub = Get-AzSubscription -SubscriptionId $SubscriptionId -TenantId $activeTenantId -WarningAction SilentlyContinue -ErrorAction Stop |
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
# Cost / usage, KQL queries
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
    # Aggregate-only, the documenter never exports incident bodies (PII).
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
    # without exporting incident detail. FirstModifiedTime can be null when an
    # incident was auto-closed without ever being modified, filter those out
    # of the acknowledge-window average so the result isn't NaN; report the
    # acknowledged subset count separately so the omission is visible.
    $kql = @'
SecurityIncident
| where TimeGenerated > ago(30d)
| summarize arg_max(TimeGenerated, *) by IncidentNumber
| where Status == "Closed"
| extend AckMins  = iff(isnotnull(FirstModifiedTime), datetime_diff('minute', FirstModifiedTime, CreatedTime), int(null))
| extend RsvMins  = iff(isnotnull(ClosedTime),        datetime_diff('minute', ClosedTime,        CreatedTime), int(null))
| summarize
    ClosedCount       = count(),
    AcknowledgedCount = countif(isnotnull(AckMins)),
    MTTAMinutes       = avgif(AckMins, isnotnull(AckMins)),
    MTTRMinutes       = avgif(RsvMins, isnotnull(RsvMins))
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'incidents-mttr.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'incidents-mttr.json' -Data @()
    }
}

Try-Capture 'sentinel-health-summary' {
    $kql = @'
SentinelHealth
| where TimeGenerated > ago(7d)
| summarize LogCount = count() by OperationName, Status
| order by LogCount desc
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'sentinel-health-summary.json' -Data ($r.Results)
    } catch { Save-Json -FileName 'sentinel-health-summary.json' -Data @() }
}

Try-Capture 'la-query-logs' {
    $kql = @'
LAQueryLogs
| where TimeGenerated > ago(7d)
| summarize QueryCount = count()
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'la-query-logs.json' -Data ($r.Results)
    } catch { Save-Json -FileName 'la-query-logs.json' -Data @() }
}

Try-Capture 'workspace-locks' {
    # Resource locks scoped to the workspace.
    $locks = Invoke-SentinelRest -Path "$workspaceResourceId/providers/Microsoft.Authorization/locks" -ApiVersion '2016-09-01'
    Save-Json -FileName 'workspace-locks.json' -Data $locks
}

Try-Capture 'available-service-tiers' {
    $tiers = Invoke-SentinelRest -Path "$workspaceResourceId/availableServiceTiers" -ApiVersion '2020-08-01'
    Save-Json -FileName 'available-service-tiers.json' -Data $tiers
}

Try-Capture 'workspace-usage' {
    # Compact set of usage scalars sourced from the Usage table. Total +
    # billable 30d, plus 14d peak / billable-peak / billable-average. Returned
    # as a single object so the renderer doesnt need five sequential reads.
    $kql = @'
let Total30d        = Usage | where TimeGenerated > ago(30d) | summarize TotalGB = round(sum(Quantity)/1024, 3);
let Billable30d     = Usage | where TimeGenerated > ago(30d) | where IsBillable == true | summarize BillableTotalGB = round(sum(Quantity)/1024, 3);
let Peak14d         = Usage | where TimeGenerated > ago(14d) | summarize DailyGB = round(sum(Quantity)/1024, 3) by bin(TimeGenerated, 1d) | summarize PeakDailyGB = max(DailyGB);
let BillablePeak14d = Usage | where TimeGenerated > ago(14d) | where IsBillable == true | summarize DailyGB = round(sum(Quantity)/1024, 3) by bin(TimeGenerated, 1d) | summarize BillablePeakDailyGB = max(DailyGB);
let BillableAvg14d  = Usage | where TimeGenerated > ago(14d) | where IsBillable == true | summarize DailyGB = round(sum(Quantity)/1024, 3) by bin(TimeGenerated, 1d) | summarize BillableAvgDailyGB = round(avg(DailyGB), 3);
Total30d
| extend BillableTotalGB     = toscalar(Billable30d)
| extend PeakDailyGB         = toscalar(Peak14d)
| extend BillablePeakDailyGB = toscalar(BillablePeak14d)
| extend BillableAvgDailyGB  = toscalar(BillableAvg14d)
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'workspace-usage.json' -Data ($r.Results)
    } catch {
        Save-Json -FileName 'workspace-usage.json' -Data @()
    }
}

Try-Capture 'incidents-detail-by-provider' {
    # SecurityIncident <-> SecurityAlert join with the first-rule indirection
    # producing per-provider, per-product, per-rule incident detail. Aggregate
    # counts only, no incident bodies or alert payloads.
    $kql = @'
SecurityIncident
| where TimeGenerated > ago(8d)
| summarize arg_max(TimeGenerated, *) by IncidentNumber
| extend FirstRule = tostring(RelatedAnalyticRuleIds[0])
| mv-expand AID = AlertIds
| extend Alert = tostring(AID)
| join kind=inner (
    SecurityAlert
    | where TimeGenerated > ago(8d)
    | project SystemAlertId, ProviderName, ProductName
) on $left.Alert == $right.SystemAlertId
| summarize AlertCount = count() by ProviderName, ProductName, FirstRule
| top 100 by AlertCount
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'incidents-detail-by-provider.json' -Data ($r.Results)
    } catch {
        Save-Json -FileName 'incidents-detail-by-provider.json' -Data @()
    }
}

Try-Capture 'incidents-daily-metrics' {
    # Daily incident-flow metrics over the last 7 days, complementary to
    # the MTTA/MTTR aggregate above.
    $kql = @'
SecurityIncident
| where TimeGenerated > ago(8d)
| where CreatedTime between(ago(8d) .. ago(1d))
| summarize DailyUnique = dcount(IncidentNumber), DailyCount = count() by bin(CreatedTime, 1d)
| summarize
    AvgDailyUniqueIncidents = round(avg(DailyUnique), 1),
    PeakDailyNewIncidents   = max(DailyCount)
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'incidents-daily-metrics.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'incidents-daily-metrics.json' -Data @()
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

# AMA vs MMA migration status broken down by machine type. Categorises every
# machine that heartbeated in the last 7 days into Azure VM / VMSS / Arc-enabled
# / Hybrid-without-Arc / Containers / Other, and reports per-category counts
# plus the migration state (Not Started / In Progress / Completed) based on
# the presence of Direct Agent (MMA) vs Azure Monitor Agent records.
Try-Capture 'ama-mma-migration' {
    $kql = @'
Heartbeat
| where TimeGenerated > ago(7d)
| summarize arg_max(TimeGenerated, *) by Category, Computer
| extend MachineType = case(
    ComputerEnvironment == "Non-Azure" and isempty(_ResourceId), "Hybrid without Arc",
    ResourceProvider == "Microsoft.ContainerService", "Containers",
    ComputerEnvironment == "Non-Azure" and ResourceProvider == "Microsoft.HybridCompute", "Arc-enabled",
    ComputerEnvironment == "Azure" and ResourceType == "virtualMachines", "Azure VM",
    ComputerEnvironment == "Azure" and ResourceType == "virtualMachineScaleSets", "VMSS",
    "Other")
| summarize
    MachineCount = count(),
    MMACount     = countif(Category == "Direct Agent"),
    AMACount     = countif(Category == "Azure Monitor Agent")
    by MachineType
| extend MigrationStatus = case(
    MMACount != 0 and AMACount != 0, "In Progress",
    AMACount != 0 and MMACount == 0, "Completed",
    "Not Started")
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'ama-mma-migration.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'ama-mma-migration.json' -Data @()
    }
}

Try-Capture 'data-exports' {
    $exports = Invoke-SentinelRest -Path "$workspaceResourceId/dataExports" -ApiVersion $apiVersions.OperationalInsights
    Save-Json -FileName 'data-exports.json' -Data $exports
}

Try-Capture 'threat-intel-counts' {
    # KQL on the indicator tables, counts only, never indicator detail.
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

# Second TI capture source, the Sentinel TI metrics API. Independent of the
# Az.OperationalInsights module + KQL path above, so the section can still
# render when one source fails. The renderer prefers metrics when both
# present (it carries an indicator-type breakdown the KQL summary doesn't).
Try-Capture 'threat-intel-metrics' {
    $metrics = Invoke-SentinelRest -Path "$sentinelScope/threatIntelligence/main/metrics" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'threat-intel-metrics.json' -Data $metrics
}

# Data-source hygiene checks. Four independent KQL captures driving section 13.
Try-Capture 'cef-devices' {
    $kql = @'
CommonSecurityLog
| where TimeGenerated > ago(7d)
| summarize LogCount = count() by DeviceVendor, DeviceProduct
| top 100 by LogCount
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'cef-devices.json' -Data ($r.Results)
    } catch { Save-Json -FileName 'cef-devices.json' -Data @() }
}

Try-Capture 'cef-in-syslog' {
    # CEF records that landed in the Syslog table, usually a Linux syslog
    # forwarder misconfiguration that should be split into a dedicated
    # CommonSecurityLog stream.
    $kql = @'
Syslog
| where TimeGenerated > ago(7d)
| where SyslogMessage startswith "0|"
| summarize LogCount = count() by Computer
| top 50 by LogCount
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'cef-in-syslog.json' -Data ($r.Results)
    } catch { Save-Json -FileName 'cef-in-syslog.json' -Data @() }
}

Try-Capture 'security-event-duplicates' {
    # Duplicate SecurityEvent records over a 1-hour window, typically an
    # agent dual-collection misconfiguration (MMA + AMA reporting the same
    # events into the workspace).
    $kql = @'
let SecurityEvents = SecurityEvent
| where TimeGenerated > ago(1h)
| where isnotempty(EventRecordId);
let DuplicateEvents = SecurityEvents
| summarize count() by Computer, EventID, EventRecordId
| where count_ > 1;
let SumPerComputer = DuplicateEvents | summarize LogCount = sum(count_) by Computer;
DuplicateEvents
| summarize DuplicateEventIds = make_set(EventID, 100) by Computer
| top 30 by array_length(DuplicateEventIds)
| lookup SumPerComputer on Computer
| project Computer, LogCount, DuplicateEventIds
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'security-event-duplicates.json' -Data ($r.Results)
    } catch { Save-Json -FileName 'security-event-duplicates.json' -Data @() }
}

Try-Capture 'azure-activity-coverage' {
    # Per-subscription AzureActivity volume, surfaces subscriptions NOT
    # shipping Activity Logs to this workspace.
    $kql = @'
AzureActivity
| where TimeGenerated > ago(7d)
| summarize LogCount = count() by SubscriptionId
| top 200 by LogCount
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'azure-activity-coverage.json' -Data ($r.Results)
    } catch { Save-Json -FileName 'azure-activity-coverage.json' -Data @() }
}

Try-Capture 'azure-diagnostics-providers' {
    $kql = @'
AzureDiagnostics
| where TimeGenerated > ago(7d)
| summarize LogCount = count() by ResourceProvider
| top 200 by LogCount
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'azure-diagnostics-providers.json' -Data ($r.Results)
    } catch { Save-Json -FileName 'azure-diagnostics-providers.json' -Data @() }
}

Try-Capture 'xdr-table-presence' {
    # XDR table-presence summary over the known XDR table list. Quick answer
    # to "is Defender XDR connected and producing data?".
    $kql = @'
let tablesOfInterest = dynamic([
    "AlertEvidence","CloudAppEvents","McasShadowItReporting",
    "DeviceEvents","DeviceFileEvents","DeviceImageLoadEvents","DeviceInfo","DeviceLogonEvents",
    "DeviceNetworkEvents","DeviceNetworkInfo","DeviceProcessEvents","DeviceRegistryEvents",
    "DeviceFileCertificateInfo","EmailAttachmentInfo","EmailEvents","EmailPostDeliveryEvents",
    "EmailUrlInfo","UrlClickEvents","IdentityLogonEvents","IdentityQueryEvents","IdentityDirectoryEvents"
]);
union withsource = tt *
| where TimeGenerated > ago(7d)
| summarize RecordCount = count() by Type
| where Type in (tablesOfInterest)
| order by Type asc
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'xdr-table-presence.json' -Data ($r.Results)
    } catch { Save-Json -FileName 'xdr-table-presence.json' -Data @() }
}

Try-Capture 'top-event-ids' {
    # Top 10 Windows event IDs by billable size, drives table-noise tuning.
    $kql = @'
find withsource = TableName1 in (Event, SecurityEvent)
    where TimeGenerated > ago(7d) project _BilledSize, _IsBillable, Computer, _ResourceId, EventID, Activity, RenderedDescription
| where _IsBillable == true
| summarize ["BilledSizeGB"] = round(sum(_BilledSize)/1000/1000/1000, 3) by TableName = TableName1, EventID, Activity, RenderedDescription
| extend EventDescription = iif(isempty(Activity), RenderedDescription, Activity)
| project-away RenderedDescription, Activity
| project-reorder TableName, EventID, EventDescription, BilledSizeGB
| top 10 by BilledSizeGB desc
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'top-event-ids.json' -Data ($r.Results)
    } catch { Save-Json -FileName 'top-event-ids.json' -Data @() }
}

Try-Capture 'analytics-rule-volumes' {
    # Per-rule alert volume from SecurityAlert. Drives the 'top noisy rules'
    # breakout (TOC 4.11.2). Note: SecurityAlert's severity column is named
    # `AlertSeverity`, not `Severity`, an earlier version of this KQL used
    # `Severity` which the workspace rejected with BadRequest, returning an
    # empty array and leaving section 21 unpopulated.
    $kql = @'
SecurityAlert
| where TimeGenerated > ago(30d)
| summarize Alerts = count() by AlertName, ProductName, AlertSeverity
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

# Diagnostic pass, sanity-check captures that typically contain data on
# any active workspace. Empty results here are NOT necessarily a bug
# (some files legitimately empty on quiet workspaces), but they almost
# always indicate either an RBAC gap, an unsupported region, or an
# undocumented schema change, and they're the single most common
# source of "the renderer says zero of X but I have a hundred"
# regressions. Surface them prominently in the run log so the operator
# notices before opening a bug.
$expectNonEmpty = @(
    'alert-rules.json',
    'data-connectors-classic.json',
    'workspace.json',
    'workspace-tables.json'
)
$expectIfActive = @(
    'automation-rules.json',
    'watchlists.json',
    'playbooks.json',
    'hunting-queries.json',
    'workbooks-saved.json',
    'cost-estimate.json'
)

Write-Host ""
Write-Host "##[section]Capture summary"
Write-Host "============================================================"

$captureRows = New-Object System.Collections.Generic.List[pscustomobject]
foreach ($f in ($expectNonEmpty + $expectIfActive)) {
    $p = Join-Path $rawOut $f
    if (-not (Test-Path $p)) {
        $captureRows.Add([pscustomobject]@{ File = $f; Items = '(missing)'; Status = 'ERROR'; Reason = 'File not written' })
        continue
    }
    $raw = Get-Content -Path $p -Raw
    $count = 0
    $isSingleObj = ($raw.TrimStart().StartsWith('{'))
    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($isSingleObj) {
            # Single-object file (cost-estimate, workspace, settings, ...), empty if `{}`.
            $count = if ($raw.Trim() -eq '{}' -or $null -eq $parsed -or @($parsed.PSObject.Properties).Count -eq 0) { 0 } else { 1 }
        } else {
            $count = if ($null -eq $parsed) { 0 } else { @($parsed).Count }
        }
    } catch {
        $captureRows.Add([pscustomobject]@{ File = $f; Items = '(parse error)'; Status = 'ERROR'; Reason = $_.Exception.Message })
        continue
    }
    $status = if ($count -gt 0) {
        'OK'
    } elseif ($expectNonEmpty -contains $f) {
        'EMPTY (unexpected)'
    } else {
        'EMPTY (verify)'
    }
    $captureRows.Add([pscustomobject]@{ File = $f; Items = $count; Status = $status; Reason = '' })
}
$captureRows | Format-Table -AutoSize | Out-String | Write-Host

if ($script:CaptureErrors.Count -gt 0) {
    Write-Host ""
    Write-Host "##[warning]$($script:CaptureErrors.Count) capture step(s) raised an error and were skipped:"
    foreach ($e in $script:CaptureErrors) {
        Write-Host "  - [$($e.Label)]  $($e.Message)"
    }
}

$suspectEmpty = $captureRows | Where-Object { $_.Status -like 'EMPTY*' -or $_.Status -eq 'ERROR' }
if ($suspectEmpty) {
    Write-Host ""
    Write-Host "##[warning]The capture(s) above are usually populated on an active workspace."
    Write-Host "If you expected non-zero counts: check RBAC (Microsoft Sentinel Reader at workspace scope is required for automation rules, watchlists, hunting queries, and incidents), and confirm the workspace has been used since deployment."
}

Write-Information "✓ Sentinel inventory exported to $rawOut"
