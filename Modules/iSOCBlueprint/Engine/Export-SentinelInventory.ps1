#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.OperationalInsights, Az.Resources, Az.Monitor, Az.SecurityInsights, Az.LogicApp

<#
.SYNOPSIS
    Export every Microsoft Sentinel artefact, the supporting Log Analytics + DCR layer,
    subscription context and 30-day usage to a SecurityDocs/<workspace>/_raw/ folder.

.DESCRIPTION
    Read-only inventory tool. Designed to run in the daily 'sentinel-blueprint' workflow
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

.PARAMETER PlaybookResourceGroup
    Resource group holding the Logic App playbooks, when they do not live
    alongside the workspace. Defaults to -ResourceGroup.

.PARAMETER TargetMaturityLevel
    Maturity level (1 to 5) the workspace is aiming for in the maturity
    assessment. Sets the gap and the roadmap in _raw/maturity.json.
    Defaults to 3 (Established).

.EXAMPLE
    ./Modules/iSOCBlueprint/Engine/Export-SentinelInventory.ps1 `
        -ResourceGroup 'rg-sentinel-prod' `
        -WorkspaceName 'law-sentinel-prod'

    Exports the full inventory to ./SecurityDocs/law-sentinel-prod/_raw/.

.EXAMPLE
    ./Modules/iSOCBlueprint/Engine/Export-SentinelInventory.ps1 `
        -ResourceGroup 'rg-sentinel-prod' `
        -WorkspaceName 'law-sentinel-prod' `
        -PlaybookResourceGroup 'rg-soar-prod' `
        -IncludePreview

    Collects playbooks from a separate resource group and uses the preview
    API version where one is available.

.NOTES
    File:           Modules/iSOCBlueprint/Engine/Export-SentinelInventory.ps1
    Repository:     Sentinel-As-Code
    Author:         noodlemctwoodle
    Website:        https://sentinel.blog
    Created:        2026-05-06
    Version:        0.5.2
    Last Updated:   2026-10-13
    Component:      iSOC Blueprint
    Requires:       PowerShell 7.2+, Az.Accounts, Az.SecurityInsights, Az.OperationalInsights, Az.Monitor, Az.Resources, Az.LogicApp

    API versions:
      - Azure Resource Graph : 2022-10-01
      - Everything else      : passed per collector through Invoke-SentinelRest,
                               so a provider version can be bumped in one place
                               without touching this script

    Credit and thanks: many of the captures added to match the health
    check (rule effectiveness and run health, hunts, playbook runs, the
    agent heartbeat mix, threat intelligence volumes and indicator
    health, among others) are based on the Sentinel health-check script
    by thinkndle, kindly given to the Sentinel-As-Code project. Thank
    you, thinkndle, for sharing your work so generously; it shaped much
    of the Blueprint's health, coverage and maturity reporting.

.LINK
    https://learn.microsoft.com/azure/governance/resource-graph/first-query-rest-api

.LINK
    https://learn.microsoft.com/rest/api/securityinsights/alert-rules
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
    [string]$OutputRoot = (Join-Path -Path (Get-Location).ProviderPath -ChildPath 'SecurityDocs'),

    # Logic Apps resource group. Sentinel-As-Code allows playbooks to live in a
    # separate resource group from the workspace (the `playbookResourceGroup`
    # pipeline variable). Defaults to the Sentinel resource group when unset.
    [Parameter(Mandatory = $false)]
    [string]$PlaybookResourceGroup,

    [Parameter(Mandatory = $false)]
    [switch]$IncludePreview,

    # Maturity level (1-5) the workspace is aiming for. Drives the gap and
    # roadmap in the maturity assessment; 3 (Established) is the default.
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 5)]
    [int]$TargetMaturityLevel = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# ---------------------------------------------------------------------------
# Module bootstrap
# ---------------------------------------------------------------------------
# API versions are hardcoded here rather than read from Blueprint.psd1.
# Reading the manifest at script start was failing silently on the ADO Linux
# agent, with $apiVersions arriving empty inside Try-Capture's child scope, 
# every subsequent REST call then fired without an api-version and Azure
# returned 400 'MissingApiVersionParameter'. Inlining the table removes the
# external file as a moving part. Keep these values in sync with the
# 'ApiVersions' block in Blueprint.psd1 and the table in Blueprint-References.md.
$apiVersions = @{
    Sentinel              = '2024-09-01'
    SentinelPreview       = '2024-10-01-preview'
    OperationalInsights   = '2025-02-01'
    Tables                = '2025-02-01'
    DataCollection        = '2023-03-11'
}
$blueprintVersion = [string](Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot '../iSOCBlueprint.psd1')).ModuleVersion

. (Join-Path $PSScriptRoot 'Private/Invoke-SentinelRest.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-AzureRetailPrice.ps1')

# Sentinel.Common's KQL identifier extractor sits behind the table-reference
# captures. The module carries its own copy of the two functions used
# (Private/Vendor), so it needs nothing from the repository around it.
. (Join-Path $PSScriptRoot 'Private/Vendor/SentinelCommon.Kql.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-KqlTableReferences.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-DefenderCustomDetections.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-SearchRestoreTable.ps1')

# Shared between captures: each Try-Capture body runs in its own scope.
$script:AlertRules         = @()
$script:AlertRuleTemplates = @()
$script:Workflows          = @()
$script:GapOutcomes        = $null

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
        'subscription.json','dedicated-cluster.json','maturity.json','bookmarks-count.json'
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
    # Who ran the collector: a user, a service principal or a managed identity.
    Account           = [string]$ctx.Account.Id
    AccountType       = [string]$ctx.Account.Type
    ResourceGroup     = $ResourceGroup
    WorkspaceName     = $WorkspaceName
    WorkspaceResourceId = $workspaceResourceId
    StartedAtUtc      = (Get-Date).ToUniversalTime().ToString('o')
    ApiVersions       = $apiVersions
    BlueprintVersion = $blueprintVersion
    AzPSVersion       = (Get-Module -ListAvailable Az.Accounts | Sort-Object Version -Descending | Select-Object -First 1).Version.ToString()
    IncludePreview    = [bool]$IncludePreview
    ScriptCommit      = $(if (Get-Command git -ErrorAction SilentlyContinue) { (& git -C $PSScriptRoot rev-parse HEAD 2>$null) -as [string] } else { $null })
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
    # 2025-02-01 carries schema.tableSubType (Classic or DCR-based),
    # lastPlanModifiedDate and the *AsDefault retention flags. A region or
    # cloud that does not serve it yet falls back to 2023-09-01.
    try {
        $tables = Invoke-SentinelRest -Path "$workspaceResourceId/tables" -ApiVersion $apiVersions.Tables
    } catch {
        Write-Warning "Tables API $($apiVersions.Tables) not served ($($_.Exception.Message)); falling back to 2023-09-01."
        $tables = Invoke-SentinelRest -Path "$workspaceResourceId/tables" -ApiVersion '2023-09-01'
    }
    Save-Json -FileName 'workspace-tables.json' -Data $tables
    # Search jobs and restores leave _SRCH and _RST tables behind; they are
    # the record the maturity model (SAC-INV-02) and the search and restore
    # page read.
    $found = Get-SearchRestoreTable -Tables @($tables)
    Save-Json -FileName 'search-jobs.json' -Data @($found.SearchJobs)
    Save-Json -FileName 'restore-logs.json' -Data @($found.Restores)
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
    # The preview API: each rule's sub-techniques come in their own
    # subTechniques array, which every GA version leaves out (the MITRE page
    # needs it). A tenant that refuses the preview call gets the GA list,
    # without sub-techniques, and a warning in the run log.
    $rules = try {
        Invoke-SentinelRest -Path "$sentinelScope/alertRules" -ApiVersion $apiVersions.SentinelPreview
    } catch {
        Write-Warning "alertRules $($apiVersions.SentinelPreview) not served ($($_.Exception.Message)); falling back to $($apiVersions.Sentinel), which leaves out sub-techniques."
        Invoke-SentinelRest -Path "$sentinelScope/alertRules" -ApiVersion $apiVersions.Sentinel
    }
    $script:AlertRules = @($rules)
    Save-Json -FileName 'alert-rules.json' -Data $rules
}

Try-Capture 'alert-rule-templates' {
    $templates = Invoke-SentinelRest -Path "$sentinelScope/alertRuleTemplates" -ApiVersion $apiVersions.Sentinel
    $script:AlertRuleTemplates = @($templates)
    Save-Json -FileName 'alert-rule-templates.json' -Data $templates
}

Try-Capture 'rule-table-references' {
    # Which tables each rule and each template reads, resolved here with
    # the vendored Sentinel.Common KQL helpers so the gap engine and the
    # renderers read plain JSON.
    Save-Json -FileName 'rule-table-references.json' -Data (Get-RuleTableReferences -AlertRules $script:AlertRules)
    Save-Json -FileName 'template-table-references.json' -Data (Get-TemplateTableReferences -Templates $script:AlertRuleTemplates -AlertRules $script:AlertRules)
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
    # The list API refuses a response over about 8 MB ("Bookmarks response
    # is too large (N bytes, M items)") and has no paging. The message does
    # carry the item count, so on that error the count is kept in
    # bookmarks-count.json: the hunting rule and the maturity criterion then
    # know bookmarks exist without the list itself.
    try {
        $bm = Invoke-SentinelRest -Path "$sentinelScope/bookmarks" -ApiVersion $apiVersions.Sentinel
        Save-Json -FileName 'bookmarks.json' -Data $bm
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'too large[^)]*?(\d+)\s+items') {
            $count = [int]$Matches[1]
            Write-Warning "Bookmarks list refused as too large; keeping the count the service reported ($count)."
            Save-Json -FileName 'bookmarks-count.json' -Data ([pscustomobject]@{ Count = $count; Source = 'The bookmarks list was refused as too large; the count is the one the service reported.' })
        } else {
            throw
        }
    }
}

Try-Capture 'hunts' {
    # Hunts exist only on preview api-versions. A tenant or region that does
    # not serve them answers 4xx, which Invoke-SentinelRest throws and
    # Try-Capture reports, so no file is written and consumers treat hunting
    # activity as unknown rather than as absent.
    $hunts = Invoke-SentinelRest -Path "$sentinelScope/hunts" -ApiVersion $apiVersions.SentinelPreview
    Save-Json -FileName 'hunts.json' -Data $hunts
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
    (BehaviorAnalytics  | where TimeGenerated > ago(14d) | extend TableName = "BehaviorAnalytics"),
    (IdentityInfo       | where TimeGenerated > ago(14d) | extend TableName = "IdentityInfo"),
    (UserPeerAnalytics  | where TimeGenerated > ago(14d) | extend TableName = "UserPeerAnalytics")
| summarize Count = countif(TimeGenerated > ago(12d)), Count7d = countif(TimeGenerated > ago(7d)), Count14d = count() by TableName
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
    $script:Workflows = @($workflows)
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

Try-Capture 'playbook-runs' {
    # Run health per playbook over the last 7 days, one bounded call per
    # enabled workflow. Disabled workflows get a zero row without a call. A
    # failure on one workflow is logged and the others are still recorded.
    $since = (Get-Date).ToUniversalTime().AddDays(-7).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $runRows = @()
    foreach ($wf in $script:Workflows) {
        if ($null -eq $wf) { continue }
        $wfName = [string]$wf.name
        $state = ''
        if ($wf.PSObject.Properties.Name -contains 'properties' -and $null -ne $wf.properties -and
            $wf.properties.PSObject.Properties.Name -contains 'state') { $state = [string]$wf.properties.state }
        $row = [ordered]@{ Playbook = $wfName; Id = [string]$wf.id; Runs7d = 0; Failed7d = 0; LastFailureUtc = $null; LastRunStatus = $null; Note = $null }
        if ($state -eq 'Enabled') {
            try {
                $runs = @(Invoke-SentinelRest -Path "$($wf.id)/runs?`$top=250&`$filter=startTime ge $since" -ApiVersion '2016-06-01')
                $runs = @($runs | Where-Object { $null -ne $_ -and $_.PSObject.Properties.Name -contains 'properties' })
                $failed = @($runs | Where-Object { [string]$_.properties.status -in @('Failed', 'TimedOut', 'Aborted') })
                $row.Runs7d = $runs.Count
                $row.Failed7d = $failed.Count
                if ($runs.Count -gt 0) {
                    $latest = $runs | Sort-Object { [datetime]$_.properties.startTime } -Descending | Select-Object -First 1
                    $row.LastRunStatus = [string]$latest.properties.status
                }
                if ($failed.Count -gt 0) {
                    $lastFailed = $failed | Sort-Object { [datetime]$_.properties.startTime } -Descending | Select-Object -First 1
                    $row.LastFailureUtc = [string]$lastFailed.properties.startTime
                }
            } catch {
                # Marked so consumers can tell "no runs" from "could not read".
                $row.LastRunStatus = 'Unavailable'
                $row.Note = "Run history not readable: $($_.Exception.Message)"
                Write-Warning "Run history for playbook $wfName failed: $($_.Exception.Message)"
            }
        }
        $runRows += [pscustomobject]$row
    }
    Save-Json -FileName 'playbook-runs.json' -Data $runRows
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

Try-Capture 'linked-storage-accounts' {
    # Customer-owned storage the workspace writes to (custom logs, query
    # results, alerts, ingestion), one entry per data source type.
    $lsa = Invoke-SentinelRest -Path "$workspaceResourceId/linkedStorageAccounts" -ApiVersion '2020-08-01'
    Save-Json -FileName 'linked-storage-accounts.json' -Data $lsa
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
    IngestedLast7d  = sumif(Quantity, TimeGenerated > ago(7d)) / 1024.0,
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
    Events      = count(),
    LastEvent   = max(TimeGenerated),
    Statuses    = make_set(Status),
    Failures    = countif(Status != "Success"),
    LastFailure = maxif(TimeGenerated, Status != "Success")
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
    # Aggregate-only, the Blueprint never exports incident bodies (PII).
    # The bags hold counts per key. ByClassification covers closed incidents
    # only; an empty classification is reported as "Unclassified".
    # OpenBySeverity counts the incidents not closed. ClosedBy says who closed
    # each closed incident, from the first record that shows it Closed:
    # an automation rule (ModifiedBy contains "Automation", the test
    # Microsoft's automation rule guide uses), Defender XDR (closed there and
    # synced), an analyst (a user principal name), or Other; only the
    # category leaves the workspace, never the name.
    $kql = @'
let inc = SecurityIncident
| where TimeGenerated > ago(30d)
| summarize arg_max(TimeGenerated, *) by IncidentNumber;
let byStatus = inc | summarize N = count() by Status   | summarize B = make_bag(bag_pack(Status, N), 100);
let bySev    = inc | summarize N = count() by Severity | summarize B = make_bag(bag_pack(Severity, N), 100);
let byClass  = inc
| where Status == "Closed"
| extend C = iff(isempty(Classification), "Unclassified", Classification)
| summarize N = count() by C
| summarize B = make_bag(bag_pack(C, N), 100);
let byProvider = inc
| extend P = iff(isempty(ProviderName), "Unknown", ProviderName)
| summarize N = count() by P
| summarize B = make_bag(bag_pack(P, N), 100);
let openBySev = inc | where Status != "Closed" | summarize N = count() by Severity | summarize B = make_bag(bag_pack(Severity, N), 100);
let closing = SecurityIncident
| where TimeGenerated > ago(30d) and Status == "Closed"
| summarize arg_min(TimeGenerated, ModifiedBy) by IncidentNumber;
let closedBy = inc
| where Status == "Closed"
| project IncidentNumber
| join kind=leftouter closing on IncidentNumber
| extend By = case(ModifiedBy contains "Automation", "AutomationRule",
                   ModifiedBy has_any ("Microsoft 365 Defender", "Microsoft Defender XDR", "Microsoft XDR"), "DefenderXdr",
                   ModifiedBy contains "@", "Analyst",
                   "Other")
| summarize N = count() by By
| summarize B = make_bag(bag_pack(By, N), 100);
let isUnified = (p: string, a: string) { p in ("Microsoft 365 Defender", "Microsoft XDR") or a has_any ("Microsoft 365 Defender", "Microsoft XDR") };
inc
| extend Recent = TimeGenerated > ago(7d), IsUnified = isUnified(ProviderName, tostring(AdditionalData))
| summarize Count = count(), Closed = countif(Status == "Closed"),
    Unified = countif(IsUnified),
    Count7d = countif(Recent), Closed7d = countif(Recent and Status == "Closed"),
    FalsePositive7d = countif(Recent and Classification == "FalsePositive"),
    TruePositive7d = countif(Recent and Classification == "TruePositive"),
    Unified7d = countif(Recent and IsUnified)
| extend ByStatus = toscalar(byStatus), BySeverity = toscalar(bySev), ByClassification = toscalar(byClass), ByProvider = toscalar(byProvider),
    OpenBySeverity = toscalar(openBySev), ClosedBy = toscalar(closedBy)
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
    MTTRMinutes       = avgif(RsvMins, isnotnull(RsvMins)),
    ClosedCount7d     = countif(TimeGenerated > ago(7d)),
    MTTAMinutes7d     = avgif(AckMins, isnotnull(AckMins) and TimeGenerated > ago(7d)),
    MTTRMinutes7d     = avgif(RsvMins, isnotnull(RsvMins) and TimeGenerated > ago(7d))
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
| order by AlertCount desc
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

# Agents by OS, agent category (Azure Monitor Agent, Direct Agent for MMA,
# SCOM) and version over 7 days: the heartbeat mix behind the AMA migration.
Try-Capture 'agent-heartbeat-mix' {
    $kql = @'
Heartbeat
| where TimeGenerated > ago(7d)
| extend OSVersion = strcat(OSName, " ", OSMajorVersion, ".", OSMinorVersion)
| summarize Computers = dcount(Computer), LastSeen = max(TimeGenerated) by OSType, Category, Version, OSVersion
| order by Computers desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'agent-heartbeat-mix.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'agent-heartbeat-mix.json' -Data @()
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
| extend IndicatorKey = coalesce(tostring(column_ifexists("Id", "")), tostring(column_ifexists("IndicatorId", "")))
| summarize Count = count(), Indicators = dcount(IndicatorKey), Last = max(TimeGenerated) by SourceSystem = coalesce(SourceSystem, Source)
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
# Records in each threat intelligence table, current and legacy, with the
# first and last record in 30 days: the table migration status on page 27.
# A table that exists but is empty still returns a row of zeros.
Try-Capture 'threat-intel-tables' {
    $kql = @'
union isfuzzy=true
    (ThreatIntelIndicators       | where TimeGenerated > ago(30d) | summarize Records30d = count(), Records7d = countif(TimeGenerated > ago(7d)), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated) | extend Table = "ThreatIntelIndicators"),
    (ThreatIntelObjects          | where TimeGenerated > ago(30d) | summarize Records30d = count(), Records7d = countif(TimeGenerated > ago(7d)), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated) | extend Table = "ThreatIntelObjects"),
    (ThreatIntelligenceIndicator | where TimeGenerated > ago(30d) | summarize Records30d = count(), Records7d = countif(TimeGenerated > ago(7d)), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated) | extend Table = "ThreatIntelligenceIndicator")
| project Table, Records30d, Records7d, FirstSeen, LastSeen
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'threat-intel-tables.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'threat-intel-tables.json' -Data @()
    }
}

# Indicator health over 30 days, each indicator at its latest state: how
# many are active, deleted, revoked and still within their validity.
Try-Capture 'threat-intel-health' {
    $kql = @'
ThreatIntelIndicators
| where TimeGenerated > ago(30d)
| summarize arg_max(TimeGenerated, *) by Id
| summarize Total = count(),
    Active = countif(IsActive == true and IsDeleted == false),
    Deleted = countif(IsDeleted == true),
    Revoked = countif(Revoked == true),
    StillValid = countif(isnull(ValidUntil) or ValidUntil > now())
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'threat-intel-health.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'threat-intel-health.json' -Data @()
    }
}

Try-Capture 'taxii-clients' {
    # TAXII clients on the workspace's threat intelligence. The path is not in
    # the published REST reference, so it is tried on three api-versions and a
    # service that does not serve it leaves an empty list; the TI connectors
    # stay the primary feed signal on page 27.
    $clients = @()
    foreach ($v in @($apiVersions.Sentinel, '2024-03-01', '2023-11-01')) {
        try {
            $clients = Invoke-SentinelRest -Path "$sentinelScope/threatIntelligence/main/taxiiClients" -ApiVersion $v
            break
        } catch {
            $clients = @()
        }
    }
    Save-Json -FileName 'taxii-clients.json' -Data $clients
}

Try-Capture 'cef-devices' {
    $kql = @'
CommonSecurityLog
| where TimeGenerated > ago(7d)
| summarize LogCount = count() by DeviceVendor, DeviceProduct
| order by LogCount desc
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
| where SyslogMessage startswith "0|" or SyslogMessage startswith "CEF:"
| extend Parts = split(SyslogMessage, "|")
| extend ProductVendor = strcat(tostring(Parts[1]), "-", tostring(Parts[2]))
| summarize LogCount = count() by Computer, ProductVendor
| order by LogCount desc
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
| summarize DuplicateEventIds = make_set(EventID), DuplicateRecords = count() by Computer
| order by DuplicateRecords desc
| lookup SumPerComputer on Computer
| project Computer, DuplicateRecords, LogCount, DuplicateEventIds
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
| order by LogCount desc
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
| order by LogCount desc
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
| summarize ["BilledSizeGB"] = round(sum(_BilledSize)/1000/1000/1000, 3), LogCount = count() by TableName = TableName1, EventID, Activity, RenderedDescription
| extend EventDescription = iif(isempty(Activity), RenderedDescription, Activity)
| project-away RenderedDescription, Activity
| project-reorder TableName, EventID, EventDescription, BilledSizeGB, LogCount
| order by BilledSizeGB desc
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
| summarize Alerts = count(), Alerts7d = countif(TimeGenerated > ago(7d)), ProviderName = take_any(ProviderName)
    by AlertName, ProductName, AlertSeverity
| order by Alerts desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'analytics-rule-volumes.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'analytics-rule-volumes.json' -Data @()
    }
}

Try-Capture 'rule-effectiveness' {
    # Incident outcomes per detection: each incident is counted once
    # (arg_max per IncidentNumber), the SecurityAlert side is time-bounded,
    # and Sentinel rules are keyed on the Analytic Rule Id carried in the
    # alert's ExtendedProperties (an array on current alerts, a scalar on
    # older ones). Alerts from other products (Defender XDR, Entra ID
    # Protection, Purview) carry no rule id and are keyed on the alert name
    # with Source set to the product, so a page can tell the two apart.
    # Sentinel rules sort first so the row cap never drops them.
    $kql = @'
let w = 30d;
let alerts = SecurityAlert
| where TimeGenerated > ago(w)
| extend ep = parse_json(ExtendedProperties)
| extend AlertRuleId = tolower(coalesce(tostring(parse_json(tostring(ep["Analytic Rule Ids"]))[0]), tostring(ep["Analytic Rule Id"])))
| summarize arg_max(TimeGenerated, AlertName, AlertRuleId, ProductName, ProviderName) by SystemAlertId;
SecurityIncident
| where TimeGenerated > ago(w)
| summarize arg_max(TimeGenerated, *) by IncidentNumber
| project IncidentNumber, Status, Classification, AlertIds
| mv-expand AlertId = AlertIds to typeof(string)
| join kind=inner alerts on $left.AlertId == $right.SystemAlertId
| extend RuleKey = iff(isempty(AlertRuleId), AlertName, AlertRuleId)
| summarize AlertRuleId = any(AlertRuleId), RuleName = any(AlertName),
    Product = any(ProductName), Provider = any(ProviderName),
    Incidents = dcount(IncidentNumber),
    Closed = dcountif(IncidentNumber, Status == "Closed"),
    TruePositive = dcountif(IncidentNumber, Classification == "TruePositive"),
    FalsePositive = dcountif(IncidentNumber, Classification == "FalsePositive"),
    BenignPositive = dcountif(IncidentNumber, Classification == "BenignPositive"),
    Undetermined = dcountif(IncidentNumber, Status == "Closed" and (Classification == "Undetermined" or isempty(Classification)))
    by RuleKey
| extend FPRate = round(100.0 * FalsePositive / iff(Closed == 0, 1, Closed), 1)
| extend Source = iff(isempty(AlertRuleId), coalesce(Product, Provider, "Other"), "Analytics rule")
| extend IsRule = isnotempty(AlertRuleId)
| order by IsRule desc, Incidents desc
| project-away RuleKey, IsRule
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'rule-effectiveness.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'rule-effectiveness.json' -Data @()
    }
}

Try-Capture 'rules-fired' {
    # Which Sentinel scheduled and NRT rules produced alerts in 30 days,
    # keyed on rule id so renamed or dynamically named alerts still match.
    $kql = @'
SecurityAlert
| where TimeGenerated > ago(30d)
| where ProviderName in ("ASI Scheduled Alerts", "ASI NRT Alerts")
| extend ep = parse_json(ExtendedProperties)
| extend AlertRuleId = tolower(coalesce(tostring(parse_json(tostring(ep["Analytic Rule Ids"]))[0]), tostring(ep["Analytic Rule Id"])))
| summarize arg_max(TimeGenerated, AlertName, AlertRuleId) by SystemAlertId
| summarize AlertRuleId = any(AlertRuleId), AlertName = any(AlertName), Alerts = count(), LastAlert = max(TimeGenerated)
    by RuleKey = iff(isempty(AlertRuleId), AlertName, AlertRuleId)
| project-away RuleKey
| order by Alerts desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'rules-fired.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'rules-fired.json' -Data @()
    }
}

Try-Capture 'workspace-usage-daily' {
    $kql = @'
Usage
| where TimeGenerated > ago(30d)
| summarize BillableGB = round(sumif(Quantity, IsBillable == true) / 1024.0, 3),
            FreeGB     = round(sumif(Quantity, IsBillable == false) / 1024.0, 3)
    by Day = bin(TimeGenerated, 1d)
| order by Day asc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'workspace-usage-daily.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'workspace-usage-daily.json' -Data @()
    }
}

Try-Capture 'azure-diagnostics-categories' {
    # Category-level view of AzureDiagnostics, used to spot resources logging
    # through both the legacy categories and resource-specific tables.
    $kql = @'
AzureDiagnostics
| where TimeGenerated > ago(7d)
| summarize LogCount = count() by ResourceProvider, Category
| order by LogCount desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'azure-diagnostics-categories.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'azure-diagnostics-categories.json' -Data @()
    }
}

# Azure Firewall rows by category, legacy (AzureFirewall*) and
# resource-specific (AZFW*), asked for by name so a small legacy category
# is not lost below the top 100 of azure-diagnostics-categories.
Try-Capture 'azure-firewall-categories' {
    $kql = @'
AzureDiagnostics
| where TimeGenerated > ago(7d)
| where Category in ("AzureFirewallApplicationRule", "AzureFirewallNetworkRule", "AzureFirewallDnsProxy",
                     "AZFWApplicationRule", "AZFWNetworkRule", "AZFWDnsQuery", "AZFWNatRule",
                     "AZFWThreatIntel", "AZFWIdpsSignature")
| summarize LogCount = count() by Category
| order by Category asc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'azure-firewall-categories.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'azure-firewall-categories.json' -Data @()
    }
}

Try-Capture 'threat-intel-objects' {
    $kql = @'
ThreatIntelObjects
| where TimeGenerated > ago(30d)
| summarize Count = count() by StixType
| order by Count desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'threat-intel-objects.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'threat-intel-objects.json' -Data @()
    }
}

# Rule run health: analytics rules whose scheduled runs failed in the last
# 7 days, from SentinelHealth. Empty is the healthy case.
Try-Capture 'rule-health' {
    $kql = @'
SentinelHealth
| where TimeGenerated > ago(7d)
| where SentinelResourceType == "Analytics Rule" and Status != "Success"
| summarize Failures = count(), LastFailure = max(TimeGenerated), Reason = any(Description) by RuleName = SentinelResourceName, Status
| order by Failures desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'rule-health.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'rule-health.json' -Data @()
    }
}

# Incident titles over 30 days with volume, closure speed and verdicts:
# the input to the automation-opportunities table (frequent, fast-closing
# or mostly-false-positive titles). Aggregates only, no per-incident rows.
Try-Capture 'incident-title-stats' {
    $kql = @'
SecurityIncident
| where TimeGenerated > ago(30d)
| summarize arg_max(TimeGenerated, *) by IncidentNumber
| extend MinsToClose = iff(Status == "Closed", datetime_diff("minute", ClosedTime, CreatedTime), int(null))
| summarize Total = count(), Closed = countif(Status == "Closed"), Severity = any(Severity),
    AvgMinsToClose = round(avg(MinsToClose), 1), ClosedWithinHour = countif(Status == "Closed" and MinsToClose <= 60),
    FP = countif(Classification == "FalsePositive"), TP = countif(Classification == "TruePositive"), BP = countif(Classification == "BenignPositive")
    by Title
| where Total >= 5
| order by Total desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'incident-title-stats.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'incident-title-stats.json' -Data @()
    }
}

# Indicators by observable type over 30 days: the current ThreatIntelIndicators
# schema first, the retired ThreatIntelligenceIndicator table when the
# current one is absent.
Try-Capture 'threat-intel-by-type' {
    $kqlModern = @'
ThreatIntelIndicators
| where TimeGenerated > ago(30d)
| extend ObservableType = tostring(split(tostring(ObservableKey), ':')[0])
| extend Type = case(
    ObservableType startswith "ipv4" or ObservableType startswith "ipv6", "IP",
    ObservableType == "domain-name", "Domain",
    ObservableType == "url", "URL",
    ObservableType == "file", "FileHash",
    ObservableType == "email-addr" or ObservableType == "email-message", "Email",
    isempty(ObservableType), "Unspecified",
    ObservableType)
| summarize Count = count(), Indicators = dcount(Id) by Type
| order by Count desc
'@
    $kqlLegacy = @'
ThreatIntelligenceIndicator
| where TimeGenerated > ago(30d)
| extend Type = case(
    isnotempty(NetworkIP) or isnotempty(NetworkSourceIP) or isnotempty(NetworkDestinationIP), "IP",
    isnotempty(DomainName), "Domain",
    isnotempty(Url), "URL",
    isnotempty(FileHashValue), "FileHash",
    isnotempty(EmailSenderAddress), "Email",
    "Other")
| summarize Count = count(), Indicators = dcount(IndicatorId) by Type
| order by Count desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kqlModern -ErrorAction Stop
        Save-Json -FileName 'threat-intel-by-type.json' -Data ($result.Results)
    } catch {
        try {
            $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kqlLegacy -ErrorAction Stop
            Save-Json -FileName 'threat-intel-by-type.json' -Data ($result.Results)
        } catch {
            Save-Json -FileName 'threat-intel-by-type.json' -Data @()
        }
    }
}

# Log composition: who writes Syslog and SecurityEvent, by host (and
# facility for Syslog), with billed size, over 7 days.
Try-Capture 'syslog-contributors' {
    $kql = @'
Syslog
| where TimeGenerated > ago(7d)
| summarize LogCount = count(), SizeMB = round(sum(_BilledSize) / 1024.0 / 1024.0, 1) by Computer, Facility
| order by LogCount desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'syslog-contributors.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'syslog-contributors.json' -Data @()
    }
}

Try-Capture 'securityevent-top-hosts' {
    $kql = @'
SecurityEvent
| where TimeGenerated > ago(7d)
| summarize LogCount = count(), SizeMB = round(sum(_BilledSize) / 1024.0 / 1024.0, 1) by Computer
| order by LogCount desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        Save-Json -FileName 'securityevent-top-hosts.json' -Data ($result.Results)
    } catch {
        Save-Json -FileName 'securityevent-top-hosts.json' -Data @()
    }
}

# Audited queries per lake-retained table (LAQueryLogs, 30 days): the
# usage evidence for tables that keep data in the lake beyond analytics
# retention or route to the lake only. Targets come from the
# workspace-tables capture written earlier in this run. Tables go in
# batches of 60 so the query text stays short; a failed batch fails the
# capture, so the pages read "not captured" rather than "no queries".
Try-Capture 'table-query-usage' {
    $targets = @()
    $tablesPath = Join-Path $rawOut 'workspace-tables.json'
    if (Test-Path -LiteralPath $tablesPath) {
        $wsTables = @(Get-Content -LiteralPath $tablesPath -Raw | ConvertFrom-Json -Depth 32)
        foreach ($t in $wsTables) {
            if (-not $t -or -not $t.PSObject.Properties['properties'] -or -not $t.properties) { continue }
            $pr = $t.properties
            $plan = if ($pr.PSObject.Properties['plan']) { [string]$pr.plan } else { '' }
            $r = if ($pr.PSObject.Properties['retentionInDays'] -and $pr.retentionInDays) { [int]$pr.retentionInDays } else { 0 }
            $tr = if ($pr.PSObject.Properties['totalRetentionInDays'] -and $pr.totalRetentionInDays) { [int]$pr.totalRetentionInDays } else { 0 }
            if ($plan -eq 'DataLake' -or $tr -gt $r) { $targets += [string]$t.name }
        }
    }
    $targets = @($targets | Where-Object { $_ -match '^[A-Za-z0-9_]+$' } | Sort-Object -Unique)
    $usage = [System.Collections.Generic.List[object]]::new()
    for ($b = 0; $b -lt $targets.Count; $b += 60) {
        $batch = @($targets[$b..([math]::Min($b + 59, $targets.Count - 1))])
        $list = ($batch | ForEach-Object { '"' + $_ + '"' }) -join ','
        $kql = @"
LAQueryLogs
| where TimeGenerated > ago(30d)
| extend Q = tolower(tostring(QueryText))
| mv-apply T = dynamic([$list]) to typeof(string) on (
    where Q contains tolower(T)
    | project T
)
| summarize Queries = count(), Users = dcount(AADEmail), LastQuery = max(TimeGenerated) by Table = T
"@
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query $kql -ErrorAction Stop
        foreach ($row in @($result.Results)) { if ($row) { $usage.Add($row) } }
    }
    Save-Json -FileName 'table-query-usage.json' -Data @($usage | Sort-Object @{ Expression = { [long]$_.Queries }; Descending = $true }, Table)
}

# Defender XDR custom detections: the other detection logic that reads this
# data. Microsoft Graph, beta security/rules/detectionRules, needs
# CustomDetection.Read.All on the identity; a 403 is recorded as "not
# captured" rather than "none". Table references are resolved with the same
# extractor as the Sentinel rules so coverage counts both.
Try-Capture 'defender-custom-detections' {
    $detections = @(Get-DefenderCustomDetections)
    Save-Json -FileName 'defender-custom-detections.json' -Data $detections
    Save-Json -FileName 'custom-detection-table-references.json' -Data @(Get-CustomDetectionTableReferences -Detections $detections)
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
    $gapOutcomes = [System.Collections.Generic.List[object]]::new()
    $findings = Get-SentinelGap `
        -InputRoot $rawOut `
        -ResourcesRoot (Join-Path $PSScriptRoot 'Private/Resources') `
        -RulesPath (Join-Path $PSScriptRoot 'Private/Resources/best-practices.json') `
        -GapChecksPath (Join-Path $PSScriptRoot 'Private/GapChecks.ps1') `
        -OutcomeCollector $gapOutcomes
    Save-Json -FileName 'gap-analysis.json' -Data $findings
    # One record per rule (Fired / Passed / Errored / Undefined), so a
    # consumer can tell a check that passed from one that never ran.
    $script:GapOutcomes = $gapOutcomes.ToArray()
    Save-Json -FileName 'gap-checks.json' -Data $script:GapOutcomes
}

# ---------------------------------------------------------------------------
# Maturity assessment, scored from the gap outcomes and the captures above.
# A failed gap-analysis leaves $script:GapOutcomes null; the engine then
# reads gap-checks.json if an earlier run left one, else every rule-backed
# criterion is Unknown rather than Gap.
# ---------------------------------------------------------------------------
Try-Capture 'maturity' {
    . (Join-Path $PSScriptRoot 'Private/Get-SentinelMaturity.ps1')
    $maturity = Get-SentinelMaturity `
        -InputRoot $rawOut `
        -ResourcesRoot (Join-Path $PSScriptRoot 'Private/Resources') `
        -CriteriaPath (Join-Path $PSScriptRoot 'Private/Resources/maturity-criteria.json') `
        -GapOutcomes $script:GapOutcomes `
        -TargetLevel $TargetMaturityLevel
    Save-Json -FileName 'maturity.json' -Data $maturity
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
    'workspace-tables.json',
    'rule-table-references.json'
)
$expectIfActive = @(
    'automation-rules.json',
    'watchlists.json',
    'playbooks.json',
    'hunting-queries.json',
    'workbooks-saved.json',
    'cost-estimate.json',
    'rule-effectiveness.json',
    'rules-fired.json',
    'incident-title-stats.json',
    'playbook-runs.json',
    'workspace-usage-daily.json'
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

Write-Information "Sentinel inventory exported to $rawOut"
