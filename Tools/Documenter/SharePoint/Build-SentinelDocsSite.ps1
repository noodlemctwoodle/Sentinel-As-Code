#Requires -Version 7.2

<#
.SYNOPSIS
    Build the iSOC Blueprint SharePoint site bundle from a Sentinel
    Documenter workspace snapshot.

.DESCRIPTION
    Reads one Documenter workspace folder (the _raw/*.json snapshot that
    Export-SentinelInventory.ps1 writes, the section *.md files that
    Convert-SentinelInventoryToMarkdown.ps1 renders next to it, and any
    assets/*.png that Convert-MermaidToImage.ps1 produced) and writes
    everything Publish-SentinelDocsSite.ps1 needs into one folder:

      index.html          the interactive dashboard: a single self-contained
                          HTML file (inline CSS and JS, data embedded as
                          JSON) that the site's home page hosts
      model.json          the dashboard's data model
      site.json           site descriptor: product name, workspace, the
                          section list with page names, families and hashes
      pages/<page>.json   one file per section: title and the ordered
                          segments (HTML for Text web parts, image
                          references for Image web parts)
      diagrams/*.png      the pre-rendered diagrams the pages reference
      findings.json       gap-analysis findings plus per-check outcomes,
                          for the findings list

    Nothing here talks to SharePoint or Azure, so the bundle can be built
    from a downloaded pipeline artefact and inspected before publishing.
    The one network call is the optional "What's new" feed (Microsoft's
    Azure release-communications RSS), fetched at build time and baked into
    the dashboard. Pass -SkipWhatsNew to build fully offline.

    Run Convert-MermaidToImage.ps1 against the snapshot first. Pages show a
    "diagram not rendered" note in place of any Mermaid block that was not
    pre-rendered, and the build reports a warning for each.

.PARAMETER Source
    Documenter workspace folder: the directory that contains _raw/ and the
    rendered section files (for example SecurityDocs/law-sentinel-prod).

.PARAMETER OutputRoot
    Bundle folder. Defaults to '<Source>/sharepoint'. The pages/ and
    diagrams/ subfolders are cleared at the start of each build so a
    removed section never lingers.

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
    tables are cut with a note pointing at the Markdown output.

.OUTPUTS
    [string] The bundle folder path.

.EXAMPLE
    ./Tools/Documenter/SharePoint/Build-SentinelDocsSite.ps1 `
        -Source ./SecurityDocs/law-sentinel-prod

    Builds the bundle into ./SecurityDocs/law-sentinel-prod/sharepoint.

.EXAMPLE
    ./Tools/Documenter/SharePoint/Build-SentinelDocsSite.ps1 `
        -Source ./artefact/law-sentinel-prod -SkipWhatsNew -WhatIf

    Shows what would be written without writing anything or fetching the
    feed.

.NOTES
    File:         Tools/Documenter/SharePoint/Build-SentinelDocsSite.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-07
    Version:      0.2.0
    Last Updated: 2026-10-08
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
        return $text | ConvertFrom-Json -Depth 64
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
# Markdown -> structured blocks for the dashboard's Sections tab. The native
# pages use ConvertTo-SharePointPageSegments instead; the dashboard keeps its
# own light parser because its charts, stat chips and table filters work off
# these blocks.
# ---------------------------------------------------------------------------

function Format-InlineMarkdown {
    param([string] $Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $s = $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
    $s = [regex]::Replace($s, '`([^`]+)`', '<code>$1</code>')
    # Links: keep real http(s) links; render internal .md cross-references as
    # plain emphasised text.
    $s = [regex]::Replace($s, '\[([^\]]+)\]\(([^)]+)\)', {
            param($m)
            $txt = $m.Groups[1].Value; $url = $m.Groups[2].Value
            if ($url -match '^https?://') { "<a href=`"$url`" target=`"_blank`" rel=`"noopener`">$txt</a>" }
            else { "<span class=`"xref`">$txt</span>" }
        })
    $s = [regex]::Replace($s, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
    $s = [regex]::Replace($s, '(?<!\*)\*(?!\*)([^*]+)\*(?!\*)', '<em>$1</em>')
    return $s
}

function Split-TableRow {
    param([string] $Row)
    $r = $Row.Trim()
    $r = $r -replace '^\|', '' -replace '\|\s*$', ''
    return @($r -split '\|' | ForEach-Object { $_.Trim() })
}

function ConvertTo-SectionBlocks {
    <#
    .SYNOPSIS
        Parse one Documenter Markdown file into an ordered list of render
        blocks: headings, prose, notes (callouts), lists and tables. Image
        references, code fences (Mermaid source), raw anchors, horizontal
        rules and the standard metadata header are dropped.
    #>
    param([string] $Path)

    $lines = @(Get-Content -LiteralPath $Path -Encoding utf8)
    $blocks = [System.Collections.ArrayList]::new()
    $para = [System.Collections.Generic.List[string]]::new()

    $flush = {
        if ($para.Count) {
            [void]$blocks.Add([ordered]@{ t = 'p'; html = (Format-InlineMarkdown (($para -join ' ').Trim())) })
            $para.Clear()
        }
    }

    $i = 0
    while ($i -lt $lines.Count) {
        $ln = $lines[$i]

        if ($ln -match '^\s*```') {
            # Fenced block (Mermaid when not pre-rendered). The dashboard draws
            # its own charts, so the source is skipped rather than shown as text.
            & $flush
            $i++
            while ($i -lt $lines.Count -and $lines[$i] -notmatch '^\s*```') { $i++ }
            $i++; continue
        }
        if ($ln -match '^\s*$') { & $flush; $i++; continue }
        if ($ln -match '^#\s') { & $flush; $i++; continue }                  # H1 = title, captured separately
        if ($ln -match '^!\[') { $i++; continue }                             # image reference -> drop
        if ($ln -match '^\s*<a id="[^"]*"></a>\s*$') { $i++; continue }      # finding anchor -> drop
        if ($ln -match '^\s*-{3,}\s*$') { & $flush; $i++; continue }         # horizontal rule -> drop

        if ($ln -match '^(#{2,6})\s+(.*)') {
            & $flush
            [void]$blocks.Add([ordered]@{ t = 'h'; lvl = $Matches[1].Length; html = (Format-InlineMarkdown $Matches[2].Trim()) })
            $i++; continue
        }

        if ($ln -match '^>\s?(.*)') {
            $buf = [System.Collections.Generic.List[string]]::new()
            while ($i -lt $lines.Count -and $lines[$i] -match '^>\s?(.*)') { $buf.Add($Matches[1]); $i++ }
            $joined = ($buf -join "`n")
            if ($joined -match '\*\*Workspace\*\*' -and $joined -match 'Documenter') { continue }   # metadata header
            & $flush
            # Preserve structure inside the callout: an optional lead line + bullet items.
            $noteTitle = ''
            $noteItems = [System.Collections.Generic.List[string]]::new()
            $noteText = [System.Collections.Generic.List[string]]::new()
            foreach ($bl in $buf) {
                $t = $bl.Trim()
                if ($t -eq '') { continue }
                if ($t -match '^[-*+]\s+(.*)') { $noteItems.Add((Format-InlineMarkdown $Matches[1].Trim())) }
                elseif ($noteItems.Count -eq 0 -and $noteText.Count -eq 0 -and $t -notmatch '\s') { $noteTitle = (Format-InlineMarkdown $t) }
                elseif ($noteItems.Count -eq 0 -and $noteText.Count -eq 0 -and $t -match '^[A-Za-z][\w &/-]{1,24}$') { $noteTitle = (Format-InlineMarkdown $t) }
                else { $noteText.Add((Format-InlineMarkdown $t)) }
            }
            $note = [ordered]@{ t = 'note'; title = $noteTitle; items = $noteItems.ToArray(); paras = $noteText.ToArray() }
            if (-not $note.title -and -not $note.items.Count -and -not $note.paras.Count) {
                $note.paras = @((Format-InlineMarkdown ($joined -replace "`n", ' ')))
            }
            [void]$blocks.Add($note)
            continue
        }

        if ($ln -match '^\|') {
            & $flush
            $tbl = [System.Collections.Generic.List[string]]::new()
            while ($i -lt $lines.Count -and $lines[$i] -match '^\|') { $tbl.Add($lines[$i]); $i++ }
            if ($tbl.Count -lt 1) { continue }
            $headers = @(Split-TableRow $tbl[0] | ForEach-Object { Format-InlineMarkdown $_ })
            $align = @()
            $dataStart = 1
            if ($tbl.Count -gt 1 -and $tbl[1] -match '^[\|\s:\-]+$') {
                foreach ($c in (Split-TableRow $tbl[1])) {
                    if ($c -match '^:-+:$') { $align += 'center' }
                    elseif ($c -match '-+:$') { $align += 'right' }
                    else { $align += 'left' }
                }
                $dataStart = 2
            }
            $rows = [System.Collections.ArrayList]::new()
            for ($r = $dataStart; $r -lt $tbl.Count; $r++) {
                [void]$rows.Add(@(Split-TableRow $tbl[$r] | ForEach-Object { Format-InlineMarkdown $_ }))
            }
            [void]$blocks.Add([ordered]@{ t = 'table'; headers = $headers; align = $align; rows = $rows.ToArray() })
            continue
        }

        if ($ln -match '^\s*[-*+]\s+(.*)' -or $ln -match '^\s*\d+\.\s+(.*)') {
            & $flush
            $items = [System.Collections.ArrayList]::new()
            while ($i -lt $lines.Count -and ($lines[$i] -match '^\s*[-*+]\s+(.*)' -or $lines[$i] -match '^\s*\d+\.\s+(.*)')) {
                [void]$items.Add((Format-InlineMarkdown $Matches[1].Trim())); $i++
            }
            [void]$blocks.Add([ordered]@{ t = 'ul'; items = $items.ToArray() })
            continue
        }

        $para.Add($ln.Trim()); $i++
    }
    & $flush
    return $blocks.ToArray()
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
    throw "No _raw/ folder under '$Source'. Point -Source at a Documenter workspace folder (the one containing _raw/)."
}

$runCtx = Read-Raw 'run-context.json'
if (-not $WorkspaceName) {
    $WorkspaceName = if ($runCtx -and $runCtx.WorkspaceName) { $runCtx.WorkspaceName } else { Split-Path $Source -Leaf }
}
if (-not $Title)      { $Title = "$WorkspaceName - $ProductName" }
if (-not $OutputRoot) { $OutputRoot = Join-Path $Source 'sharepoint' }

Write-Log "Sentinel Documenter -> SharePoint site bundle" Section
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
    documenterVer   = if ($runCtx) { $runCtx.DocumenterVersion } else { '' }
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
    }
    if ($cost.ByPlan) {
        foreach ($p in $cost.ByPlan.PSObject.Properties) {
            $costModel.byPlan += [ordered]@{ plan = $p.Name; gb30d = [math]::Round([double]$p.Value.Gb30d, 2); cost = [math]::Round([double]$p.Value.MonthlyCost, 2) }
        }
    }
    foreach ($t in @($cost.Top10TablesByCost | Where-Object { $_ })) {
        $costModel.topTables += [ordered]@{ table = $t.Table; plan = $t.Plan; gb30d = [math]::Round([double]$t.Gb30d, 2); cost = [math]::Round([double]$t.MonthlyCost, 2) }
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

# ---- Ingest / billing flow (grounded in cost-estimate) ----
$flowNodes = @()
$flowLinks = @()
if ($cost) {
    $ingest = @($cost.AllTablesByCost | Where-Object { $_ -and [double]$_.Gb30d -gt 0 } | Sort-Object { [double]$_.Gb30d } -Descending)
    $topN = 9
    $top = @($ingest | Select-Object -First $topN)
    $rest = @($ingest | Select-Object -Skip $topN)

    $tableRows = @()
    foreach ($t in $top) {
        $tableRows += [ordered]@{ table = $t.Table; family = (Get-TableFamily $t.Table); plan = $t.Plan; gb = [math]::Round([double]$t.Gb30d, 3); billed = ([double]$t.MonthlyCost -gt 0) }
    }
    if ($rest.Count -gt 0) {
        $restGb = ($rest | Measure-Object -Property Gb30d -Sum).Sum
        $restBilled = (@($rest | Where-Object { [double]$_.MonthlyCost -gt 0 } | Measure-Object -Property Gb30d -Sum).Sum)
        # Represent the long tail as one synthetic table node, split billed/free by Gb.
        $tableRows += [ordered]@{ table = "Other (+$($rest.Count))"; family = 'Other'; plan = 'Analytics'; gb = [math]::Round([double]$restGb, 3); billed = ($restBilled -gt ($restGb / 2)) }
    }

    # Nodes: families (col0), tables (col1), plans (col2), billed buckets (col3)
    $famAgg = @{}; foreach ($row in $tableRows) { if (-not $famAgg.ContainsKey($row.family)) { $famAgg[$row.family] = 0.0 }; $famAgg[$row.family] += $row.gb }
    $planAgg = @{}; foreach ($row in $tableRows) { if (-not $planAgg.ContainsKey($row.plan)) { $planAgg[$row.plan] = 0.0 }; $planAgg[$row.plan] += $row.gb }
    $bucketAgg = @{ 'Billed' = 0.0; 'Free benefit' = 0.0 }
    foreach ($row in $tableRows) { $bucketAgg[$(if ($row.billed) { 'Billed' } else { 'Free benefit' })] += $row.gb }

    foreach ($fam in ($famAgg.Keys | Sort-Object { $famAgg[$_] } -Descending)) {
        $flowNodes += [ordered]@{ id = "f:$fam"; col = 0; label = $fam; value = [math]::Round($famAgg[$fam], 3) }
    }
    foreach ($row in $tableRows) {
        $flowNodes += [ordered]@{ id = "t:$($row.table)"; col = 1; label = $row.table; value = $row.gb }
    }
    foreach ($pl in ($planAgg.Keys | Sort-Object { $planAgg[$_] } -Descending)) {
        $flowNodes += [ordered]@{ id = "p:$pl"; col = 2; label = "$pl plan"; value = [math]::Round($planAgg[$pl], 3) }
    }
    foreach ($bk in 'Billed', 'Free benefit') {
        if ($bucketAgg[$bk] -gt 0) { $flowNodes += [ordered]@{ id = "b:$bk"; col = 3; label = $bk; value = [math]::Round($bucketAgg[$bk], 3) } }
    }

    # Links
    foreach ($row in $tableRows) {
        $flowLinks += [ordered]@{ source = "f:$($row.family)"; target = "t:$($row.table)"; value = $row.gb }
        $flowLinks += [ordered]@{ source = "t:$($row.table)"; target = "p:$($row.plan)"; value = $row.gb }
    }
    $planBucket = @{}
    foreach ($row in $tableRows) {
        $bk = if ($row.billed) { 'Billed' } else { 'Free benefit' }
        $key = "$($row.plan)|$bk"
        if (-not $planBucket.ContainsKey($key)) { $planBucket[$key] = 0.0 }
        $planBucket[$key] += $row.gb
    }
    foreach ($key in $planBucket.Keys) {
        $parts = $key -split '\|', 2
        $flowLinks += [ordered]@{ source = "p:$($parts[0])"; target = "b:$($parts[1])"; value = [math]::Round($planBucket[$key], 3) }
    }
}
$flow = [ordered]@{ nodes = $flowNodes; links = $flowLinks }

# ---- Top alerting rules (by 30d volume) ----
$topRules = @()
foreach ($v in ($volumes | Where-Object { $_ } | Select-Object -First 10)) {
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
$famAgg2 = [ordered]@{}
$tablesActive = 0; $tablesCovered = 0; $estateTotalGb = 0.0; $estateCoveredGb = 0.0
foreach ($t in $tablesData) {
    if (-not $t -or -not $t.DataType) { continue }
    $gb = ConvertTo-BuildNumber $t.BillableLast30d
    if ($gb -le 0) { continue }
    $tablesActive++; $estateTotalGb += $gb
    $fam = Get-TableFamily $t.DataType
    if (-not $famAgg2.Contains($fam)) { $famAgg2[$fam] = [ordered]@{ category = $fam; tables = 0; gb = 0.0; coveredGb = 0.0; covered = 0 } }
    $famAgg2[$fam].tables++; $famAgg2[$fam].gb += $gb
    if ($referencedTables.ContainsKey([string]$t.DataType)) { $tablesCovered++; $estateCoveredGb += $gb; $famAgg2[$fam].covered++; $famAgg2[$fam].coveredGb += $gb }
}
$sortedFams = @($famAgg2.Values | Sort-Object { $_.gb } -Descending)
$estateSources = @()
foreach ($f in @($sortedFams | Select-Object -First 7)) {
    $estateSources += [ordered]@{ category = $f.category; tables = $f.tables; gb = [math]::Round($f.gb, 2); coveredGb = [math]::Round($f.coveredGb, 2); covered = $f.covered }
}
$famTail = @($sortedFams | Select-Object -Skip 7)
if ($famTail.Count -gt 0) {
    $other = $estateSources | Where-Object { $_.category -eq 'Other' } | Select-Object -First 1
    if (-not $other) { $other = [ordered]@{ category = 'Other'; tables = 0; gb = 0.0; coveredGb = 0.0; covered = 0 }; $estateSources += $other }
    foreach ($f in $famTail) { $other.tables += $f.tables; $other.gb = [math]::Round($other.gb + $f.gb, 2); $other.coveredGb = [math]::Round($other.coveredGb + $f.coveredGb, 2); $other.covered += $f.covered }
}
$alerts30d = [long]0
foreach ($f in $firedRows) { if ($f) { $alerts30d += [long](ConvertTo-BuildNumber $f.Alerts) } }
$incidents30d = if ($incSummaryRow -and $incSummaryRow.PSObject.Properties['Count'])  { [int](ConvertTo-BuildNumber $incSummaryRow.Count) }  else { 0 }
$closed30d    = if ($incSummaryRow -and $incSummaryRow.PSObject.Properties['Closed']) { [int](ConvertTo-BuildNumber $incSummaryRow.Closed) } else { 0 }
$rulesQueryEnabled = @($alertRaw | Where-Object { $_.properties -and $_.properties.enabled -and $_.kind -in @('Scheduled', 'NRT') }).Count
$rulesFiredCount = @($firedRows | Where-Object { $_ }).Count
$estate = [ordered]@{
    window          = '30d'
    sources         = $estateSources
    totalGb         = [math]::Round($estateTotalGb, 2)
    coveredGb       = [math]::Round($estateCoveredGb, 2)
    uncoveredGb     = [math]::Round($estateTotalGb - $estateCoveredGb, 2)
    rings           = [ordered]@{
        ingestion = New-EstateRing 'Tables still receiving data (30d of 90d)' $tablesActive (@($tablesData | Where-Object { $_ }).Count)
        detection = New-EstateRing 'Active tables read by an enabled rule' $tablesCovered $tablesActive
        alerts    = New-EstateRing 'Enabled Scheduled/NRT rules that fired' $rulesFiredCount $rulesQueryEnabled
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
foreach ($e in ($effectRows | Where-Object { $_ } | Sort-Object { ConvertTo-BuildNumber $_.Incidents } -Descending | Select-Object -First 15)) {
    $effectiveness += [ordered]@{
        rule = $e.RuleName; incidents = [int](ConvertTo-BuildNumber $e.Incidents); closed = [int](ConvertTo-BuildNumber $e.Closed)
        tp = [int](ConvertTo-BuildNumber $e.TruePositive); fp = [int](ConvertTo-BuildNumber $e.FalsePositive); bp = [int](ConvertTo-BuildNumber $e.BenignPositive)
        undetermined = [int](ConvertTo-BuildNumber $e.Undetermined); fpRate = [math]::Round((ConvertTo-BuildNumber $e.FPRate), 1)
    }
}

$usageDaily = @()
foreach ($u in ($usageRows | Where-Object { $_ } | Sort-Object { [datetime]$_.Day } | Select-Object -Last 90)) {
    $usageDaily += [ordered]@{ day = ([datetime]$u.Day).ToUniversalTime().ToString('yyyy-MM-dd'); billable = [math]::Round((ConvertTo-BuildNumber $u.BillableGB), 2); free = [math]::Round((ConvertTo-BuildNumber $u.FreeGB), 2) }
}

# Tables with data that no enabled rule reads, with the undeployed templates
# that would cover them (section 28's content, top 12 for the dashboard).
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
    foreach ($t in ($uncovered | Select-Object -First 12)) {
        $name = [string]$t.DataType
        $cands = @($undeployed | Where-Object { @($_.Tables) -contains $name } | Sort-Object { $sv = [string]$_.Severity; if ($sevRank2.ContainsKey($sv)) { $sevRank2[$sv] } else { 9 } }, DisplayName)
        $detectionOpportunities += [ordered]@{
            table     = $name
            family    = (Get-TableFamily $name)
            gb30d     = [math]::Round((ConvertTo-BuildNumber $t.BillableLast30d), 2)
            templates = @($cands | Select-Object -First 3 | ForEach-Object { [ordered]@{ name = $_.DisplayName; severity = $_.Severity } })
            more      = [math]::Max(0, $cands.Count - 3)
        }
    }
}

$huntsSummary = [ordered]@{
    captured       = (Test-Path -LiteralPath (Join-Path $script:RawRoot 'hunts.json'))
    hunts          = @($huntRows | Where-Object { $_ }).Count
    bookmarks      = @($bookmarkRows | Where-Object { $_ }).Count
    huntingQueries = $counts.hunting
}

$pbRuns = 0; $pbFailed = 0; $pbFailing = @()
foreach ($r in ($runRows | Where-Object { $_ })) {
    $runs = [int](ConvertTo-BuildNumber $r.Runs7d); $failed = [int](ConvertTo-BuildNumber $r.Failed7d)
    $pbRuns += $runs; $pbFailed += $failed
    if ($failed -gt 0) {
        $last = if ($r.LastFailureUtc) { ([datetime]$r.LastFailureUtc).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') } else { '' }
        $pbFailing += [ordered]@{ playbook = $r.Playbook; runs = $runs; failed = $failed; lastFailure = $last }
    }
}
$playbookHealth = [ordered]@{ runs7d = $pbRuns; failed7d = $pbFailed; playbooks = @($runRows | Where-Object { $_ }).Count; failing = @($pbFailing | Sort-Object { $_.failed } -Descending) }

$tiBySource = @()
foreach ($row in ($tiCountRows | Where-Object { $_ } | Sort-Object { ConvertTo-BuildNumber $_.Count } -Descending | Select-Object -First 6)) {
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
            [ordered]@{ id = $c.id; area = $a.id; kind = $c.kind; name = $c.name; status = $c.status; effort = $c.effort; impact = $c.impact; evidence = $c.evidence }
        } })
        roadmap          = @(@($maturityRaw.roadmap) | Select-Object -First 20 | ForEach-Object {
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

$assetsDir = Join-Path $Source 'assets'
$sections = @()
$siteSections = @()
$pageDocs = @()
$diagramFiles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

foreach ($md in (Get-ChildItem -LiteralPath $Source -Filter '*.md' | Where-Object { $_.Name -ne 'index.md' } | Sort-Object Name)) {
    if ($md.BaseName -notmatch '^(\d+)-(.*)$') { continue }
    $num = [int]$Matches[1]
    $family = Get-SectionFamily -Number $num
    $pageName = Get-SacPageName -FileName $md.Name

    $markdown = Get-Content -LiteralPath $md.FullName -Raw -Encoding utf8
    $converted = ConvertTo-SharePointPageSegments -Markdown $markdown -FileName $md.Name -FindingsListUrl $script:FindingsListUrl -MaxTableRows $MaxTableRows
    foreach ($w in $converted.Warnings) { $buildWarnings.Add($w) }

    $secTitle = if ($converted.Title) { $converted.Title } else { ($md.BaseName -replace '^\d+-', '' -replace '-', ' ') }

    # Keep only image segments whose file exists, so a page never references
    # a diagram the publisher cannot upload.
    $segments = @()
    foreach ($seg in $converted.Segments) {
        if ($seg.type -eq 'image') {
            $assetPath = Join-Path $assetsDir $seg.file
            if (-not (Test-Path -LiteralPath $assetPath)) {
                $buildWarnings.Add("$($md.Name) : diagram assets/$($seg.file) is missing and was left out.")
                continue
            }
            [void]$diagramFiles.Add($seg.file)
        }
        $segments += $seg
    }

    $hash = Get-ContentHash -Text (([ordered]@{ title = $secTitle; segments = $segments }) | ConvertTo-Json -Depth 8 -Compress)

    $blocks = ConvertTo-SectionBlocks -Path $md.FullName
    $tableRows = 0
    foreach ($b in $blocks) { if ($b.t -eq 'table') { $tableRows += $b.rows.Count } }

    $sections += [ordered]@{
        num       = $num
        file      = $md.Name
        page      = $pageName
        title     = $secTitle
        family    = $family
        headline  = if ($headlineByNum.ContainsKey($num)) { $headlineByNum[$num] } else { '' }
        tableRows = $tableRows
        blocks    = $blocks
    }
    $siteSections += [ordered]@{ num = $num; file = $md.Name; page = $pageName; title = $secTitle; family = $family; hash = $hash }
    $pageDocs += [ordered]@{ name = $pageName; file = $md.Name; num = $num; title = $secTitle; family = $family; hash = $hash; segments = $segments }
}

if ($sections.Count -eq 0) {
    $buildWarnings.Add("No rendered section files (NN-name.md) under $Source. Run Convert-SentinelInventoryToMarkdown.ps1 first; the site will have a dashboard and findings but no section pages.")
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
    dataLakeEnrolled = ($dataLake.Count -gt 0)
    whatsNew     = $whatsNew
    generatedBlueprintUtc = $generatedBuildUtc
}

Write-Log "  Sections   : $($sections.Count)   Diagrams: $($diagramFiles.Count)" Info
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
$diagramsDir = Join-Path $OutputRoot 'diagrams'

if ($PSCmdlet.ShouldProcess($OutputRoot, 'Prepare bundle folder')) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    foreach ($d in $pagesDir, $diagramsDir) {
        if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
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
foreach ($file in $diagramFiles) {
    $dest = Join-Path $diagramsDir $file
    if ($PSCmdlet.ShouldProcess($dest, 'Copy diagram')) {
        Copy-Item -LiteralPath (Join-Path $assetsDir $file) -Destination $dest -Force
    }
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
    documenterVersion = $workspace.documenterVer
    dashboard     = [ordered]@{ page = $script:DashboardPage; file = 'index.html' }
    findingsList  = [ordered]@{ title = $script:FindingsTitle; url = $script:FindingsListUrl }
    familyOrder   = @(Get-SectionFamilyOrder)
    sections      = $siteSections
    diagrams      = @($diagramFiles | Sort-Object)
    warnings      = $buildWarnings.ToArray()
}
Write-BundleJson -Path (Join-Path $OutputRoot 'site.json') -Data $site -What 'Write site descriptor'

foreach ($w in $buildWarnings) { Write-Log "  ! $w" Warning }
Write-Log "Bundle -> $OutputRoot ($($pageDocs.Count) pages, $($diagramFiles.Count) diagrams, $($findingList.Count) findings)" Success

return $OutputRoot
