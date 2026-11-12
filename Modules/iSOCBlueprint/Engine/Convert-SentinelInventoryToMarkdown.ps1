#Requires -Version 7.6
#Requires -Modules powershell-yaml

<#
.SYNOPSIS
    Render the JSON snapshot under SecurityDocs/<workspace>/_raw/ into the section model
    (SecurityDocs/<workspace>/sections/*.json) and the Markdown report beside it.

.DESCRIPTION
    Pure file-to-file transformation — no Azure dependency. Designed so the renderer can
    be exercised end-to-end by Pester fixtures without auth, and so a re-run produces the
    same output for the same input (idempotent).

    Each section is written as the section model, sections/<id>.json
    (Modules/iSOCBlueprint/Engine/Schemas/section.schema.json: typed blocks, structured text
    runs, charts as data; no Markdown), with sections/index.json listing them in
    order. That is what the SharePoint site is built from. The Markdown files are
    the same sections as a Markdown pack, for the docs pull request and the Word
    report; -OutputFormat Json skips them.

    Sections produced (one file of each format, plus index):

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
    Modules/iSOCBlueprint/Engine/Private/Resources.

.PARAMETER OutputFormat
    Which formats to write: Markdown (NN-name.md), Json (sections/NN-name.json and
    sections/index.json), or both (the default). The SharePoint site needs only Json.

.EXAMPLE
    ./Modules/iSOCBlueprint/Engine/Convert-SentinelInventoryToMarkdown.ps1 `
        -WorkspaceName 'law-sentinel-prod'

    Renders the Markdown section files from the inventory that
    Export-SentinelInventory.ps1 previously collected.

.EXAMPLE
    ./Modules/iSOCBlueprint/Engine/Convert-SentinelInventoryToMarkdown.ps1 `
        -InputRoot     './SecurityDocs/law-sentinel-prod/_raw' `
        -OutputRoot    './SecurityDocs/law-sentinel-prod' `
        -WorkspaceName 'law-sentinel-prod'

    Renders from an explicit collection folder, for regenerating the
    document set from an archived inventory.

.NOTES
    File:           Modules/iSOCBlueprint/Engine/Convert-SentinelInventoryToMarkdown.ps1
    Repository:     Sentinel-As-Code
    Author:         noodlemctwoodle
    Website:        https://sentinel.blog
    Created:        2026-05-06
    Version:        0.8.2
    Last Updated:   2026-11-09
    Component:      iSOC Blueprint, Renderer
    Requires:       PowerShell 7.6+, powershell-yaml

    Credit and thanks: the estate flow, the detection opportunities
    page, the automation opportunities title-to-action map, the rule
    complexity idea and the page sections added to match the health
    check's report are based on the Sentinel health-check script by
    thinkndle, kindly given to the Sentinel-As-Code project. Thank you,
    thinkndle, for sharing your work so generously; it shaped much of
    the Blueprint's health, coverage and maturity reporting.
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
    [string]$ResourcesRoot = (Join-Path $PSScriptRoot 'Private/Resources'),

    [Parameter(Mandatory = $false)]
    [ValidateSet('Markdown', 'Json')]
    [string[]]$OutputFormat = @('Markdown', 'Json')
)

# The renderer itself lives in Modules/iSOCBlueprint/Private/Render as functions,
# one file per helper and per report section. This script is its command-line
# entry point: it loads them, with the shared helpers from Private/, and runs
# Invoke-iSOCBlueprintRender.
foreach ($helper in 'Format-BlueprintText', 'Get-EffectiveConnectors', 'Get-TableFamily', 'Get-AttackCoverage',
    'Get-SearchRestoreTable', 'Get-TemplateSolution', 'Get-WatchlistFreshness', 'Get-ConnectorCatalogue',
    'Get-FindingMaturityLink', 'Get-TableTierProfile', 'ConvertFrom-BlueprintMermaid', 'ConvertTo-BlueprintSection') {
    . (Join-Path $PSScriptRoot "Private/$helper.ps1")
}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '../Private/Render') -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
    . $file.FullName
}

Invoke-iSOCBlueprintRender @PSBoundParameters -ResourcesRoot $ResourcesRoot
