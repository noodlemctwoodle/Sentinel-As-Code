#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 83-data-collection.md (part 1 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/DataCollection/Write-BlueprintDataCollectionSection.ps1
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
function Write-BlueprintDataCollectionSection {
    <#
    .SYNOPSIS
        Build the figures for and write 83-data-collection.md (part 1 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSPossibleIncorrectComparisonWithNull', '', Justification = 'The left side is deliberately a collection (one value per data flow); -ne $null filters the empty ones.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'ccfTitleByName', Justification = 'Read by Get-BlueprintTopologyBucket from this function scope, which the analyser cannot see.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $bucket = $Context.bucket
    $ccfTitleByName = $Context.ccfTitleByName
    $dcrs = $Context.dcrs
    $effective = $Context.effective
    $enabledRules = $Context.enabledRules
    $m365DefenderConnected = $Context.m365DefenderConnected
    $p = $Context.p
    $playbooks = $Context.playbooks
    $r = $Context.r
    $workbooksSaved = $Context.workbooksSaved
    $workspace = $Context.workspace
    $workspaceResourceId = $Context.workspaceResourceId
    $workspaceTables = $Context.workspaceTables

    # ---------------------------------------------------------------------------
    # Section: 83 — data collection
    # ---------------------------------------------------------------------------
    $dces = Read-BlueprintRawArray 'dces.json'

    $dcrsInScope = @()
    $dcrsOutOfScope = @()
    foreach ($d in $dcrs) {
        if (Test-BlueprintDcrTargetsWorkspace -Dcr $d -WorkspaceId $workspaceResourceId) { $dcrsInScope += $d } else { $dcrsOutOfScope += $d }
    }

    $dcrRows = $dcrsInScope | ForEach-Object {
        $streams = ($_.properties.dataFlows | ForEach-Object { $_.streams } | Sort-Object -Unique) -join ', '
        [pscustomobject]@{
            Name         = $_.name
            Kind         = $_.kind
            Streams      = $streams
            HasTransform = if (($_.properties.dataFlows.transformKql) -ne $null) { 'Yes' } else { '' }
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
        [pscustomobject]@{ Name = $_.name; Location = Get-BlueprintRegionName ([string]$_.location) }
    }

    $sourceBuckets = @{}
    foreach ($e in $effective) {
        $bucket = Get-BlueprintTopologyBucket -Table $e.Table -Source $e.Source -Identifier $e.Identifier
        if (-not $sourceBuckets.ContainsKey($bucket)) { $sourceBuckets[$bucket] = 0 }
        $sourceBuckets[$bucket]++
    }
    # Order: highest item-count first, with the "Other sources" catch-all
    # always last regardless of count.
    $sortedBuckets = $sourceBuckets.GetEnumerator() |
        Sort-Object @{ Expression = { if ($_.Key -eq 'Other sources') { 1 } else { 0 } } }, @{ Expression = { - $_.Value } }, Key |
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
        $label = if ($b.Count -gt 1) { "$($b.Name) · $(Format-BlueprintCount $b.Count)" } else { $b.Name }
        # Wrap label in double quotes — Mermaid flowchart treats `(` as a
        # node-shape directive, so unquoted labels containing parens parse-
        # error with "Expecting SQE/PE/STADIUMEND etc.".
        "    $shortId[`"$label`"]"
    }
    if ($overflowBuckets.Count -gt 0) {
        $srcLines += "    S99[`"Other sources · $(Format-BlueprintCount $overflowTotal)`"]"
        $sourceEdges += '    S99 --> WS'
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
    $sentinelDataLake = Read-BlueprintRawArray 'sentinel-data-lake.json'
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
        $r = [int]($t.properties.retentionInDays | ForEach-Object { if ($_) { $_ } else { 0 } })
        $tr = [int]($t.properties.totalRetentionInDays | ForEach-Object { if ($_) { $_ } else { 0 } })
        if ($tr -gt $r -and $tr -gt 0) { $archiveTables++ }
    }
    $hasBasic = $plansInUse.ContainsKey('Basic')
    $hasAuxiliary = $plansInUse.ContainsKey('Auxiliary')
    $hasDataLake = $plansInUse.ContainsKey('DataLake') -or @($sentinelDataLake).Count -gt 0 -or $unifiedBilling
    $hasArchive = $archiveTables -gt 0

    $wspNodes = @(
        '        WS[(Log Analytics workspace)]', "        RUL[Analytics rules · $(Format-BlueprintCount $enabledRules.Count)]", '        INC[Incidents]'
    )
    $wspEdges = @('    WS --> RUL', '    RUL --> INC')
    if ($hasBasic) { $wspNodes += '        BAS[Basic plan tables]'; $wspEdges += '    WS --> BAS' }
    if ($hasAuxiliary) { $wspNodes += '        AUX[Auxiliary plan tables]'; $wspEdges += '    WS --> AUX' }
    if ($hasDataLake) { $wspNodes += '        DL[(Sentinel Data Lake)]'; $wspEdges += '    WS --> DL' }
    if ($hasArchive) { $wspNodes += "        ARC[(Long-term archive · $(Format-BlueprintPlural $archiveTables 'table'))]"; $wspEdges += '    WS --> ARC' }

    # Downstream — render only the destinations the capture supports.
    $dataExports = Read-BlueprintRawArray 'data-exports.json'
    $dataExportCount = @($dataExports).Count
    $hasPlaybooks = @($playbooks).Count -gt 0

    $dstNodes = @()
    $dstEdges = @()
    if ($m365DefenderConnected) {
        $dstNodes += '        XDR[Defender XDR portal]'
        $dstEdges += '    INC --> XDR'
    }
    if ($hasPlaybooks) {
        $dstNodes += "        PB[Playbooks · $(Format-BlueprintCount @($playbooks).Count)]"
        $dstEdges += '    INC --> PB'
    }
    if ($dataExportCount -gt 0) {
        $dstNodes += "        EXP[Data export · $(Format-BlueprintPlural $dataExportCount 'destination')]"
        $dstEdges += '    WS --> EXP'
    }
    # Always-on destination — workbooks consume workspace data regardless
    # of incidents. Surface it so the topology shows the reporting flow.
    if (@($workbooksSaved).Count -gt 0) {
        $dstNodes += "        WB[Workbooks · $(Format-BlueprintCount @($workbooksSaved).Count)]"
        $dstEdges += '    WS --> WB'
    }
    $hasDownstream = $dstNodes.Count -gt 0
    # The topology as data for the SharePoint graphic: every source family
    # (none rolled up), the table plans in use and not, and the destinations.
    $planTableCounts = @{}
    foreach ($t in $workspaceTables) {
        $pl = [string]$t.properties.plan
        if ($pl) { if (-not $planTableCounts.ContainsKey($pl)) { $planTableCounts[$pl] = 0 }; $planTableCounts[$pl]++ }
    }
    $planDetail = {
        param([string]$Plan) if ($planTableCounts.ContainsKey($Plan)) {
            "$($planTableCounts[$Plan]) table$(if ($planTableCounts[$Plan] -ne 1) { 's' })"
        } else { 'In use' }
    }
    $topologyVisualLine = Format-VisualLine -Kind 'topology' -Data ([ordered]@{
            sources     = @($sortedBuckets | ForEach-Object { [ordered]@{ name = [string]$_.Name; count = [int]$_.Count } })
            sourceTotal = @($effective).Count
            rules       = $enabledRules.Count
            plans       = @(
                [ordered]@{ name = 'Analytics'; inUse = $true; detail = 'Default plan' }
                [ordered]@{ name = 'Basic'; inUse = $hasBasic; detail = (& $planDetail 'Basic') }
                [ordered]@{ name = 'Auxiliary'; inUse = $hasAuxiliary; detail = (& $planDetail 'Auxiliary') }
                [ordered]@{ name = 'Data Lake'; inUse = $hasDataLake; detail = 'Enrolled' }
                [ordered]@{ name = 'Long-term archive'; inUse = $hasArchive; detail = "$archiveTables table$(if ($archiveTables -ne 1) { 's' })" }
            )
            downstream  = @(
                [ordered]@{ name = 'Defender XDR portal'; inUse = [bool]$m365DefenderConnected; detail = 'Connected' }
                [ordered]@{ name = 'Playbooks'; inUse = $hasPlaybooks; detail = (Format-BlueprintCount @($playbooks).Count) }
                [ordered]@{ name = 'Data export'; inUse = ($dataExportCount -gt 0); detail = "$dataExportCount destination$(if ($dataExportCount -ne 1) { 's' })" }
                [ordered]@{ name = 'Workbooks'; inUse = (@($workbooksSaved).Count -gt 0); detail = (Format-BlueprintCount @($workbooksSaved).Count) }
            )
        })
    $dstClassLine = ''
    if ($hasDownstream) {
        $dstIds = $dstNodes | ForEach-Object { ($_ -split '\[')[0].Trim() }
        $dstClassLine = "    class $($dstIds -join ',') dst"
    }

    # Left in the render context for later sections.
    $Context.d = $d
    $Context.dceRows = $dceRows
    $Context.dcrOutOfScopeRows = $dcrOutOfScopeRows
    $Context.dcrRows = $dcrRows
    $Context.dstClassLine = $dstClassLine
    $Context.dstEdges = $dstEdges
    $Context.dstNodes = $dstNodes
    $Context.hasArchive = $hasArchive
    $Context.hasAuxiliary = $hasAuxiliary
    $Context.hasBasic = $hasBasic
    $Context.hasDataLake = $hasDataLake
    $Context.hasDownstream = $hasDownstream
    if (Get-Variable -Name 'label' -Scope 0 -ErrorAction Ignore) { $Context.label = $label }
    if (Get-Variable -Name 'p' -Scope 0 -ErrorAction Ignore) { $Context.p = $p }
    if (Get-Variable -Name 'r' -Scope 0 -ErrorAction Ignore) { $Context.r = $r }
    $Context.sentinelDataLake = $sentinelDataLake
    $Context.sourceEdges = $sourceEdges
    $Context.srcLines = $srcLines
    $Context.t = $t
    $Context.topologyVisualLine = $topologyVisualLine
    $Context.unifiedBilling = $unifiedBilling
    $Context.wspEdges = $wspEdges
    $Context.wspNodes = $wspNodes
}
