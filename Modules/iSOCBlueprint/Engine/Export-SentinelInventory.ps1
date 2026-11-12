#Requires -Version 7.6
#Requires -Modules Az.Accounts, Az.OperationalInsights, Az.Resources, Az.Monitor, Az.SecurityInsights, Az.LogicApp

<#
.SYNOPSIS
    Export every Microsoft Sentinel artefact, the supporting Log Analytics + DCR layer,
    subscription context and 30-day usage to a SecurityDocs/<workspace>/_raw/ folder.

.DESCRIPTION
    Read-only inventory tool. The collector itself is one function per file under
    Modules/iSOCBlueprint/Private/Collector (Invoke-iSOCBlueprintCollect and its
    captures); this script loads them and runs it with the same parameters.
    Designed to run in the daily 'sentinel-blueprint' workflow
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
    under <OutputRoot>/<WorkspaceName>/_raw/, or <OutputRoot>/<WorkspaceName>/<RunFolder>/_raw/
    with -RunFolder.

.PARAMETER RunFolder
    A folder under the workspace's folder for this run, such as the date
    (yyyy-MM-dd), so a run does not overwrite the last. Empty by default:
    the run writes to the workspace's folder itself.

.PARAMETER IncludePreview
    Use the 2024-10-01-preview API version where applicable (Content Hub product packages,
    summary rules).

.PARAMETER PlaybookResourceGroup
    Resource group holding the Logic App playbooks, when they do not live
    alongside the workspace. Defaults to -ResourceGroup.

.PARAMETER TargetMaturityLevel
    Maturity level (1 to 5) the workspace is aiming for in the maturity
    assessment. Sets the gap and the roadmap in _raw/maturity.json.
    Defaults to 3 (Established).

.PARAMETER Currency
    The currency the cost estimate prices in: Auto (the default) takes it
    from the workspace's region (Resolve-AzureRetailCurrency: UK regions
    GBP, EU regions EUR, and so on), or one of the codes the Azure Retail
    Prices API supports. Billing currency follows the billing account, not
    the region, so set it when the guess is wrong. Recorded in
    run-context.json and, with where it came from, in retail-prices.json.

.PARAMETER LookbackDays
    Days of activity every KQL capture reads, 1 to 730 (default 30). The
    figures for the latest days within it cover the shorter of 7 days and
    this. Recorded in run-context.json as LookbackDays and RecentDays; the
    pages, the dashboard's cards and the findings name their window from
    there. A window longer than a table's interactive retention returns only
    what the table still holds.

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
    Version:        0.12.0
    Last Updated:   2026-11-12
    Component:      iSOC Blueprint
    Requires:       PowerShell 7.6+, Az.Accounts, Az.SecurityInsights, Az.OperationalInsights, Az.Monitor, Az.Resources, Az.LogicApp

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

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[\w.-]*$')]
    [string]$RunFolder,

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
    [int]$TargetMaturityLevel = 3,

    # Days of activity every KQL capture reads (1 to 730): incidents, alerts,
    # usage and cost, health, agents, table activity and the rest. The
    # figures for the latest days within it (the "recent" window) cover the
    # shorter of 7 days and this. Recorded in run-context.json, which every
    # page, card and finding reads its window from.
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 730)]
    [int]$LookbackDays = 30,

    # The currency the cost estimate prices in; Auto takes it from the
    # workspace's region.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'USD', 'AUD', 'BRL', 'CAD', 'CHF', 'CNY', 'DKK', 'EUR', 'GBP', 'INR', 'JPY', 'KRW', 'NOK', 'NZD', 'RUB', 'SEK', 'TWD')]
    [string]$Currency = 'Auto'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

. (Join-Path $PSScriptRoot 'Private/Invoke-SentinelRest.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-AzureRetailPrice.ps1')
. (Join-Path $PSScriptRoot 'Private/Write-CaptureSummary.ps1')

# Sentinel.Common's KQL identifier extractor sits behind the table-reference
# captures. The module carries its own copy of the two functions used
# (Private/Vendor), so it needs nothing from the repository around it.
. (Join-Path $PSScriptRoot 'Private/Vendor/SentinelCommon.Kql.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-KqlTableReferences.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-DefenderCustomDetections.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-SearchRestoreTable.ps1')

# The collector and its captures (the module's own Private/Collector, one
# folder up from here), defined in this scope.
$collectorRoot = Join-Path $PSScriptRoot '..' 'Private' 'Collector'
foreach ($collectorFile in Get-ChildItem -LiteralPath $collectorRoot -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
    . $collectorFile.FullName
}
Remove-Variable -Name collectorFile, collectorRoot

Invoke-iSOCBlueprintCollect @PSBoundParameters -EngineRoot $PSScriptRoot
