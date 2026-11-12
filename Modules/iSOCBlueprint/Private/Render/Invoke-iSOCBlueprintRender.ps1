#Requires -Version 7.6

<#
.SYNOPSIS
    Render the collected inventory into the Blueprint section model and Markdown.

.DESCRIPTION
    Entry point of the renderer. Sets up the run, then calls each step in
    order: Read-BlueprintInventory loads _raw/, and one Write-Blueprint*Section
    function per report section writes its page. The steps share their figures
    through a render context (a hashtable): each takes what it needs from it
    and leaves what later sections need.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Invoke-iSOCBlueprintRender.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCBlueprintRender {
    <#
    .SYNOPSIS
        Render the JSON snapshot under SecurityDocs/<workspace>/_raw/ into the
        section model (sections/*.json) and the Markdown report beside it.

    .DESCRIPTION
        A pure file-to-file transformation with no Azure dependency, so it can
        be exercised end to end by Pester fixtures without auth, and a re-run
        produces the same output for the same input.

        Each section is written as the section model, sections/<id>.json
        (Modules/iSOCBlueprint/Engine/Schemas/section.schema.json), with
        sections/index.json listing them in order. The Markdown files are the
        same sections as a Markdown pack, for the docs pull request and the
        Word report; -OutputFormat Json skips them.

        Strict mode is turned off for the run. The inventory holds JSON shapes
        from many Azure REST endpoints whose property graphs differ between API
        versions, and strict mode would force every read to be guarded.

    .PARAMETER WorkspaceName
        Workspace name. Titles the sections and defaults InputRoot and OutputRoot.

    .PARAMETER InputRoot
        Workspace root that contains _raw/. Defaults to ./SecurityDocs/<WorkspaceName>.

    .PARAMETER OutputRoot
        Folder for the rendered output. Defaults to InputRoot.

    .PARAMETER ResourcesRoot
        Folder holding best-practices.json, mitre-attack.json and the other
        reference files.

    .PARAMETER OutputFormat
        Markdown (NN-name.md), Json (sections/NN-name.json and
        sections/index.json), or both (the default).

    .EXAMPLE
        Invoke-iSOCBlueprintRender -WorkspaceName 'law-sentinel-prod' -ResourcesRoot $resources

        Renders ./SecurityDocs/law-sentinel-prod/_raw into the section model
        and the Markdown pack beside it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkspaceName,

        [string] $InputRoot,

        [string] $OutputRoot,

        [Parameter(Mandatory)]
        [string] $ResourcesRoot,

        [ValidateSet('Markdown', 'Json')]
        [string[]] $OutputFormat = @('Markdown', 'Json')
    )

    Set-StrictMode -Off
    $ErrorActionPreference = 'Stop'
    $InformationPreference = 'Continue'

    if (-not $InputRoot) {
        $InputRoot = Join-Path -Path (Get-Location).ProviderPath -ChildPath "SecurityDocs/$WorkspaceName"
    }
    if (-not $OutputRoot) { $OutputRoot = $InputRoot }

    $rawRoot = Join-Path $InputRoot '_raw'
    if (-not (Test-Path $rawRoot)) {
        throw "Renderer cannot find raw inventory at $rawRoot. Run Export-SentinelInventory.ps1 first."
    }
    if (-not (Test-Path $OutputRoot)) {
        New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    }

    $script:RawRoot = $rawRoot
    $script:OutputRoot = $OutputRoot
    $script:WorkspaceName = $WorkspaceName

    # Finding ids known to the rule catalogue. The auto-linker in
    # Write-BlueprintSection only links these, so a maturity criterion id that
    # no rule shares stays plain text.
    $script:FindingIds = @{}
    $bestPracticesPath = Join-Path $ResourcesRoot 'best-practices.json'
    if (Test-Path -LiteralPath $bestPracticesPath) {
        foreach ($rule in @((Get-Content -LiteralPath $bestPracticesPath -Raw | ConvertFrom-Json -Depth 8).rules)) {
            if ($rule -and $rule.PSObject.Properties['id'] -and $rule.id) { $script:FindingIds[[string]$rule.id] = $true }
        }
    }

    # Output formats. The section model is what the SharePoint site reads; the
    # Markdown pack feeds the docs pull request and the Word report.
    $script:WriteMarkdown = $OutputFormat -contains 'Markdown'
    $script:WriteJson = $OutputFormat -contains 'Json'
    $script:SectionsRoot = Join-Path $OutputRoot 'sections'
    $script:SectionIndex = [System.Collections.Generic.List[object]]::new()
    $script:SectionMeta = $null
    $script:PagesWritten = 0
    $script:BpWindow = $null
    if ($script:WriteJson -and -not (Test-Path $script:SectionsRoot)) {
        New-Item -ItemType Directory -Path $script:SectionsRoot -Force | Out-Null
    }

    $context = @{
        rawRoot       = $rawRoot
        OutputRoot    = $OutputRoot
        ResourcesRoot = $ResourcesRoot
        WorkspaceName = $WorkspaceName
    }

    $steps = @(
        'Read-BlueprintInventory'
        'Write-BlueprintOverviewSection'
        'Write-BlueprintDataConnectorsSection'
        'Write-BlueprintDataConnectorsSectionPart2'
        'Write-BlueprintMitreCoverageSection'
        'Write-BlueprintMitreCoverageSectionPart2'
        'Write-BlueprintMitreCoverageSectionPart3'
        'Write-BlueprintHuntingQueriesSection'
        'Write-BlueprintParsersFunctionsSection'
        'Write-BlueprintWorkbooksSection'
        'Write-BlueprintWatchlistsSection'
        'Write-BlueprintAutomationRulesPlaybooksSection'
        'Write-BlueprintContentHubSection'
        'Write-BlueprintWorkspaceSection'
        'Write-BlueprintWorkspaceSectionPart2'
        'Write-BlueprintTablePlansRetentionSection'
        'Write-BlueprintTablePlansRetentionSectionPart2'
        'Write-BlueprintDedicatedClusterSection'
        'Write-BlueprintDataCollectionSection'
        'Write-BlueprintDataCollectionSectionPart2'
        'Write-BlueprintCostEstimateSection'
        'Write-BlueprintCostEstimateSectionPart2'
        'Write-BlueprintRbacSection'
        'Write-BlueprintSubscriptionContextSection'
        'Write-BlueprintGapAnalysisSection'
        'Write-BlueprintLiveSnapshotSection'
        'Write-BlueprintDeprecatedLegacyFeaturesSection'
        'Write-BlueprintWhatsNewSection'
        'Write-BlueprintMaturityAssessmentSection'
        'Write-BlueprintSentinelHealthSection'
        'Write-BlueprintSocOptimizationSection'
        'Write-BlueprintDataSourceHygieneSection'
        'Write-BlueprintCoverageBreakdownsSection'
        'Write-BlueprintIncidentsSection'
        'Write-BlueprintIncidentsSectionPart2'
        'Write-BlueprintAlertsSection'
        'Write-BlueprintAnalyticsRulesSection'
        'Write-BlueprintAnalyticsRulesSectionPart2'
        'Write-BlueprintRulePerformanceSection'
        'Write-BlueprintRuleHealthQualitySection'
        'Write-BlueprintUebaSection'
        'Write-BlueprintThreatIntelligenceSection'
        'Write-BlueprintThreatIntelligenceSectionPart2'
        'Write-BlueprintDetectionOpportunitiesSection'
        'Write-BlueprintDataExportSection'
        'Write-BlueprintSearchRestoreSection'
        'Write-BlueprintSummaryRulesSection'
        'Write-BlueprintAzureMonitorAgentsSection'
        'Write-BlueprintSentinelDataLakeSection'
        'Write-BlueprintSentinelDataLakeSectionPart2'
        'Write-BlueprintSentinelDataLakeSectionPart3'
        'Write-BlueprintRetentionSection'
        'Write-BlueprintReferencesMicrosoftSection'
        'Write-BlueprintIndexSection'
    )
    foreach ($step in $steps) { & $step -Context $context }

    if ($script:WriteJson) {
        # sections/index.json: every section in reading order.
        $ordered = @($script:SectionIndex | Sort-Object @{ Expression = { if ($null -eq $_.order) { [int]::MaxValue } else { $_.order } } }, @{ Expression = { $_.id } })
        [ordered]@{ schemaVersion = 1; meta = $script:SectionMeta; sections = $ordered } |
            ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $script:SectionsRoot 'index.json') -Encoding utf8
    }

    # One line for the run log; -Verbose lists each page as it is written.
    $rendered = @()
    if ($script:WriteMarkdown) { $rendered += "$($script:PagesWritten) Markdown pages" }
    if ($script:WriteJson) { $rendered += "$(@($script:SectionIndex).Count) JSON sections" }
    Write-Information "Report: $($rendered -join ' and ') to $OutputRoot"
}
