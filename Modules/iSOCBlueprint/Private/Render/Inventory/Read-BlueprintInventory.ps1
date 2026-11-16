#Requires -Version 7.6

<#
.SYNOPSIS
    Read the collected inventory into the render context.

.DESCRIPTION
    Loads every JSON file the renderer reads from _raw/ and the figures derived
    from them, and leaves them in the render context for the section writers.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Inventory/Read-BlueprintInventory.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Read-BlueprintInventory {
    <#
    .SYNOPSIS
        Read the collected inventory into the render context.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $rawRoot = $Context.rawRoot
    $ResourcesRoot = $Context.ResourcesRoot

    # ---------------------------------------------------------------------------
    # Section: 00-overview
    # ---------------------------------------------------------------------------
    $workspace          = Read-BlueprintRaw 'workspace.json'
    # How Microsoft Sentinel is billed: the SecurityInsights solution's
    # properties.sku (Unified is simplified pricing, anything else classic).
    $sentinelSolutionSku = ''
    foreach ($sol in @(Read-BlueprintRawArray 'solutions-installed.json' | Where-Object { $_ })) {
        $solPlan = Get-BlueprintRawProperty $sol 'plan' $null
        if (-not $solPlan -or [string](Get-BlueprintRawProperty $solPlan 'product' '') -notmatch 'SecurityInsights$') { continue }
        $solSku = Get-BlueprintRawProperty (Get-BlueprintRawProperty $sol 'properties' $null) 'sku' $null
        if ($solSku) { $sentinelSolutionSku = [string](Get-BlueprintRawProperty $solSku 'name' '') }
    }
    $sentinelPricingText = if (-not $sentinelSolutionSku) { '_(not recorded on the Microsoft Sentinel solution)_' }
        elseif ($sentinelSolutionSku -eq 'Unified') {
            "Simplified: one Microsoft Sentinel meter covers analysis and Log Analytics ingestion (solution SKU ``Unified``)"
        }
        else { "Classic: Microsoft Sentinel analysis and Log Analytics ingestion billed separately (solution SKU ``$sentinelSolutionSku``)" }
    $run                = Read-BlueprintRaw 'run-context.json'
    $rules              = Read-BlueprintRawArray 'alert-rules.json'
    $connectors         = Read-BlueprintRawArray 'data-connectors-classic.json'
    $workbooksSaved     = Read-BlueprintRawArray 'workbooks-saved.json'
    $dcrs               = Read-BlueprintRawArray 'dcrs.json'
    $tablesWithData     = Read-BlueprintRawArray 'tables-with-data.json'
    $workspaceTables    = Read-BlueprintRawArray 'workspace-tables.json'
    $watchlists         = Read-BlueprintRawArray 'watchlists.json'
    $autoRules          = Read-BlueprintRawArray 'automation-rules.json'
    $gapFindings        = Read-BlueprintRawArray 'gap-analysis.json'
    foreach ($gf in @($gapFindings)) {
        foreach ($field in 'Title', 'Evidence', 'Remediation') {
            if ($gf -and $gf.PSObject.Properties[$field] -and $gf.$field -is [string]) { $gf.$field = Format-DatesInText $gf.$field }
        }
    }
    # Ids that fired in this run, so the maturity page links only the criterion
    # ids that have a finding (and an anchor) on 90-gap-analysis.md.
    $script:FiredFindingIds = @{}
    foreach ($gf in @($gapFindings)) { if ($gf -and $gf.PSObject.Properties['Id'] -and $gf.Id) { $script:FiredFindingIds[[string]$gf.Id] = $true } }
    $cost               = Read-BlueprintRaw 'cost-estimate.json'

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
    # The top findings as cards on the SharePoint site and the dashboard: a
    # comment Markdown does not show, read by the section model as a graphic;
    # the list after it stays for the Markdown and Word exports.
    $topFindingsVisual = '<!-- bp:visual finding-cards ' + ([ordered]@{
        total = @($gapFindings).Count
        cards = @($top5Findings | ForEach-Object {
            [ordered]@{
                id = [string]$_.Id; severity = [string]$_.Severity; title = [string]$_.Title; category = [string](Get-BlueprintRawProperty $_ 'Category' '')
                evidence = [string](Get-BlueprintRawProperty $_ 'Evidence' '')
                remediation = [string](Get-BlueprintRawProperty $_ 'Remediation' '')
                learn = [string](Get-BlueprintRawProperty $_ 'Learn' '')
                href = "90-gap-analysis.md#$(([string]$_.Id).ToLowerInvariant())"
            }
        })
    } | ConvertTo-Json -Compress -Depth 6).Replace('-->', '--\u003e') + ' -->'

    # ---------------------------------------------------------------------------
    # Health-check ports, hoisted: table-to-rule references, rule effectiveness,
    # run health, the usage trend and the maturity assessment. Read once here so
    # 00-overview and 01-live-snapshot can draw the estate flow before the
    # sections that own the detail (15, 21, 28, 60, 80, 81, 91) are written.
    # ---------------------------------------------------------------------------
    $ruleTableRefs     = Read-BlueprintRawArray 'rule-table-references.json'
    $templateTableRefs = Read-BlueprintRawArray 'template-table-references.json'
    # Each template's Content Hub solution; a template only deprecated solutions
    # ship (Threat Intelligence, replaced by Threat Intelligence (NEW)) is not
    # one to enable, so it counts nowhere a template is offered.
    $templateSolutionMap = Get-TemplateSolutionMap -Installed @(
        Read-BlueprintRawArray 'content-packages.json'
    ) -Catalogue @(Read-BlueprintRawArray 'content-product-packages.json')
    $customDetectionRefs = Read-BlueprintRawArray 'custom-detection-table-references.json'
    $customDetectionsCaptured = Test-Path -LiteralPath (Join-Path $rawRoot 'defender-custom-detections.json')
    $customDetectionTableSet = @{}
    foreach ($cd in $customDetectionRefs) {
        if ($cd -and (Get-BlueprintRawProperty $cd 'Enabled' $false) -eq $true) {
            foreach ($t in @(Get-BlueprintRawProperty $cd 'Tables' @())) { if ($t) { $customDetectionTableSet[[string]$t] = $true } }
        }
    }
    $ruleEffectiveness = Read-BlueprintRawArray 'rule-effectiveness.json'
    $rulesFired        = Read-BlueprintRawArray 'rules-fired.json'
    $playbookRuns      = Read-BlueprintRawArray 'playbook-runs.json'
    $hunts             = Read-BlueprintRawArray 'hunts.json'
    $bookmarks         = Read-BlueprintRawArray 'bookmarks.json'
    $bookmarksFromLogs = Read-BlueprintRawArray 'bookmarks-from-logs.json'
    $bookmarkCountDoc  = Read-BlueprintRaw 'bookmarks-count.json'
    $ruleVolumesAll    = Read-BlueprintRawArray 'analytics-rule-volumes.json'
    $customDetectionsRaw = Read-BlueprintRawArray 'defender-custom-detections.json'
    $usageDaily        = Read-BlueprintRawArray 'workspace-usage-daily.json'
    $maturity          = Read-BlueprintRaw 'maturity.json'
    if ($maturity) {
        $maturityNotes = @(@(Get-BlueprintRawProperty $maturity 'roadmap' @()) + @(Get-BlueprintRawProperty $maturity 'quickWins' @()))
        foreach ($mArea in @(Get-BlueprintRawProperty $maturity 'areas' @())) { $maturityNotes += @(Get-BlueprintRawProperty $mArea 'criteria' @()) }
        foreach ($note in $maturityNotes) {
            foreach ($field in 'name', 'evidence', 'impact', 'guidance') {
                if ($note -and $note.PSObject.Properties[$field] -and $note.$field -is [string]) { $note.$field = Format-DatesInText $note.$field }
            }
        }
    }
    # A Gap criterion whose id is a finding id means that finding fired, so
    # the maturity page can link it even when gap-analysis.json is partial.
    if ($maturity) {
        foreach ($mArea in @(Get-BlueprintRawProperty $maturity 'areas' @())) {
            foreach ($mCrit in @(Get-BlueprintRawProperty $mArea 'criteria' @())) {
                $mid = [string](Get-BlueprintRawProperty $mCrit 'id' '')
                if ($mid -and (Get-BlueprintRawProperty $mCrit 'status' '') -eq 'Gap' -and $script:FindingIds.ContainsKey($mid)) {
                    $script:FiredFindingIds[$mid] = $true
                }
            }
        }
    }
    $incSummary        = Read-BlueprintRawArray 'incidents-summary.json' | Select-Object -First 1
    $incMttr           = Read-BlueprintRawArray 'incidents-mttr.json'    | Select-Object -First 1
    # A failed maturity capture writes '{}', which is truthy, so test for the
    # members the page needs rather than for the object.
    $maturityOk = ($null -ne $maturity -and $null -ne $maturity.PSObject.Properties['areas'] -and $null -ne $maturity.PSObject.Properties['overall'])

    # What the score is based on and what it covers. A maturity.json from an
    # older collector carries neither, so fall back to the criteria file.
    $maturityBasis = ''
    $maturityScope = ''
    if ($maturityOk) {
        $maturityBasis = [string](Get-BlueprintRawProperty (Get-BlueprintRawProperty $maturity 'methodology') 'basis' '')
        $maturityScope = [string](Get-BlueprintRawProperty (Get-BlueprintRawProperty $maturity 'methodology') 'scope' '')
        $criteriaFile = Join-Path $ResourcesRoot 'maturity-criteria.json'
        if ((-not $maturityBasis -or -not $maturityScope) -and (Test-Path -LiteralPath $criteriaFile)) {
            $criteriaDoc = Get-Content -LiteralPath $criteriaFile -Raw | ConvertFrom-Json
            if (-not $maturityBasis) { $maturityBasis = [string](Get-BlueprintRawProperty $criteriaDoc.methodology 'basis' '') }
            if (-not $maturityScope) { $maturityScope = [string](Get-BlueprintRawProperty $criteriaDoc.methodology 'scope' '') }
        }
    }

    # Left in the render context for later sections.
    $Context.autoRules = $autoRules
    $Context.bookmarkCountDoc = $bookmarkCountDoc
    $Context.bookmarks = $bookmarks
    $Context.bookmarksFromLogs = $bookmarksFromLogs
    $Context.catalogueOnlyCount = $catalogueOnlyCount
    $Context.connectors = $connectors
    $Context.cost = $cost
    $Context.customDetectionRefs = $customDetectionRefs
    $Context.customDetectionsCaptured = $customDetectionsCaptured
    $Context.customDetectionsRaw = $customDetectionsRaw
    $Context.customDetectionTableSet = $customDetectionTableSet
    $Context.dcrs = $dcrs
    $Context.enabledRules = $enabledRules
    $Context.gapFindings = $gapFindings
    $Context.hunts = $hunts
    $Context.incMttr = $incMttr
    $Context.incSummary = $incSummary
    $Context.maturity = $maturity
    $Context.maturityBasis = $maturityBasis
    $Context.maturityOk = $maturityOk
    $Context.maturityScope = $maturityScope
    $Context.operationalTables = $operationalTables
    $Context.playbookRuns = $playbookRuns
    $Context.populatedTableNames = $populatedTableNames
    $Context.populatedTables = $populatedTables
    $Context.ruleEffectiveness = $ruleEffectiveness
    $Context.rules = $rules
    $Context.rulesFired = $rulesFired
    $Context.ruleTableRefs = $ruleTableRefs
    $Context.ruleVolumesAll = $ruleVolumesAll
    $Context.run = $run
    $Context.sentinelPricingText = $sentinelPricingText
    $Context.sol = $sol
    $Context.t = $t
    $Context.tablesWithData = $tablesWithData
    $Context.templateSolutionMap = $templateSolutionMap
    $Context.templateTableRefs = $templateTableRefs
    $Context.top5Findings = $top5Findings
    $Context.topFindingsVisual = $topFindingsVisual
    $Context.usageDaily = $usageDaily
    $Context.watchlists = $watchlists
    $Context.workbooksSaved = $workbooksSaved
    $Context.workspace = $workspace
    $Context.workspaceTables = $workspaceTables
}
