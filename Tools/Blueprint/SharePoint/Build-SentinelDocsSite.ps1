#Requires -Version 7.2

<#
.SYNOPSIS
    Build the iSOC Blueprint SharePoint site bundle from a Sentinel
    Blueprint workspace snapshot.

.DESCRIPTION
    Reads one Blueprint workspace folder (the _raw/*.json snapshot that
    Export-SentinelInventory.ps1 writes and the section model, sections/*.json,
    that Convert-SentinelInventoryToMarkdown.ps1 renders next to it) and
    writes everything Publish-SentinelDocsSite.ps1 needs into one folder.
    No Markdown is read: a run rendered with -OutputFormat Json is enough.
    A snapshot rendered before the section model existed has only the
    NN-name.md files; those are converted on the fly instead.

      index.html          the interactive dashboard: a single self-contained
                          HTML file (inline CSS and JS, data embedded as
                          JSON) that the site's home page hosts
      model.json          the dashboard's data model
      site.json           site descriptor: product name, workspace, the
                          section list with page names, families and hashes
      pages/<page>.json   one file per section: title and the ordered
                          segments (HTML for Text web parts, chart data for
                          the isoc-blueprint chart web part)
      findings.json       gap-analysis findings plus per-check outcomes,
                          for the findings list

    Nothing here talks to SharePoint or Azure, so the bundle can be built
    from a downloaded pipeline artefact and inspected before publishing.
    The one network call is the optional "What's new" feed (Microsoft's
    Azure release-communications RSS), fetched at build time and baked into
    the dashboard. Pass -SkipWhatsNew to build fully offline.

    Charts come from the section model as data. The dashboard draws its own,
    and each section page places the chart web part, which draws the chart
    from that data; nothing is pre-rendered.

.PARAMETER Source
    Blueprint workspace folder: the directory that contains _raw/ and
    sections/ (for example SecurityDocs/law-sentinel-prod).

.PARAMETER OutputRoot
    Bundle folder. Defaults to '<Source>/sharepoint'. The pages/ subfolder
    is cleared at the start of each build so a removed section never
    lingers.

.PARAMETER ProductName
    Product name shown on the dashboard, in page titles and in the site
    descriptor. Defaults to 'iSOC Blueprint'.

.PARAMETER Title
    Dashboard document title. Defaults to '<workspace> - <ProductName>'.

.PARAMETER WorkspaceName
    Override the workspace name. Defaults to the WorkspaceName recorded in
    _raw/run-context.json, else the leaf name of -Source.

.PARAMETER WhatsNewFeedUrl
    RSS feed for the dashboard's "What's new" panel.

.PARAMETER WhatsNewCount
    Number of feed items to keep. Defaults to 8.

.PARAMETER SkipWhatsNew
    Do not fetch the feed. The panel is left out.

.PARAMETER MaxTableRows
    Maximum body rows per table on a native page. Defaults to 500. Longer
    tables are cut with a note linking to the dashboard, whose copy of the
    section has every row.

.OUTPUTS
    [string] The bundle folder path.

.EXAMPLE
    ./Tools/Blueprint/SharePoint/Build-SentinelDocsSite.ps1 `
        -Source ./SecurityDocs/law-sentinel-prod

    Builds the bundle into ./SecurityDocs/law-sentinel-prod/sharepoint.

.EXAMPLE
    ./Tools/Blueprint/SharePoint/Build-SentinelDocsSite.ps1 `
        -Source ./artefact/law-sentinel-prod -SkipWhatsNew -WhatIf

    Shows what would be written without writing anything or fetching the
    feed.

.NOTES
    File:         Tools/Blueprint/SharePoint/Build-SentinelDocsSite.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-07
    Version:      0.4.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [string]$ProductName = 'iSOC Blueprint',

    [Parameter(Mandatory = $false)]
    [string]$Title,

    [Parameter(Mandatory = $false)]
    [string]$WorkspaceName,

    [Parameter(Mandatory = $false)]
    [string]$WhatsNewFeedUrl = 'https://www.microsoft.com/releasecommunications/api/v2/azure/rss',

    [Parameter(Mandatory = $false)]
    [int]$WhatsNewCount = 8,

    [switch]$SkipWhatsNew,

    [Parameter(Mandatory = $false)]
    [int]$MaxTableRows = 500
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Private/Get-SectionFamily.ps1')
. (Join-Path $PSScriptRoot 'Private/ConvertTo-SharePointPageSegments.ps1')
. (Join-Path $PSScriptRoot '../Private/Get-TableFamily.ps1')
. (Join-Path $PSScriptRoot '../Private/Get-TableTierProfile.ps1')
# Only for snapshots rendered before the section model: their Markdown is
# converted with the renderer's own converter.
. (Join-Path $PSScriptRoot '../Private/ConvertFrom-BlueprintMermaid.ps1')
. (Join-Path $PSScriptRoot '../Private/ConvertTo-BlueprintSection.ps1')

$script:DashboardPage   = 'Dashboard'
$script:FindingsListUrl = 'Lists/SentinelFindings'
$script:FindingsTitle   = 'Sentinel Findings'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Message,
        [ValidateSet('Info', 'Section', 'Warning', 'Error', 'Success')]
        [string] $Level = 'Info'
    )
    switch ($Level) {
        'Section' { Write-Host "`n$Message" -ForegroundColor Cyan }
        'Warning' { Write-Host $Message -ForegroundColor Yellow }
        'Error'   { Write-Host $Message -ForegroundColor Red }
        'Success' { Write-Host $Message -ForegroundColor Green }
        default   { Write-Host $Message }
    }
}

# ---------------------------------------------------------------------------
# Raw-snapshot helpers
# ---------------------------------------------------------------------------

$script:RawRoot = $null

function Read-Raw {
    <#
    .SYNOPSIS
        Read one _raw/<name> JSON file into an object, or $null if absent,
        empty or unparseable.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)

    $path = Join-Path $script:RawRoot $Name
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $text = Get-Content -LiteralPath $path -Raw -Encoding utf8
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        $obj = $text | ConvertFrom-Json -Depth 64
        # Snapshots collected before the Documenter was renamed Blueprint carry
        # DocumenterVersion; read it as BlueprintVersion.
        if ($Name -eq 'run-context.json' -and $obj -and -not $obj.PSObject.Properties['BlueprintVersion'] -and $obj.PSObject.Properties['DocumenterVersion']) {
            $obj | Add-Member -NotePropertyName BlueprintVersion -NotePropertyValue $obj.DocumenterVersion
        }
        return $obj
    }
    catch {
        Write-Log "  ! could not parse _raw/$Name : $($_.Exception.Message)" Warning
        return $null
    }
}

function Read-RawArray {
    <#
    .SYNOPSIS
        Array-shaped reader: an empty array when the file is missing or
        empty, never the one-element-null array that @(Read-Raw x) gives
        (whose Count is 1 and which yields a phantom all-null row). Same
        contract as Read-RawArray in Convert-SentinelInventoryToMarkdown.ps1.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)

    $value = Read-Raw $Name
    if ($null -eq $value) { return , @() }
    return , @($value)
}

function Measure-Count {
    <# Count items in a list or value-wrapped payload, tolerant of $null. #>
    param($Data)
    if ($null -eq $Data) { return 0 }
    if ($Data -is [System.Array]) { return @($Data | Where-Object { $null -ne $_ }).Count }
    if ($Data.PSObject.Properties.Name -contains 'value') { return @($Data.value).Count }
    return @($Data).Count
}

function Get-ContentHash {
    <# SHA-256 of a string, lower-case hex. #>
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return ([System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
}

# MITRE internal-name -> (TA id, display) mapping.
$script:MitreTactics = [ordered]@{
    'Reconnaissance'       = @('TA0043', 'Reconnaissance')
    'ResourceDevelopment'  = @('TA0042', 'Resource Development')
    'InitialAccess'        = @('TA0001', 'Initial Access')
    'Execution'            = @('TA0002', 'Execution')
    'Persistence'          = @('TA0003', 'Persistence')
    'PrivilegeEscalation'  = @('TA0004', 'Privilege Escalation')
    'DefenseEvasion'       = @('TA0005', 'Defense Evasion')
    'CredentialAccess'     = @('TA0006', 'Credential Access')
    'Discovery'            = @('TA0007', 'Discovery')
    'LateralMovement'      = @('TA0008', 'Lateral Movement')
    'Collection'           = @('TA0009', 'Collection')
    'CommandAndControl'    = @('TA0011', 'Command and Control')
    'Exfiltration'         = @('TA0010', 'Exfiltration')
    'Impact'               = @('TA0040', 'Impact')
}

# A tactic counts as Covered at this many enabled rules, Thin below it.
$script:MitreCoveredThreshold = 3

# ---------------------------------------------------------------------------
# Section model -> structured blocks for the dashboard's Sections tab. The
# native pages use ConvertTo-SharePointPageSegments; the dashboard has its own
# block shape because its charts, stat chips and table filters work off it.
# ---------------------------------------------------------------------------

function ConvertTo-SectionRunsHtml {
    <#
    .SYNOPSIS
        Dashboard HTML for text runs: web links open in a new tab, links to
        other sections and findings show as cross-reference text.
    #>
    param([object[]] $Runs)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($r in @($Runs)) {
        if ($null -eq $r) { continue }
        if ($r.break) { [void]$sb.Append('<br>'); continue }
        $h = ConvertTo-HtmlText ([string]$r.text)
        if ($r.code) { $h = "<code>$h</code>" }
        if ($r.strike) { $h = "<s>$h</s>" }
        if ($r.italic) { $h = "<em>$h</em>" }
        if ($r.bold) { $h = "<strong>$h</strong>" }
        if ($r.href) {
            if ([string]$r.target.kind -eq 'external') { $h = "<a href=`"$(ConvertTo-HtmlText ([string]$r.href))`" target=`"_blank`" rel=`"noopener`">$h</a>" }
            else { $h = "<span class=`"xref`">$h</span>" }
        }
        [void]$sb.Append($h)
    }
    return $sb.ToString()
}

function Get-SectionListItems {
    # A list's items, nested lists flattened in reading order.
    param($List)
    foreach ($item in @($List.items)) {
        ConvertTo-SectionRunsHtml @($item.text)
        foreach ($b in @($item.blocks)) { if ($b -and [string]$b.type -eq 'list') { Get-SectionListItems $b } }
    }
}

function ConvertTo-SectionBlocks {
    <#
    .SYNOPSIS
        Turn one section from the section model into the dashboard's render
        blocks: headings, prose, notes (callouts), lists and tables. Charts
        (the dashboard draws its own), code and rules are left out.
    #>
    param($Section)

    $blocks = [System.Collections.Generic.List[object]]::new()
    foreach ($b in @($Section.blocks)) {
        if ($null -eq $b) { continue }
        switch ([string]$b.type) {
            'heading' { $blocks.Add([ordered]@{ t = 'h'; lvl = [int]$b.level; html = (ConvertTo-SectionRunsHtml @($b.text)) }) }
            'paragraph' { $blocks.Add([ordered]@{ t = 'p'; html = (ConvertTo-SectionRunsHtml @($b.text)) }) }
            'list' { $blocks.Add([ordered]@{ t = 'ul'; items = @(Get-SectionListItems $b) }) }
            'table' {
                $blocks.Add([ordered]@{
                        t       = 'table'
                        headers = @(@($b.columns) | ForEach-Object { ConvertTo-SectionRunsHtml @($_.text) })
                        align   = @(@($b.columns) | ForEach-Object { if ($_.align) { [string]$_.align } else { 'left' } })
                        rows    = @(foreach ($row in @($b.rows)) { , @(foreach ($cell in @($row)) { ConvertTo-SectionRunsHtml @($cell) }) })
                    })
            }
            'note' {
                # A callout: an optional short lead line, bullet items, paragraphs.
                $inner = @($b.blocks | Where-Object { $_ })
                $title = ''
                $first = $inner | Select-Object -First 1
                if ($inner.Count -gt 1 -and $first -and [string]$first.type -eq 'paragraph') {
                    $lead = ((@($first.text) | ForEach-Object { if ($_.text) { $_.text } }) -join '').Trim()
                    if ($lead -match '^[A-Za-z][\w &/-]{1,24}$') { $title = ConvertTo-SectionRunsHtml @($first.text); $inner = @($inner | Select-Object -Skip 1) }
                }
                $blocks.Add([ordered]@{
                        t     = 'note'
                        title = $title
                        items = @($inner | Where-Object { [string]$_.type -eq 'list' } | ForEach-Object { Get-SectionListItems $_ })
                        paras = @($inner | Where-Object { [string]$_.type -eq 'paragraph' } | ForEach-Object { ConvertTo-SectionRunsHtml @($_.text) })
                    })
            }
            default { }
        }
    }
    return $blocks.ToArray()
}

function Get-SectionModels {
    <#
    .SYNOPSIS
        The run's sections from the section model (sections/index.json and
        sections/<id>.json), in reading order. A snapshot rendered before
        the section model existed has only NN-name.md files; those are
        converted on the fly with the same converter the renderer uses.
    #>
    param([Parameter(Mandatory)] [string] $Source)
    $dir = Join-Path $Source 'sections'
    $indexPath = Join-Path $dir 'index.json'
    if (Test-Path -LiteralPath $indexPath) {
        $index = Get-Content -LiteralPath $indexPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable -Depth 64
        foreach ($entry in @($index.sections)) {
            $path = Join-Path $dir ([string]$entry.file)
            if (-not (Test-Path -LiteralPath $path)) { $buildWarnings.Add("sections/$($entry.file) is listed in sections/index.json but missing."); continue }
            Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable -Depth 64
        }
        return
    }
    $md = @(Get-ChildItem -LiteralPath $Source -Filter '*.md' | Where-Object { $_.BaseName -match '^\d+-' } | Sort-Object Name)
    if ($md.Count) { $buildWarnings.Add("No sections/ in $Source (rendered before the section model); converted the $($md.Count) Markdown sections instead.") }
    foreach ($f in $md) {
        ConvertTo-BlueprintSection -Markdown (Get-Content -LiteralPath $f.FullName -Raw -Encoding utf8) -Id $f.BaseName
    }
}

function ConvertTo-HtmlText {
    param([string] $Text)
    if (-not $Text) { return '' }
    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

function Write-BundleJson {
    <# Write an object to a bundle JSON file, honouring -WhatIf. #>
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] $Data,
        [Parameter(Mandatory)] [string] $What
    )
    if ($PSCmdlet.ShouldProcess($Path, $What)) {
        ($Data | ConvertTo-Json -Depth 32) | Set-Content -LiteralPath $Path -Encoding utf8
    }
}

# ---------------------------------------------------------------------------
# Resolve inputs
# ---------------------------------------------------------------------------

$Source = (Resolve-Path -LiteralPath $Source).Path
$script:RawRoot = Join-Path $Source '_raw'
if (-not (Test-Path -LiteralPath $script:RawRoot)) {
    throw "No _raw/ folder under '$Source'. Point -Source at a Blueprint workspace folder (the one containing _raw/)."
}

$runCtx = Read-Raw 'run-context.json'
if (-not $WorkspaceName) {
    $WorkspaceName = if ($runCtx -and $runCtx.WorkspaceName) { $runCtx.WorkspaceName } else { Split-Path $Source -Leaf }
}
if (-not $Title)      { $Title = "$WorkspaceName - $ProductName" }
if (-not $OutputRoot) { $OutputRoot = Join-Path $Source 'sharepoint' }

Write-Log "Sentinel Blueprint -> SharePoint site bundle" Section
Write-Log "  Source     : $Source"
Write-Log "  Workspace  : $WorkspaceName"
Write-Log "  Product    : $ProductName"
Write-Log "  Output     : $OutputRoot"

$buildWarnings = [System.Collections.Generic.List[string]]::new()

# ---------------------------------------------------------------------------
# Build the dashboard model
# ---------------------------------------------------------------------------

$wsRaw     = Read-Raw 'workspace.json'
$cost      = Read-Raw 'cost-estimate.json'
$gap       = Read-RawArray 'gap-analysis.json'
$connClass = Read-RawArray 'data-connectors-classic.json'
$alertRaw  = Read-RawArray 'alert-rules.json'
$volumes   = Read-RawArray 'analytics-rule-volumes.json'
$healthSum = Read-RawArray 'sentinel-health-summary.json'
$rbacWs    = Read-RawArray 'rbac-workspace.json'
$dataLake  = Read-RawArray 'sentinel-data-lake.json'

$wsProps = if ($wsRaw) { $wsRaw.properties } else { $null }

# ---- Headline / workspace ----
$generatedUtc = if ($runCtx -and $runCtx.StartedAtUtc) { ([datetime]$runCtx.StartedAtUtc).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC' } else { '' }
$workspace = [ordered]@{
    name            = $WorkspaceName
    id              = if ($wsProps) { $wsProps.customerId } else { '' }
    region          = if ($wsRaw) { $wsRaw.location } else { '' }
    sku             = if ($wsProps -and $wsProps.sku) { $wsProps.sku.name } else { '' }
    retentionDays   = if ($wsProps) { [int]$wsProps.retentionInDays } else { 0 }
    dailyCap        = if ($wsProps -and $wsProps.workspaceCapping -and $wsProps.workspaceCapping.dailyQuotaGb -ge 0) { "$($wsProps.workspaceCapping.dailyQuotaGb) GB" } else { 'Unlimited' }
    pnaIngestion    = if ($wsProps) { $wsProps.publicNetworkAccessForIngestion } else { '' }
    pnaQuery        = if ($wsProps) { $wsProps.publicNetworkAccessForQuery } else { '' }
    subscriptionId  = if ($runCtx) { $runCtx.SubscriptionId } else { '' }
    resourceGroup   = if ($runCtx) { $runCtx.ResourceGroup } else { '' }
    generatedUtc    = $generatedUtc
    blueprintVer   = if ($runCtx) { $runCtx.BlueprintVersion } else { '' }
}

# ---- Counts ----
$rulesEnabled = @($alertRaw | Where-Object { $_.properties -and $_.properties.enabled }).Count
$counts = [ordered]@{
    connectors      = Measure-Count $connClass
    rulesTotal      = Measure-Count $alertRaw
    rulesEnabled    = $rulesEnabled
    automationRules = Measure-Count (Read-Raw 'automation-rules.json')
    watchlists      = Measure-Count (Read-Raw 'watchlists.json')
    workbooks       = Measure-Count (Read-Raw 'workbooks-saved.json')
    dcrs            = Measure-Count (Read-Raw 'dcrs.json')
    tables          = Measure-Count (Read-Raw 'tables-with-data.json')
    rbac            = Measure-Count $rbacWs
    hunting         = Measure-Count (Read-Raw 'hunting-queries.json')
    playbookMi      = Measure-Count (Read-Raw 'rbac-playbook-mi.json')
}

# ---- Cost ----
$costModel = $null
if ($cost) {
    $costModel = [ordered]@{
        monthlyTotal = [math]::Round([double]$cost.MonthlyTotal, 2)
        currency     = $cost.Currency
        asOf         = if ($cost.AsOfUtc) { ([datetime]$cost.AsOfUtc).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC' } else { '' }
        byPlan       = @()
        topTables    = @()
        allTables    = @()
    }
    if ($cost.ByPlan) {
        foreach ($p in $cost.ByPlan.PSObject.Properties) {
            $costModel.byPlan += [ordered]@{ plan = $p.Name; gb30d = [math]::Round([double]$p.Value.Gb30d, 2); cost = [math]::Round([double]$p.Value.MonthlyCost, 2) }
        }
    }
    foreach ($t in @($cost.Top10TablesByCost | Where-Object { $_ })) {
        $costModel.topTables += [ordered]@{ table = $t.Table; plan = $t.Plan; gb30d = [math]::Round([double]$t.Gb30d, 2); cost = [math]::Round([double]$t.MonthlyCost, 2) }
    }
    if ($cost.PSObject.Properties['AllTablesByCost']) {
        foreach ($t in @($cost.AllTablesByCost | Where-Object { $_ -and [double]$_.Gb30d -gt 0 } | Sort-Object { [double]$_.Gb30d } -Descending)) {
            $costModel.allTables += [ordered]@{ table = $t.Table; plan = $t.Plan; gb30d = [math]::Round([double]$t.Gb30d, 2); cost = [math]::Round([double]$t.MonthlyCost, 2) }
        }
    }
}

# ---- Findings ----
$sevRank = @{ 'Critical' = 0; 'Error' = 1; 'Warning' = 2; 'Info' = 3; 'Informational' = 3 }
$bySeverity = @{}
$byCategory = @{}
foreach ($f in $gap) {
    if (-not $f) { continue }
    $s = if ($f.Severity) { [string]$f.Severity } else { 'Info' }
    $c = if ($f.Category) { [string]$f.Category } else { 'Other' }
    if (-not $bySeverity.ContainsKey($s)) { $bySeverity[$s] = 0 }; $bySeverity[$s]++
    if (-not $byCategory.ContainsKey($c)) { $byCategory[$c] = 0 }; $byCategory[$c]++
}
$findingList = @()
foreach ($f in ($gap | Where-Object { $_ } | Sort-Object { if ($sevRank.ContainsKey([string]$_.Severity)) { $sevRank[[string]$_.Severity] } else { 5 } }, Id)) {
    $findingList += [ordered]@{
        id          = $f.Id
        legacyId    = $(if ($f.PSObject.Properties['LegacyId'] -and $f.LegacyId) { [string]$f.LegacyId } else { $null })
        area        = $(if ($f.PSObject.Properties['Area'] -and $f.Area) { [string]$f.Area } else { $null })
        title       = $f.Title
        severity    = [string]$f.Severity
        category    = [string]$f.Category
        evidence    = $f.Evidence
        remediation = $f.Remediation
        learn       = $f.Learn
    }
}
$findings = [ordered]@{
    total      = @($gap | Where-Object { $_ }).Count
    bySeverity = $bySeverity
    byCategory = $byCategory
    items      = $findingList
}

# ---- MITRE coverage ----
$tacticCounts = @{}
foreach ($r in $alertRaw) {
    if (-not ($r.properties -and $r.properties.enabled)) { continue }
    foreach ($t in @($r.properties.tactics)) {
        if (-not $t) { continue }
        if (-not $tacticCounts.ContainsKey($t)) { $tacticCounts[$t] = 0 }
        $tacticCounts[$t]++
    }
}
$mitre = @()
foreach ($k in $script:MitreTactics.Keys) {
    $n = if ($tacticCounts.ContainsKey($k)) { $tacticCounts[$k] } else { 0 }
    $status = if ($n -eq 0) { 'None' } elseif ($n -lt $script:MitreCoveredThreshold) { 'Thin' } else { 'Covered' }
    $mitre += [ordered]@{ id = $script:MitreTactics[$k][0]; tactic = $script:MitreTactics[$k][1]; rules = $n; status = $status }
}
$mitreCovered = @($mitre | Where-Object { $_.status -eq 'Covered' }).Count

# ---- Data lake enrolment (shared by the billing flow and the lake panel) ----
$wsProps = if ($wsRaw -and $wsRaw.PSObject.Properties['properties']) { $wsRaw.properties } else { $null }
$wsTablesRaw = Read-RawArray 'workspace-tables.json'
$wsTableByName = @{}
foreach ($t in $wsTablesRaw) { if ($t -and $t.PSObject.Properties['name'] -and $t.name) { $wsTableByName[[string]$t.name] = $t } }
$unifiedBilling = [bool]($wsProps -and $wsProps.PSObject.Properties['features'] -and $wsProps.features -and $wsProps.features.PSObject.Properties['unifiedSentinelBillingOnly'] -and $wsProps.features.unifiedSentinelBillingOnly)
$lakePlanTables = @($wsTablesRaw | Where-Object { $_ -and $_.PSObject.Properties['properties'] -and $_.properties -and $_.properties.PSObject.Properties['plan'] -and $_.properties.plan -eq 'DataLake' }).Count
$lakeEnrolled = ($dataLake.Count -gt 0) -or $unifiedBilling -or ($lakePlanTables -gt 0)
# The flow's plan column names the lake tier a table lands in, so an
# enrolled workspace shows its lake instead of a single "Analytics plan"
# box. Basic and Auxiliary tables keep their plan name: they are neither
# analytics-tier nor lake-mirrored.
$script:FlowTierLabel = @{ AnalyticsOnly = 'Analytics plan'; MirroredOnly = 'Analytics + Lake mirror'; MirroredExtended = 'Analytics + Lake extended'; LakeOnly = 'Data lake only' }
function Get-FlowPlanLabel {
    param([string]$Table, [string]$Plan)
    if ($Plan -in @('Basic', 'Auxiliary')) { return "$Plan plan" }
    if ($Plan -eq 'DataLake') { return $script:FlowTierLabel.LakeOnly }
    $res = if ($Table -and $wsTableByName.ContainsKey($Table)) { $wsTableByName[$Table] } else { $null }
    if ($null -eq $res) { return $(if ($lakeEnrolled) { $script:FlowTierLabel.MirroredOnly } else { $script:FlowTierLabel.AnalyticsOnly }) }
    return $script:FlowTierLabel[(Get-TableTier -Table $res -LakeEnrolled $lakeEnrolled)]
}

# ---- Ingest / billing flow (grounded in cost-estimate) ----
$flowNodes = @()
$flowLinks = @()
if ($cost -and $cost.PSObject.Properties['AllTablesByCost']) {
    $ingest = @($cost.AllTablesByCost | Where-Object { $_ -and [double]$_.Gb30d -gt 0 } | Sort-Object { [double]$_.Gb30d } -Descending)
    $topN = 9
    $top = @($ingest | Select-Object -First $topN)
    $rest = @($ingest | Select-Object -Skip $topN)

    # Each table row carries one or more parts: (plan label, gb, billed gb).
    # A named table has one part; the long-tail node has one part per plan
    # label so its ribbons fan out to every tier the tail lands in.
    $tableRows = @()
    foreach ($t in $top) {
        $gb = [math]::Round([double]$t.Gb30d, 3)
        $billedGb = if ([double]$t.MonthlyCost -gt 0) { $gb } else { 0.0 }
        $tableRows += [ordered]@{ table = $t.Table; family = (Get-TableFamily $t.Table); gb = $gb; parts = @([ordered]@{ plan = (Get-FlowPlanLabel -Table $t.Table -Plan ([string]$t.Plan)); gb = $gb; billedGb = $billedGb }) }
    }
    if ($rest.Count -gt 0) {
        $restParts = [ordered]@{}
        foreach ($t in $rest) {
            $label = Get-FlowPlanLabel -Table $t.Table -Plan ([string]$t.Plan)
            if (-not $restParts.Contains($label)) { $restParts[$label] = [ordered]@{ plan = $label; gb = 0.0; billedGb = 0.0 } }
            $restParts[$label].gb += [double]$t.Gb30d
            if ([double]$t.MonthlyCost -gt 0) { $restParts[$label].billedGb += [double]$t.Gb30d }
        }
        $restGb = 0.0; foreach ($pt in $restParts.Values) { $pt.gb = [math]::Round($pt.gb, 3); $pt.billedGb = [math]::Round($pt.billedGb, 3); $restGb += $pt.gb }
        $tableRows += [ordered]@{ table = "Other (+$($rest.Count))"; family = 'Other'; gb = [math]::Round($restGb, 3); parts = @($restParts.Values) }
    }

    # Nodes: families (col0), tables (col1), plans and lake tiers (col2), billed buckets (col3)
    $famAgg = @{}; foreach ($row in $tableRows) { if (-not $famAgg.ContainsKey($row.family)) { $famAgg[$row.family] = 0.0 }; $famAgg[$row.family] += $row.gb }
    $planAgg = @{}; $planBucket = @{}
    $bucketAgg = @{ 'Billed' = 0.0; 'Free benefit' = 0.0 }
    foreach ($row in $tableRows) {
        foreach ($pt in $row.parts) {
            if (-not $planAgg.ContainsKey($pt.plan)) { $planAgg[$pt.plan] = 0.0 }
            $planAgg[$pt.plan] += $pt.gb
            $freeGb = [math]::Round($pt.gb - $pt.billedGb, 3)
            $bucketAgg['Billed'] += $pt.billedGb; $bucketAgg['Free benefit'] += $freeGb
            foreach ($pair in @(@('Billed', $pt.billedGb), @('Free benefit', $freeGb))) {
                if ($pair[1] -le 0) { continue }
                $key = "$($pt.plan)|$($pair[0])"
                if (-not $planBucket.ContainsKey($key)) { $planBucket[$key] = 0.0 }
                $planBucket[$key] += $pair[1]
            }
        }
    }

    foreach ($fam in ($famAgg.Keys | Sort-Object { $famAgg[$_] } -Descending)) {
        $flowNodes += [ordered]@{ id = "f:$fam"; col = 0; label = $fam; value = [math]::Round($famAgg[$fam], 3) }
    }
    foreach ($row in $tableRows) {
        $flowNodes += [ordered]@{ id = "t:$($row.table)"; col = 1; label = $row.table; value = $row.gb }
    }
    foreach ($pl in ($planAgg.Keys | Sort-Object { $planAgg[$_] } -Descending)) {
        $flowNodes += [ordered]@{ id = "p:$pl"; col = 2; label = $pl; value = [math]::Round($planAgg[$pl], 3); lake = ($pl -like '*Lake*') }
    }
    foreach ($bk in 'Billed', 'Free benefit') {
        if ($bucketAgg[$bk] -gt 0) { $flowNodes += [ordered]@{ id = "b:$bk"; col = 3; label = $bk; value = [math]::Round($bucketAgg[$bk], 3) } }
    }

    # Links
    foreach ($row in $tableRows) {
        $flowLinks += [ordered]@{ source = "f:$($row.family)"; target = "t:$($row.table)"; value = $row.gb }
        foreach ($pt in $row.parts) {
            $flowLinks += [ordered]@{ source = "t:$($row.table)"; target = "p:$($pt.plan)"; value = $pt.gb }
        }
    }
    foreach ($key in $planBucket.Keys) {
        $parts = $key -split '\|', 2
        $flowLinks += [ordered]@{ source = "p:$($parts[0])"; target = "b:$($parts[1])"; value = [math]::Round($planBucket[$key], 3) }
    }
}
$flow = [ordered]@{ nodes = $flowNodes; links = $flowLinks }
# Every ingesting table with its family, plan label and billed share, so the
# dashboard can rebuild the flow for one family or for every table on click
# instead of folding the long tail into an "Other" node for good.
$flowTables = @()
if ($cost -and $cost.PSObject.Properties['AllTablesByCost']) {
    foreach ($t in @($cost.AllTablesByCost | Where-Object { $_ -and [double]$_.Gb30d -gt 0 } | Sort-Object { [double]$_.Gb30d } -Descending)) {
        $gb = [math]::Round([double]$t.Gb30d, 3)
        $flowTables += [ordered]@{
            table    = [string]$t.Table
            family   = (Get-TableFamily $t.Table)
            plan     = (Get-FlowPlanLabel -Table ([string]$t.Table) -Plan ([string]$t.Plan))
            gb       = $gb
            billedGb = $(if ([double]$t.MonthlyCost -gt 0) { $gb } else { 0.0 })
        }
    }
}

# ---- Top alerting rules (by 30d volume) ----
$topRules = @()
foreach ($v in ($volumes | Where-Object { $_ })) {
    $topRules += [ordered]@{ name = $v.AlertName; product = $v.ProductName; severity = $v.AlertSeverity; alerts = [int]$v.Alerts }
}

# ---- Operational health ----
$healthTotal = 0.0; $healthOk = 0.0
foreach ($h in $healthSum) { if (-not $h) { continue }; $n = [double]$h.LogCount; $healthTotal += $n; if ($h.Status -eq 'Success') { $healthOk += $n } }
$healthPct = if ($healthTotal -gt 0) { [math]::Round(100.0 * $healthOk / $healthTotal, 1) } else { 0 }

# ---- Health-check ports: estate, effectiveness, run health, maturity ----
# KQL result cells arrive as strings and fixtures carry typed values, so
# every number is parsed with the invariant culture rather than cast.
function ConvertTo-BuildNumber {
    param($Value)
    if ($null -eq $Value) { return 0.0 }
    $d = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return 0.0
}
# A KQL dynamic bag (ByClassification) as an ordered name -> count map.
function Get-BuildBag {
    param($Value)
    $bag = [ordered]@{}
    if ($null -eq $Value) { return $bag }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $bag }
        try { $Value = $Value | ConvertFrom-Json } catch { return $bag }
        if ($null -eq $Value) { return $bag }
    }
    foreach ($prop in $Value.PSObject.Properties) { $bag[$prop.Name] = [long](ConvertTo-BuildNumber $prop.Value) }
    return $bag
}
function New-EstateRing {
    param([string]$Label, [int]$Value, [int]$Max)
    [ordered]@{ label = $Label; value = $Value; max = $Max; pct = $(if ($Max -gt 0) { [int][math]::Round(100.0 * $Value / $Max, 0) } else { $null }) }
}

$ruleRefs      = Read-RawArray 'rule-table-references.json'
$templateRefs  = Read-RawArray 'template-table-references.json'
$customDetRefs = Read-RawArray 'custom-detection-table-references.json'
$customDetCaptured = Test-Path -LiteralPath (Join-Path $script:RawRoot 'defender-custom-detections.json')
$customDetRaw = Read-RawArray 'defender-custom-detections.json'
$effectRows    = Read-RawArray 'rule-effectiveness.json'
$firedRows     = Read-RawArray 'rules-fired.json'
$runRows       = Read-RawArray 'playbook-runs.json'
$huntRows      = Read-RawArray 'hunts.json'
$bookmarkRows  = Read-RawArray 'bookmarks.json'
$usageRows     = Read-RawArray 'workspace-usage-daily.json'
$tablesData    = Read-RawArray 'tables-with-data.json'
# Read-RawArray emits the array as one object, so take the first row by index.
$incSummaryRows = @(Read-RawArray 'incidents-summary.json')
$incSummaryRow = if ($incSummaryRows.Count -gt 0) { $incSummaryRows[0] } else { $null }
$tiCountRows   = Read-RawArray 'threat-intel-counts.json'
$tiObjectRows  = Read-RawArray 'threat-intel-objects.json'
$maturityRaw   = Read-Raw 'maturity.json'
# A failed maturity capture writes '{}', which is truthy, so test for the
# members the dashboard needs.
$maturityOk    = ($null -ne $maturityRaw -and $null -ne $maturityRaw.PSObject.Properties['areas'] -and $null -ne $maturityRaw.PSObject.Properties['overall'])

# Estate: source families -> ingestion -> detection -> alerts -> incidents,
# the same numbers the Markdown renderer draws on 00 and 01.
$referencedTables = @{}
foreach ($r in $ruleRefs) {
    if (-not $r -or $r.Enabled -ne $true) { continue }
    foreach ($t in @($r.Tables)) { if ($t) { $referencedTables[[string]$t] = $true } }
}
# Enabled Defender XDR custom detections count as coverage too.
$customDetPerTable = @{}
foreach ($r in $customDetRefs) {
    if (-not $r -or $r.Enabled -ne $true) { continue }
    foreach ($t in @($r.Tables)) { if ($t) { $k = [string]$t; $referencedTables[$k] = $true; if (-not $customDetPerTable.ContainsKey($k)) { $customDetPerTable[$k] = 0 }; $customDetPerTable[$k]++ } }
}
$famAgg2 = [ordered]@{}
$tablesActive = 0; $tablesCovered = 0; $estateTotalGb = 0.0; $estateCoveredGb = 0.0
# Enabled rules per table, so the estate flow can list what reads each one.
$rulesPerTableBuild = @{}
foreach ($r in $ruleRefs) {
    if (-not $r -or $r.Enabled -ne $true) { continue }
    foreach ($t in @($r.Tables)) { if ($t) { $k = [string]$t; if (-not $rulesPerTableBuild.ContainsKey($k)) { $rulesPerTableBuild[$k] = 0 }; $rulesPerTableBuild[$k]++ } }
}
$estateTableRows = @()
foreach ($t in $tablesData) {
    if (-not $t -or -not $t.DataType) { continue }
    $gb = ConvertTo-BuildNumber $t.BillableLast30d
    if ($gb -le 0) { continue }
    $tablesActive++; $estateTotalGb += $gb
    $fam = Get-TableFamily $t.DataType
    if (-not $famAgg2.Contains($fam)) { $famAgg2[$fam] = [ordered]@{ category = $fam; tables = 0; gb = 0.0; coveredGb = 0.0; covered = 0 } }
    $famAgg2[$fam].tables++; $famAgg2[$fam].gb += $gb
    $isCovered = $referencedTables.ContainsKey([string]$t.DataType)
    if ($isCovered) { $tablesCovered++; $estateCoveredGb += $gb; $famAgg2[$fam].covered++; $famAgg2[$fam].coveredGb += $gb }
    $estateTableRows += [ordered]@{
        table   = [string]$t.DataType
        family  = $fam
        gb      = [math]::Round($gb, 2)
        rules   = $(if ($rulesPerTableBuild.ContainsKey([string]$t.DataType)) { $rulesPerTableBuild[[string]$t.DataType] } else { 0 })
        customDetections = $(if ($customDetPerTable.ContainsKey([string]$t.DataType)) { $customDetPerTable[[string]$t.DataType] } else { 0 })
        covered = $isCovered
    }
}
$sortedFams = @($famAgg2.Values | Sort-Object { $_.gb } -Descending)
$estateSources = @()
foreach ($f in $sortedFams) {
    $estateSources += [ordered]@{ category = $f.category; tables = $f.tables; gb = [math]::Round($f.gb, 2); coveredGb = [math]::Round($f.coveredGb, 2); covered = $f.covered }
}
$alerts30d = [long]0
foreach ($f in $firedRows) { if ($f) { $alerts30d += [long](ConvertTo-BuildNumber $f.Alerts) } }
# First-party detections by source family: alerts raised inside Defender XDR,
# Entra ID Protection, Defender for Identity and Defender for Cloud do not
# read workspace tables, so the rings cannot count them; the flow shows them
# beside each family instead. Sentinel's own rules are excluded here.
$productAgg = [ordered]@{}
foreach ($v in @($volumes | Where-Object { $_ })) {
    $prod = [string]$(if ($v.PSObject.Properties['ProductName']) { $v.ProductName } else { '' })
    if (-not $prod -or $prod -match 'Sentinel') { continue }
    $famName = Get-ProductFamily -Product $prod
    $key = "$famName|$prod"
    if (-not $productAgg.Contains($key)) { $productAgg[$key] = [ordered]@{ family = $famName; product = $prod; alerts = [long]0; detections = 0 } }
    $productAgg[$key].alerts += [long](ConvertTo-BuildNumber $v.Alerts); $productAgg[$key].detections++
}
$productAlerts = @($productAgg.Values | Sort-Object { -$_.alerts })
$incidents30d = if ($incSummaryRow -and $incSummaryRow.PSObject.Properties['Count'])  { [int](ConvertTo-BuildNumber $incSummaryRow.Count) }  else { 0 }
$closed30d    = if ($incSummaryRow -and $incSummaryRow.PSObject.Properties['Closed']) { [int](ConvertTo-BuildNumber $incSummaryRow.Closed) } else { 0 }
$rulesQueryEnabled = @($alertRaw | Where-Object { $_.properties -and $_.properties.enabled -and $_.kind -in @('Scheduled', 'NRT') }).Count
$rulesFiredCount = @($firedRows | Where-Object { $_ }).Count
$estate = [ordered]@{
    window          = '30d'
    sources         = $estateSources
    tables          = @($estateTableRows | Sort-Object { $_.gb } -Descending)
    productAlerts   = $productAlerts
    customDetections = [ordered]@{ captured = $customDetCaptured; total = @($customDetRaw | Where-Object { $_ }).Count; enabled = @($customDetRefs | Where-Object { $_ -and $_.Enabled -eq $true }).Count }
    totalGb         = [math]::Round($estateTotalGb, 2)
    coveredGb       = [math]::Round($estateCoveredGb, 2)
    uncoveredGb     = [math]::Round($estateTotalGb - $estateCoveredGb, 2)
    rings           = [ordered]@{
        ingestion = New-EstateRing 'Tables still receiving data (30d of 90d)' $tablesActive (@($tablesData | Where-Object { $_ }).Count)
        detection = New-EstateRing 'Active tables read by an enabled Sentinel rule or custom detection' $tablesCovered $tablesActive
        alerts    = New-EstateRing 'Enabled Scheduled/NRT Sentinel rules that fired' $rulesFiredCount $rulesQueryEnabled
        incidents = New-EstateRing 'Incidents closed, of those created' $closed30d $incidents30d
    }
    rulesEnabled    = $rulesEnabled
    rulesFired      = $rulesFiredCount
    alerts          = $alerts30d
    incidents       = $incidents30d
    incidentsClosed = $closed30d
    incidentsOpen   = [math]::Max(0, $incidents30d - $closed30d)
    dcrs            = $counts.dcrs
    automationRules = $counts.automationRules
    playbooks       = Measure-Count (Read-Raw 'playbooks.json')
}

$effectiveness = @()
# Sentinel rules first, then other products' alerts by name.
$effectSorted = @($effectRows | Where-Object { $_ } | Sort-Object { -(ConvertTo-BuildNumber $_.Incidents) } | Sort-Object { if ($_.PSObject.Properties['AlertRuleId'] -and $_.AlertRuleId) { 0 } else { 1 } } -Stable)
foreach ($e in $effectSorted) {
    $src = if ($e.PSObject.Properties['Source'] -and $e.Source) { [string]$e.Source } elseif ($e.PSObject.Properties['AlertRuleId'] -and $e.AlertRuleId) { 'Analytics rule' } else { 'Other' }
    $effectiveness += [ordered]@{
        rule = $e.RuleName; source = $src; incidents = [int](ConvertTo-BuildNumber $e.Incidents); closed = [int](ConvertTo-BuildNumber $e.Closed)
        tp = [int](ConvertTo-BuildNumber $e.TruePositive); fp = [int](ConvertTo-BuildNumber $e.FalsePositive); bp = [int](ConvertTo-BuildNumber $e.BenignPositive)
        undetermined = [int](ConvertTo-BuildNumber $e.Undetermined); fpRate = [math]::Round((ConvertTo-BuildNumber $e.FPRate), 1)
    }
}

$usageDaily = @()
foreach ($u in ($usageRows | Where-Object { $_ } | Sort-Object { [datetime]$_.Day } | Select-Object -Last 90)) {
    $usageDaily += [ordered]@{ day = ([datetime]$u.Day).ToUniversalTime().ToString('yyyy-MM-dd'); billable = [math]::Round((ConvertTo-BuildNumber $u.BillableGB), 2); free = [math]::Round((ConvertTo-BuildNumber $u.FreeGB), 2) }
}

# Tables with data that no enabled rule reads, with the undeployed templates
# that would cover them (section 28's content; the dashboard shows twelve
# and a Show all control for the rest).
$detectionOpportunities = @()
$uncoveredTotal = 0
if ($ruleRefs.Count -gt 0) {
    $undeployed = @($templateRefs | Where-Object { $_ -and $_.Deprecated -ne $true -and $_.AlreadyDeployed -ne $true })
    $sevRank2 = @{ High = 0; Medium = 1; Low = 2; Informational = 3 }
    $operationalOnly = @('SecurityIncident', 'SecurityAlert', 'Usage', 'Operation', 'LAQueryLogs', 'SentinelHealth', 'SentinelAudit', 'AzureMetrics')
    $uncovered = @($tablesData | Where-Object {
        $_ -and $_.DataType -and (ConvertTo-BuildNumber $_.BillableLast30d) -gt 0 -and
        -not $referencedTables.ContainsKey([string]$_.DataType) -and ([string]$_.DataType) -notin $operationalOnly
    } | Sort-Object { ConvertTo-BuildNumber $_.BillableLast30d } -Descending)
    $uncoveredTotal = $uncovered.Count
    foreach ($t in $uncovered) {
        $name = [string]$t.DataType
        $cands = @($undeployed | Where-Object { @($_.Tables) -contains $name } | Sort-Object { $sv = [string]$_.Severity; if ($sevRank2.ContainsKey($sv)) { $sevRank2[$sv] } else { 9 } }, DisplayName)
        $detectionOpportunities += [ordered]@{
            table     = $name
            family    = (Get-TableFamily $name)
            gb30d     = [math]::Round((ConvertTo-BuildNumber $t.BillableLast30d), 2)
            templates = @($cands | ForEach-Object { [ordered]@{ name = $_.DisplayName; severity = $_.Severity } })
        }
    }
}

# When the bookmarks list was too large to fetch, the collector keeps the
# count the service reported.
$bookmarkCount = @($bookmarkRows | Where-Object { $_ }).Count
if (-not (Test-Path -LiteralPath (Join-Path $script:RawRoot 'bookmarks.json'))) {
    $bookmarkCountDoc = Read-Raw 'bookmarks-count.json'
    # Neither file: the count is unknown, not zero.
    $bookmarkCount = if ($bookmarkCountDoc -and $bookmarkCountDoc.PSObject.Properties['Count']) { [int](ConvertTo-BuildNumber $bookmarkCountDoc.Count) } else { $null }
}
$huntsSummary = [ordered]@{
    captured       = (Test-Path -LiteralPath (Join-Path $script:RawRoot 'hunts.json'))
    hunts          = @($huntRows | Where-Object { $_ }).Count
    bookmarks      = $bookmarkCount
    huntingQueries = $counts.hunting
}

$pbRuns = 0; $pbFailed = 0; $pbFailing = @(); $pbUnavailable = 0
foreach ($r in ($runRows | Where-Object { $_ })) {
    if ($r.PSObject.Properties['LastRunStatus'] -and [string]$r.LastRunStatus -eq 'Unavailable') { $pbUnavailable++; continue }
    $runs = [int](ConvertTo-BuildNumber $r.Runs7d); $failed = [int](ConvertTo-BuildNumber $r.Failed7d)
    $pbRuns += $runs; $pbFailed += $failed
    if ($failed -gt 0) {
        $last = if ($r.LastFailureUtc) { ([datetime]$r.LastFailureUtc).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') } else { '' }
        $pbFailing += [ordered]@{ playbook = $r.Playbook; runs = $runs; failed = $failed; lastFailure = $last }
    }
}
$playbookHealth = [ordered]@{ runs7d = $pbRuns; failed7d = $pbFailed; playbooks = @($runRows | Where-Object { $_ }).Count; unavailable = $pbUnavailable; failing = @($pbFailing | Sort-Object { $_.failed } -Descending) }

$tiBySource = @()
foreach ($row in ($tiCountRows | Where-Object { $_ } | Sort-Object { ConvertTo-BuildNumber $_.Count } -Descending)) {
    $tiBySource += [ordered]@{ source = [string]$row.SourceSystem; count = [long](ConvertTo-BuildNumber $row.Count) }
}
$tiObjects = @()
foreach ($row in ($tiObjectRows | Where-Object { $_ } | Sort-Object { ConvertTo-BuildNumber $_.Count } -Descending)) {
    $tiObjects += [ordered]@{ type = [string]$row.StixType; count = [long](ConvertTo-BuildNumber $row.Count) }
}

$incidentsByClassification = @()
if ($incSummaryRow -and $incSummaryRow.PSObject.Properties['ByClassification']) {
    $bag = Get-BuildBag $incSummaryRow.ByClassification
    foreach ($k in ($bag.Keys | Sort-Object { $bag[$_] } -Descending)) { if ($bag[$k] -gt 0) { $incidentsByClassification += [ordered]@{ label = [string]$k; value = [long]$bag[$k] } } }
}

# Sentinel data lake: enrolment signals, tier distribution and the tables
# that keep data in the lake beyond analytics retention, counted over the
# operational tables (data in 90 days, plus custom logs) exactly as section
# 88 counts them, through the shared helper.
$populatedNames = @{}
foreach ($t in $tablesData) { if ($t -and $t.PSObject.Properties['DataType'] -and $t.DataType -and (ConvertTo-BuildNumber $t.BillableLast90d) -gt 0) { $populatedNames[[string]$t.DataType] = $true } }
$operationalTables = @($wsTablesRaw | Where-Object {
    $_ -and $_.PSObject.Properties['name'] -and $_.name -and $_.PSObject.Properties['properties'] -and $_.properties -and (
        ($_.properties.PSObject.Properties['schema'] -and $_.properties.schema -and $_.properties.schema.PSObject.Properties['tableType'] -and $_.properties.schema.tableType -eq 'CustomLog') -or
        $populatedNames.ContainsKey([string]$_.name))
})
$tierProfile = Get-TableTierProfile -Tables $operationalTables -LakeEnrolled $lakeEnrolled
$lakeResource = @($dataLake | Where-Object { $_ }) | Select-Object -First 1
$lakeCostRow = if ($costModel) { $costModel.byPlan | Where-Object { $_.plan -eq 'DataLake' } | Select-Object -First 1 } else { $null }
$analyticsCostRow = if ($costModel) { $costModel.byPlan | Where-Object { $_.plan -eq 'Analytics' } | Select-Object -First 1 } else { $null }
$dataLakeModel = [ordered]@{
    enrolled          = $lakeEnrolled
    signals           = [ordered]@{ resource = ($dataLake.Count -gt 0); unifiedBilling = $unifiedBilling; lakeOnlyTables = $lakePlanTables }
    provisioningState = if ($lakeResource -and $lakeResource.properties -and $lakeResource.properties.PSObject.Properties['provisioningState']) { [string]$lakeResource.properties.provisioningState } else { '' }
    region            = if ($lakeResource -and $lakeResource.PSObject.Properties['location']) { [string]$lakeResource.location } else { '' }
    operationalTables = $operationalTables.Count
    tiers             = $tierProfile.Tiers
    extendedCount     = @($tierProfile.RetentionRows).Count
    extendedTables    = @($tierProfile.RetentionRows | Sort-Object { $_.LakeOnlyDays } -Descending | ForEach-Object {
        [ordered]@{ table = $_.Table; plan = $_.Plan; analyticsDays = $_.AnalyticsDays; lakeOnlyDays = $_.LakeOnlyDays; totalDays = $_.TotalDays }
    })
    cost              = [ordered]@{
        currency     = if ($costModel) { $costModel.currency } else { '' }
        analyticsGb  = if ($analyticsCostRow) { $analyticsCostRow.gb30d } else { 0 }
        analyticsCost = if ($analyticsCostRow) { $analyticsCostRow.cost } else { 0 }
        lakeGb       = if ($lakeCostRow) { $lakeCostRow.gb30d } else { 0 }
        lakeCost     = if ($lakeCostRow) { $lakeCostRow.cost } else { 0 }
    }
}

# Maturity: the page carries evidence and guidance; the dashboard keeps the
# scores, the criteria statuses, the roadmap and the rollup.
$maturityModel = $null
if ($maturityOk) {
    $maturityModel = [ordered]@{
        methodology      = [ordered]@{ name = [string]$maturityRaw.methodology.name; version = [string]$maturityRaw.methodology.version }
        targetLevel      = [int]$maturityRaw.targetLevel
        targetLevelName  = [string]$maturityRaw.targetLevelName
        targetMet        = [bool]$maturityRaw.targetMet
        overall          = [ordered]@{ score = $maturityRaw.overall.score; level = $maturityRaw.overall.level; levelName = [string]$maturityRaw.overall.levelName }
        levels           = @(@($maturityRaw.levels) | ForEach-Object { [ordered]@{ level = [int]$_.level; name = [string]$_.name } })
        areasBelowTarget = @(@($maturityRaw.areasBelowTarget) | ForEach-Object { [string]$_.id })
        areas            = @(foreach ($a in @($maturityRaw.areas)) {
            [ordered]@{ id = $a.id; name = $a.name; score = $a.score; level = $a.level; levelName = $a.levelName; met = $a.met; gap = $a.gap; unknown = $a.unknown; evaluated = $a.evaluated; confidence = $a.confidence }
        })
        criteria         = @(foreach ($a in @($maturityRaw.areas)) { foreach ($c in @($a.criteria)) {
            [ordered]@{ id = $c.id; area = $a.id; kind = $c.kind; name = $c.name; status = $c.status; effort = $c.effort; impact = $c.impact; evidence = $c.evidence; guidance = $(if ($c.PSObject.Properties['guidance']) { [string]$c.guidance } else { '' }) }
        } })
        roadmap          = @(@($maturityRaw.roadmap) | ForEach-Object {
            [ordered]@{ priority = $_.priority; criterionId = $_.criterionId; area = $_.area; name = $_.name; effort = $_.effort; overallLift = $_.overallLift; projectedScore = $_.projectedScore; guidance = $_.guidance }
        })
        quickWins        = @(@($maturityRaw.quickWins) | ForEach-Object { [ordered]@{ criterionId = $_.criterionId; area = $_.area; name = $_.name; guidance = $_.guidance; overallLift = $_.overallLift } })
        csf              = [ordered]@{
            source    = [string]$maturityRaw.csf.source
            functions = @(@($maturityRaw.csf.functions) | ForEach-Object { [ordered]@{ id = $_.id; name = $_.name; criteria = $_.criteria; met = $_.met; gap = $_.gap; unknown = $_.unknown } })
        }
        totals           = [ordered]@{ criteria = $maturityRaw.totals.criteria; met = $maturityRaw.totals.met; gap = $maturityRaw.totals.gap; unknown = $maturityRaw.totals.unknown }
    }
}

# ---------------------------------------------------------------------------
# Sections: dashboard blocks and native page segments
# ---------------------------------------------------------------------------

$headlineByNum = @{
    10 = "$($counts.connectors) connectors"
    20 = "$($counts.rulesEnabled) enabled / $($counts.rulesTotal)"
    25 = "$mitreCovered / $($mitre.Count) tactics"
    30 = "$($counts.hunting) hunting queries"
    40 = "$($counts.workbooks) workbooks"
    50 = "$($counts.watchlists) watchlists"
    60 = "$($counts.automationRules) automation rules"
    83 = "$($counts.dcrs) DCRs"
    85 = "$($counts.rbac) role assignments"
    90 = "$($findings.total) findings"
}
if ($costModel) { $headlineByNum[84] = "$($costModel.currency) $($costModel.monthlyTotal)/mo" }
if ($incSummaryRow) { $headlineByNum[15] = "$incidents30d incidents (30d)" }
if ($ruleRefs.Count -gt 0) { $headlineByNum[28] = "$uncoveredTotal tables without detection" }
if ($maturityModel) {
    $headlineByNum[91] = if ($null -ne $maturityModel.overall.score) { "Score $($maturityModel.overall.score) / 5" } else { 'Not assessed' }
}

$sections = @()
$siteSections = @()
$pageDocs = @()
$chartCount = 0

foreach ($sec in @(Get-SectionModels -Source $Source)) {
    if ($null -eq $sec.order) { continue }
    $id = [string]$sec.id
    $num = [int]$sec.order
    $family = Get-SectionFamily -Number $num
    $pageName = Get-SacPageName -FileName $id

    $converted = ConvertTo-SharePointPageSegments -Section $sec -FindingsListUrl $script:FindingsListUrl -MaxTableRows $MaxTableRows
    foreach ($w in $converted.Warnings) { $buildWarnings.Add($w) }
    $segments = @($converted.Segments)
    $chartCount += @($segments | Where-Object { $_.type -eq 'chart' }).Count

    $secTitle = if ($converted.Title) { $converted.Title } else { ($id -replace '^\d+-', '' -replace '-', ' ') }
    $hash = Get-ContentHash -Text (([ordered]@{ title = $secTitle; segments = $segments }) | ConvertTo-Json -Depth 32 -Compress)

    $blocks = ConvertTo-SectionBlocks -Section $sec
    $tableRows = 0
    foreach ($b in $blocks) { if ($b.t -eq 'table') { $tableRows += @($b.rows).Count } }

    $sections += [ordered]@{
        num       = $num
        file      = "sections/$id.json"
        page      = $pageName
        title     = $secTitle
        family    = $family
        headline  = if ($headlineByNum.ContainsKey($num)) { $headlineByNum[$num] } else { '' }
        tableRows = $tableRows
        blocks    = $blocks
    }
    $siteSections += [ordered]@{ num = $num; file = "sections/$id.json"; page = $pageName; title = $secTitle; family = $family; hash = $hash }
    $pageDocs += [ordered]@{ name = $pageName; file = "sections/$id.json"; num = $num; title = $secTitle; family = $family; hash = $hash; segments = $segments }
}

if ($sections.Count -eq 0) {
    $buildWarnings.Add("No sections under $Source. Run Convert-SentinelInventoryToMarkdown.ps1 first; the site will have a dashboard and findings but no section pages.")
}

# ---- What's new (Microsoft release-communications RSS, security-filtered) ----
$whatsNew = @()
if (-not $SkipWhatsNew) {
    try {
        Write-Log "  Fetching What's new feed..." Info
        $feed = Invoke-RestMethod -Uri $WhatsNewFeedUrl -TimeoutSec 20 -ErrorAction Stop
        $rx = 'Sentinel|Defender|SIEM|SOC\b|Security Copilot|Microsoft Security|Log Analytics|Azure Monitor|Microsoft Purview|threat intel'
        $items = @($feed | Where-Object { $_.title -match $rx })
        if ($items.Count -lt $WhatsNewCount) { $items = @($feed) }   # fall back to general Azure news
        foreach ($it in ($items | Select-Object -First $WhatsNewCount)) {
            $tag = 'Update'
            if ($it.title -match '^\s*\[?(Launched|Generally Available|GA)\]?' -or $it.title -match 'Generally Available') { $tag = 'GA' }
            elseif ($it.title -match 'Public Preview|In preview|\[Preview\]') { $tag = 'Preview' }
            elseif ($it.title -match 'Retirement|Deprecat|End of support|Retiring') { $tag = 'Retirement' }
            $cleanTitle = ($it.title -replace '^\s*\[[^\]]+\]\s*', '').Trim()
            $pd = $null
            try { $pd = ([datetime]$it.pubDate).ToString('yyyy-MM-dd') } catch { $pd = ([string]$it.pubDate) }
            $desc = ''
            if ($it.description) { $desc = (($it.description -replace '<[^>]+>', ' ') -replace '\s+', ' ').Trim() }
            if ($desc.Length -gt 220) { $desc = $desc.Substring(0, 219) + [char]0x2026 }
            $whatsNew += [ordered]@{ title = $cleanTitle; tag = $tag; date = $pd; link = [string]$it.link; desc = $desc }
        }
        Write-Log "  What's new: $($whatsNew.Count) item(s)" Success
    }
    catch {
        Write-Log "  What's new feed unavailable: $($_.Exception.Message)" Warning
    }
}

$generatedBuildUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC'

$model = [ordered]@{
    product      = $ProductName
    title        = $Title
    workspace    = $workspace
    counts       = $counts
    cost         = $costModel
    findings     = $findings
    mitre        = $mitre
    mitreCovered = $mitreCovered
    mitreCoveredThreshold = $script:MitreCoveredThreshold
    flow         = $flow
    flowTables   = $flowTables
    topRules     = $topRules
    health       = [ordered]@{ pct = $healthPct; totalEvents = [int]$healthTotal; rows = @($healthSum | Where-Object { $_ }) }
    estate       = $estate
    effectiveness = $effectiveness
    usageDaily   = $usageDaily
    maturity     = $maturityModel
    detectionOpportunities = $detectionOpportunities
    huntsSummary = $huntsSummary
    playbookHealth = $playbookHealth
    tiBySource   = $tiBySource
    tiObjects    = $tiObjects
    incidentsByClassification = $incidentsByClassification
    familyOrder  = @(Get-SectionFamilyOrder)
    sections     = $sections
    dataLakeEnrolled = $lakeEnrolled
    dataLake     = $dataLakeModel
    whatsNew     = $whatsNew
    generatedBlueprintUtc = $generatedBuildUtc
}

Write-Log "  Sections   : $($sections.Count)   Charts: $chartCount (drawn by the chart web part)" Info
Write-Log "  Findings   : $($findings.total)   Rules enabled: $($counts.rulesEnabled)/$($counts.rulesTotal)   MITRE: $mitreCovered/$($mitre.Count)" Info
Write-Log "  Maturity   : $(if ($maturityModel -and $null -ne $maturityModel.overall.score) { "$($maturityModel.overall.score) / 5 ($($maturityModel.overall.levelName)), target $($maturityModel.targetLevel)" } else { 'not assessed' })   Uncovered: $(if ($ruleRefs.Count -gt 0) { "$uncoveredTotal table(s), $($estate.uncoveredGb) GB" } else { 'n/a' })" Info

# ---------------------------------------------------------------------------
# Findings for the SharePoint list
# ---------------------------------------------------------------------------

$gapChecksPath = Join-Path $script:RawRoot 'gap-checks.json'
$checks = $null
if (Test-Path -LiteralPath $gapChecksPath) {
    $checkRows = Read-RawArray 'gap-checks.json'
    $checks = @($checkRows | Where-Object { $_ } | ForEach-Object { [ordered]@{ id = $_.Id; outcome = $_.Outcome } })
}
$findingsDoc = [ordered]@{
    generatedUtc      = $generatedUtc
    analysisAvailable = (Test-Path -LiteralPath (Join-Path $script:RawRoot 'gap-analysis.json'))
    items             = $findingList
    checks            = $checks
}
if ($null -eq $checks) {
    $buildWarnings.Add('No _raw/gap-checks.json in this snapshot (collected before per-check outcomes were recorded). Findings that stop firing will be resolved on absence.')
}

# ---------------------------------------------------------------------------
# Write the bundle
# ---------------------------------------------------------------------------

$pagesDir = Join-Path $OutputRoot 'pages'

if ($PSCmdlet.ShouldProcess($OutputRoot, 'Prepare bundle folder')) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    # diagrams/ is what a bundle built before charts became data carried.
    foreach ($d in $pagesDir, (Join-Path $OutputRoot 'diagrams')) {
        if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
    }
    New-Item -ItemType Directory -Path $pagesDir -Force | Out-Null
}

# Dashboard. EscapeHtml encodes <, >, & and quotes as \uXXXX so no value in
# the data (a rule name, finding evidence, a feed title) can close the
# <script type="application/json"> block it is embedded in.
$modelJson = $model | ConvertTo-Json -Depth 24 -Compress -EscapeHandling EscapeHtml
$template = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'templates/sharepoint-dashboard.html') -Raw -Encoding utf8
$html = $template.Replace('__TITLE__', (ConvertTo-HtmlText $Title)).Replace('/*__MODEL__*/null', $modelJson)
$indexPath = Join-Path $OutputRoot 'index.html'
if ($PSCmdlet.ShouldProcess($indexPath, 'Write dashboard HTML')) {
    Set-Content -LiteralPath $indexPath -Value $html -Encoding utf8 -NoNewline
}
Write-BundleJson -Path (Join-Path $OutputRoot 'model.json') -Data $model -What 'Write dashboard model'

foreach ($p in $pageDocs) {
    Write-BundleJson -Path (Join-Path $pagesDir "$($p.name).json") -Data $p -What 'Write page'
}

Write-BundleJson -Path (Join-Path $OutputRoot 'findings.json') -Data $findingsDoc -What 'Write findings'

$site = [ordered]@{
    schemaVersion = 1
    product       = $ProductName
    title         = "$ProductName - $WorkspaceName"
    workspace     = [ordered]@{
        name           = $WorkspaceName
        id             = $workspace.id
        region         = $workspace.region
        subscriptionId = $workspace.subscriptionId
        resourceGroup  = $workspace.resourceGroup
    }
    generatedUtc  = $generatedUtc
    builtUtc      = $generatedBuildUtc
    blueprintVersion = $workspace.blueprintVer
    dashboard     = [ordered]@{ page = $script:DashboardPage; file = 'index.html' }
    findingsList  = [ordered]@{ title = $script:FindingsTitle; url = $script:FindingsListUrl }
    familyOrder   = @(Get-SectionFamilyOrder)
    sections      = $siteSections
    # Always empty now that charts are data: the publisher recycles the
    # diagram images an earlier bundle uploaded.
    diagrams      = @()
    warnings      = $buildWarnings.ToArray()
}
Write-BundleJson -Path (Join-Path $OutputRoot 'site.json') -Data $site -What 'Write site descriptor'

foreach ($w in $buildWarnings) { Write-Log "  ! $w" Warning }
Write-Log "Bundle -> $OutputRoot ($($pageDocs.Count) pages, $chartCount charts, $($findingList.Count) findings)" Success

return $OutputRoot
