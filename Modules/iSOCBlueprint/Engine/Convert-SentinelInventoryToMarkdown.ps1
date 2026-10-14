#Requires -Version 7.2
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
    Version:        0.7.4
    Last Updated:   2026-10-14
    Component:      iSOC Blueprint, Renderer
    Requires:       PowerShell 7.2+, powershell-yaml

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

# Strict mode is intentionally NOT set in the renderer.
# The renderer reads JSON shapes from many heterogeneous Azure REST endpoints whose
# nested property graphs differ between API versions (and frequently include null
# branches). StrictMode 'Latest' would force every read access to be defensively
# wrapped, polluting every interpolation. We keep strict mode in the collector and
# the gap engine where shapes are bounded; here we trade strictness for resilience.
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

if (-not $InputRoot)  {
    $InputRoot = Join-Path -Path (Get-Location).ProviderPath -ChildPath "SecurityDocs/$WorkspaceName"
}
if (-not $OutputRoot) { $OutputRoot = $InputRoot }

$rawRoot = Join-Path $InputRoot '_raw'
# Finding ids known to the rule catalogue. The auto-linker in Write-Section
# only links these, so a maturity criterion id that no rule shares stays
# plain text.
$script:FindingIds = @{}
$bpPathForIds = Join-Path $ResourcesRoot 'best-practices.json'
if (Test-Path -LiteralPath $bpPathForIds) {
    foreach ($bpRule in @((Get-Content -LiteralPath $bpPathForIds -Raw | ConvertFrom-Json -Depth 8).rules)) {
        if ($bpRule -and $bpRule.PSObject.Properties['id'] -and $bpRule.id) { $script:FindingIds[[string]$bpRule.id] = $true }
    }
}
if (-not (Test-Path $rawRoot)) {
    throw "Renderer cannot find raw inventory at $rawRoot. Run Export-SentinelInventory.ps1 first."
}
if (-not (Test-Path $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

# Dot-source private helpers.
. (Join-Path $PSScriptRoot 'Private/Get-EffectiveConnectors.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-TableFamily.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-AttackCoverage.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-SearchRestoreTable.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-TemplateSolution.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-WatchlistFreshness.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-ConnectorCatalogue.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-FindingMaturityLink.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-TableTierProfile.ps1')
. (Join-Path $PSScriptRoot 'Private/ConvertFrom-BlueprintMermaid.ps1')
. (Join-Path $PSScriptRoot 'Private/ConvertTo-BlueprintSection.ps1')

# Output formats. The section model is what the SharePoint site reads; the
# Markdown pack feeds the docs pull request and the Word report.
$script:WriteMarkdown = $OutputFormat -contains 'Markdown'
$script:WriteJson     = $OutputFormat -contains 'Json'
$script:SectionsRoot  = Join-Path $OutputRoot 'sections'
$script:SectionIndex  = [System.Collections.Generic.List[object]]::new()
$script:SectionMeta   = $null
if ($script:WriteJson -and -not (Test-Path $script:SectionsRoot)) {
    New-Item -ItemType Directory -Path $script:SectionsRoot -Force | Out-Null
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function _RProp {
    # StrictMode-safe property read: $Default when the object or property is absent or null.
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}
function _RList {
    # The items of a dynamic column (make_set, make_list): an array from a
    # fixture, JSON text ('["Success","Failure"]') from Log Analytics.
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        $t = $Value.Trim()
        if ($t.StartsWith('[')) { try { return @($t | ConvertFrom-Json -ErrorAction Stop | ForEach-Object { [string]$_ }) } catch { return @($t) } }
        return $(if ($t) { @($t) } else { @() })
    }
    return @($Value | ForEach-Object { [string]$_ })
}
function Read-Raw([string]$Name) {
    $p = Join-Path $rawRoot $Name
    if (-not (Test-Path $p)) { return $null }
    $raw = Get-Content $p -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $obj = $raw | ConvertFrom-Json -Depth 32
    # Snapshots collected before the Documenter was renamed Blueprint carry
    # DocumenterVersion; read it as BlueprintVersion.
    if ($Name -eq 'run-context.json' -and $obj -and -not $obj.PSObject.Properties['BlueprintVersion'] -and $obj.PSObject.Properties['DocumenterVersion']) {
        $obj | Add-Member -NotePropertyName BlueprintVersion -NotePropertyValue $obj.DocumenterVersion
    }
    return $obj
}

function Read-RawArray([string]$Name) {
    # Array-shaped reader. Use this when the caller intends to iterate the
    # result via ForEach-Object. Returns an empty array when the underlying
    # file is missing or empty, rather than the one-element-null-array a
    # naive array-wrap of Read-Raw produces. The phantom all-null row that
    # iterating a one-element-null-array yields (and PowerShells own quirk
    # that returns 0 for the Count property of a null reference) is the bug
    # this helper prevents.
    $value = Read-Raw $Name
    if ($null -eq $value) { return ,@() }
    return @($value)
}

function Get-EmptyMessage([string]$Name, [string]$Empty = '_None._') {
    # A capture added after a snapshot was taken leaves no file. Its section
    # says so, rather than claiming the workspace has nothing.
    if (Test-Path (Join-Path $rawRoot $Name)) { return $Empty }
    return '_Not captured in this snapshot._'
}

# What each page covers, for the pages whose opening does not already say:
# Write-Section puts it under the title and the workspace line, so the
# Markdown, the SharePoint pages and the dashboard (above its inner tabs)
# all open with it.
$script:SectionDescriptions = @{
    '00-overview.md'                   = 'The whole assessment on one page: findings by severity, the headline counts, the estate flow, the maturity score, the estimated monthly cost and the most severe findings, each linking to the page that covers it in full.'
    '01-live-snapshot.md'              = 'A summary of the workspace as collected in this run: findings by severity, the workspace at a glance, the estate flow and the top recommendations, with pointers to the pages that go deeper.'
    '10-data-connectors.md'            = 'Which data sources feed the workspace: the classic and Codeless Connector Framework connectors, an effective view that combines them, how the connected ones compare with the Content Hub catalogue, their recent activity and the Defender XDR unification state.'
    '15-incidents.md'                  = 'How incidents move from creation to closure over the last {lookback}: response times, the incident lifecycle and analyst journey, the rules and providers that raise incidents, and how they are closed.'
    '16-alerts.md'                     = 'Alert volume over the last {lookback} by severity, by the product that raised it and by provider, showing where the alert load comes from.'
    '20-analytics-rules.md'            = 'Every analytics rule in the workspace: the mix of rule kinds and states, the full rule list, Microsoft incident-creation and Microsoft-managed rules, recent changes, the Content Hub solutions the rules came from, and Defender XDR custom detections.'
    '30-hunting-queries.md'            = 'The saved hunting queries by ATT&CK tactic, the hunts run in the workspace and the bookmarks analysts have kept.'
    '35-parsers-functions.md'          = 'The KQL parsers and functions saved in the workspace, by category, and its other saved searches.'
    '36-data-export.md'                = 'Where workspace data leaves or is linked: continuous data export rules, linked storage accounts, Azure Data Explorer clusters and other linked services.'
    '40-workbooks.md'                  = 'The workbooks saved in the workspace, how widely they are adopted, and the workbook templates the Content Hub offers.'
    '50-watchlists.md'                 = 'The watchlists in the workspace, which analytics rules use them, and any rule that refers to a watchlist that does not exist.'
    '60-automation-rules-playbooks.md' = 'How incidents are handled automatically: the automation rules, the Logic Apps playbooks they run, how those runs went in the last {lookback}, and recurring incident titles automation could take on.'
    '70-content-hub.md'                = 'Where the workspace content comes from: the Content Hub solutions installed, any that are deprecated or unlisted, connected repositories and legacy management solutions.'
    '80-workspace.md'                  = 'The Log Analytics workspace itself: its history and provenance, pricing tier, usage, networking and replication, resilience, feature flags, Sentinel onboarding and resource locks.'
    '81-table-plans-retention.md'      = 'Every table in the workspace by plan, retention and recent activity: which tables receive data, which have gone silent, orphan and legacy custom tables, and how well each is covered by detections.'
    '82-dedicated-cluster.md'          = 'Whether the workspace is linked to a Log Analytics dedicated cluster, and that cluster''s capacity reservation, billing and encryption settings.'
    '83-data-collection.md'            = 'How data reaches the workspace through Azure Monitor: the data collection rules and endpoints that target it, and other rules in the subscription that send elsewhere.'
    '84-cost-estimate.md'              = 'An estimate of the monthly cost from {lookback} of billable ingestion: cost by plan and by table, where it concentrates, how it flows to the billing tiers, what a commitment tier would save, and how the estimate is worked out.'
    '85-rbac.md'                       = 'Who can do what in the workspace: role assignments by role, the Microsoft Sentinel and Log Analytics roles, high-privilege assignments, and assignments at workspace and resource-group scope.'
    '91-maturity-assessment.md'        = 'How mature the workspace is, scored 0 to 5 across eleven capability areas from the gap findings and the captured configuration, with the roadmap of criteria to close to reach the target level.'
    '86-subscription-context.md'       = 'The Azure subscription and tenant around the workspace: the subscription, the identity that ran the collection, resource-provider registration, locks and the policy assignments that affect Sentinel.'
}

# The window the collector's KQL captures read (run-context.json): every
# capture's lookback, and the recent window (the shorter of 7 days and the
# lookback) its latest-days figures cover. A snapshot collected before the
# setting existed read 30 days and 7. Pages name the window through tokens,
# {lookback}, {lookback-d}, {recent} and {recent-d}, which Write-Section
# fills, so a label, a heading or a chart title follows whatever the run
# read. The "30d", "90d" and "7d" property names in the captures are their
# historical names for the lookback and recent figures.
function Get-BpWindow {
    if ($script:BpWindow) { return $script:BpWindow }
    $rc = Read-Raw 'run-context.json'
    $days = 30
    if ($rc -and $rc.PSObject.Properties['LookbackDays'] -and [int]$rc.LookbackDays -ge 1) { $days = [int]$rc.LookbackDays }
    $recent = [math]::Min(7, $days)
    if ($rc -and $rc.PSObject.Properties['RecentDays'] -and [int]$rc.RecentDays -ge 1) { $recent = [int]$rc.RecentDays }
    $script:BpWindow = [pscustomobject]@{ Days = $days; RecentDays = $recent }
    return $script:BpWindow
}
function Resolve-BpWindowText([string]$Text) {
    if (-not $Text -or $Text.IndexOf('{') -lt 0) { return $Text }
    $w = Get-BpWindow
    $words = { param([int]$n) if ($n -eq 1) { '1 day' } else { "$n days" } }
    return $Text.Replace('{lookback-d}', "$($w.Days)d").Replace('{recent-d}', "$($w.RecentDays)d").Replace('{lookback}', (& $words $w.Days)).Replace('{recent}', (& $words $w.RecentDays))
}

# A page's reference links all sit at its foot, so a reader knows where to
# look. A paragraph or list that holds only external links (the Microsoft
# Learn pointers under a section, a finding's "Reference:", "See A and B.")
# moves out of the page into one References list at the end, each link
# once, in the order the page first gives it. A finding's reference names
# the finding. Links inside a sentence or a table stay where they are.
function Move-ReferenceLinks([string]$Markdown) {
    $nl = [Environment]::NewLine
    $linkRx = '\[((?:[^\[\]]|\[[^\]]*\])+)\]\((https?://[^)\s]+)\)'
    $isLinksOnly = {
        param([string]$Text)
        $found = [regex]::Matches($Text, $linkRx)
        if ($found.Count -eq 0) { return $null }
        $rest = [regex]::Replace($Text, $linkRx, ' ').Trim()
        $rest = $rest -replace '^(\*\*)?(see also|see|references?|docs|further reading|read more)\s*:?\s*(\*\*)?\s*:?', ''
        $rest = $rest -replace '\band\b|&middot;|[\u00B7,;.:\s]', ''
        if ($rest) { return $null }
        return , @($found | ForEach-Object { [pscustomobject]@{ Text = $_.Groups[1].Value; Url = $_.Groups[2].Value } })
    }
    $lines = $Markdown -split '\r?\n'
    $keep = [System.Collections.Generic.List[string]]::new()
    $refs = [System.Collections.Generic.List[object]]::new()
    $inFence = $false; $finding = $null; $i = 0
    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        if ($line -match '^\s*```') { $inFence = -not $inFence; $keep.Add($line); $i++; continue }
        if ($inFence -or -not $line.Trim()) { $keep.Add($line); $i++; continue }
        if ($line -match '^#{1,6}\s') {
            $finding = if ($line -match '^#{2,4}\s+\[?(SAC-[A-Z]{2,4}-\d{2})\b') { $Matches[1] } else { $null }
            $keep.Add($line); $i++; continue
        }
        # One block: the lines up to the next blank line, fence or heading.
        $j = $i
        while ($j -lt $lines.Count -and $lines[$j].Trim() -and $lines[$j] -notmatch '^\s*```' -and $lines[$j] -notmatch '^#{1,6}\s') { $j++ }
        $block = $lines[$i..($j - 1)]
        $links = $null
        if ($block[0] -notmatch '^\s*[|>]|^\s*<') {
            $items = if (@($block | Where-Object { $_ -notmatch '^\s*[-*]\s' }).Count -eq 0) { @($block | ForEach-Object { $_ -replace '^\s*[-*]\s+', '' }) } else { @($block -join ' ') }
            $all = [System.Collections.Generic.List[object]]::new()
            foreach ($it in $items) { $got = & $isLinksOnly $it; if ($null -eq $got) { $all = $null; break }; $all.AddRange([object[]]$got) }
            $links = $all
        }
        if ($links) {
            foreach ($l in $links) { $refs.Add([pscustomobject]@{ Text = $l.Text; Url = $l.Url; Finding = $finding }) }
        } else {
            foreach ($b in $block) { $keep.Add($b) }
        }
        $i = $j
    }
    if (-not $refs.Count) { return $Markdown }
    $byUrl = [ordered]@{}
    foreach ($r in $refs) {
        if (-not $byUrl.Contains($r.Url)) { $byUrl[$r.Url] = [pscustomobject]@{ Text = $r.Text; Findings = [System.Collections.Generic.List[string]]::new() } }
        if ($r.Finding -and -not $byUrl[$r.Url].Findings.Contains($r.Finding)) { $byUrl[$r.Url].Findings.Add($r.Finding) }
    }
    $list = foreach ($u in $byUrl.Keys) {
        $e = $byUrl[$u]
        $text = if ($e.Findings.Count) { ($e.Findings -join ', ') + ': ' + $e.Text } else { $e.Text }
        "- [$text]($u)"
    }
    $page = (($keep -join $nl) -replace "(\r?\n){3,}", ($nl + $nl)).TrimEnd()
    return $page + $nl + $nl + '## References' + $nl + $nl + ($list -join $nl) + $nl
}

function Write-Section([string]$FileName, [string]$Body) {
    $target = Join-Path $OutputRoot $FileName
    $body = $Body.TrimEnd() + [Environment]::NewLine
    # The window the KQL captures read, named where a page says {lookback}
    # ("30 days"), {lookback-d} ("30d"), {recent} or {recent-d}.
    $body = Resolve-BpWindowText $body
    # The page's description goes under the title and its workspace line.
    if ($script:SectionDescriptions.ContainsKey($FileName)) {
        $desc = Resolve-BpWindowText $script:SectionDescriptions[$FileName]
        $nl = [Environment]::NewLine
        $banner = [regex]::Match($body, '(?m)^> \*\*Workspace\*\*.*$')
        $title = [regex]::Match($body, '(?m)^# .*$')
        $at = if ($banner.Success) { $banner.Index + $banner.Length } elseif ($title.Success) { $title.Index + $title.Length } else { -1 }
        if ($at -ge 0) { $body = $body.Substring(0, $at) + $nl + $nl + $desc + $nl + $body.Substring($at) }
    }
    # Auto-link finding mentions. Two passes:
    #   1. `[SAC-<AREA>-NN]` text-in-brackets NOT followed by `(` → wrap with URL.
    #      This catches the bullet-list format already used in 00-overview
    #      and 01-live-snapshot's "Top recommendations" blocks where the
    #      square brackets are literal (Markdown treats `[X]` without a
    #      following `(...)` as plain text).
    #   2. Bare `SAC-<AREA>-NN` not already inside a Markdown link → wrap.
    # On 90-gap-analysis.md itself the target collapses to just the anchor
    # so internal links work (`[SAC-LOG-03](#sac-log-03)`). Existing links are
    # preserved — the lookarounds skip anything already followed by `](`.
    $relTarget = if ($FileName -eq '90-gap-analysis.md') { '' } else { '90-gap-analysis.md' }

    # Walk the body line-by-line, tracking fenced-code state. Auto-link only
    # outside fences — references inside ```mermaid / ```kusto / etc must
    # render literally (Mermaid `click` directives in 85-rbac use finding ids
    # in their tooltips and break if rewritten).
    $sb = New-Object System.Text.StringBuilder
    $inFence = $false
    foreach ($line in ($body -split "(`r?`n)")) {
        if ($line -match '^\s*```') { $inFence = -not $inFence; [void]$sb.Append($line); continue }
        if ($inFence) { [void]$sb.Append($line); continue }
        # A bp: comment carries data for the site (a graphic's JSON); its ids stay as written.
        if ($line -match '^<!--\s*bp:') { [void]$sb.Append($line); continue }
        # Pass 1: bracketed-but-unlinked IDs (only ids the rule catalogue knows).
        $line = [regex]::Replace($line, '\[(SAC-[A-Z]{2,4}-\d{2})\](?!\()', {
            param($m)
            $id = $m.Groups[1].Value
            if (-not $script:FindingIds.ContainsKey($id)) { return $m.Value }
            "[$id]($relTarget#$($id.ToLower()))"
        })
        # Pass 2: bare IDs not preceded by `[`, `(`, `#`, `-` or a word
        # character and not followed by `]`, `)`, `-` or a word character.
        # On the maturity page and the What's new page the same ids name
        # criteria, so only ids whose finding fired in this run (and so has an
        # anchor on 90) are linked.
        $linkable = if ($FileName -in '91-maturity-assessment.md', '03-whats-new.md') { $script:FiredFindingIds } else { $script:FindingIds }
        $line = [regex]::Replace($line, '(?<![\[\(#\-\w])(SAC-[A-Z]{2,4}-\d{2})(?![\]\)\-\w])', {
            param($m)
            $id = $m.Groups[1].Value
            if (-not $linkable.ContainsKey($id)) { return $m.Value }
            "[$id]($relTarget#$($id.ToLower()))"
        })
        [void]$sb.Append($line)
    }
    $body = $sb.ToString()
    # After the auto-linker, so the finding ids a moved reference names stay text.
    if ($FileName -ne 'index.md') { $body = Move-ReferenceLinks $body }
    if ($script:WriteMarkdown) {
        Set-Content -Path $target -Value $body -Encoding UTF8
        Write-Information "  ↳ rendered $FileName"
    }
    if ($script:WriteJson) { Write-SectionModel -FileName $FileName -Markdown $body }
}

function Write-SectionModel([string]$FileName, [string]$Markdown) {
    # sections/<id>.json: the section model for this section. The contents
    # page (index.md) has none: sections/index.json lists the sections.
    if ($FileName -eq 'index.md') { return }
    if (-not $script:SectionMeta) {
        $rc = Read-Raw 'run-context.json'
        $script:SectionMeta = [ordered]@{
            workspace        = $WorkspaceName
            generatedUtc     = $(if ($rc -and $rc.StartedAtUtc) { ([datetime]$rc.StartedAtUtc).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null })
            blueprintVersion = $(if ($rc -and $rc.BlueprintVersion) { [string]$rc.BlueprintVersion } else { $null })
        }
    }
    $id = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $model = ConvertTo-BlueprintSection -Markdown $Markdown -Id $id -Meta $script:SectionMeta
    $model | ConvertTo-Json -Depth 64 | Set-Content -Path (Join-Path $script:SectionsRoot "$id.json") -Encoding utf8
    $script:SectionIndex.Add([ordered]@{ id = $id; order = $model.order; title = $model.title; file = "$id.json" })
    if (-not $script:WriteMarkdown) { Write-Information "  ↳ rendered sections/$id.json" }
}

function Format-DateUtc {
    # Renders any datetime-ish input (string ISO, [datetime]) as
    # `yyyy-MM-dd HH:mm` — locale-invariant, seconds dropped to reduce
    # column width. Empty / null / unparseable inputs return ''.
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
        return $parsed.ToUniversalTime().ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $s
}

function Format-Gb {
    # Renders any numeric-ish input as a GB value to 3 decimal places.
    # Values below 0.001 GB render as `<0.001` so a meaningful "non-zero
    # but tiny" signal isn't lost to rounding. Empty / null / non-numeric
    # inputs return ''.
    param($Value)
    if ($null -eq $Value) { return '' }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $d = 0.0
    if (-not [double]::TryParse($s, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $s }
    if ($d -eq 0) { return '0' }
    if ($d -gt 0 -and $d -lt 0.001) { return '<0.001' }
    return $d.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Format-Banner {
    param([string]$Title)
    $run = Read-Raw 'run-context.json'
    $started = if ($run) { Format-DateUtc $run.StartedAtUtc } else { '' }
    @"
# $Title

> **Workspace** ``$WorkspaceName``  ·  **Generated** $started UTC  ·  **Blueprint** v$($run.BlueprintVersion)
"@
}

# A column named after a raw property (Gb30d, MonthlyCost, LastFailureUtc)
# reads as words in a table header: the names below as written, any other
# CamelCase name split into words. A name with a space or in one word keeps
# its text.
$script:ColumnLabels = @{
    Gb30d = 'GB ({lookback-d})'; Gb7d = 'GB ({recent-d})'; Gb90d = 'GB ({lookback-d})'; GbRead = 'GB read'; Last24hGB = 'GB (24h)'
    BillableLast24hGB = 'Billable GB (24h)'; BilledSizeGB = 'Billed GB'; SizeMB = 'Size (MB)'
    Data7d = 'Data ({recent-d})'; Failed7d = 'Failed ({lookback-d})'; Records30d = 'Records ({lookback-d})'; Records7d = 'Records ({recent-d})'
    Rows7d = 'Rows ({recent-d})'; Rows12d = 'Rows ({lookback-d})'; Rows14d = 'Rows ({lookback-d})'; Runs7d = 'Runs ({lookback-d})'; Last24h = 'Last 24h'
    FPRate = 'FP rate'; LastFailureUtc = 'Last failure (UTC)'; EventID = 'Event ID'; OSType = 'OS type'; OSVersion = 'OS version'
    AMACount = 'AMA machines'; MMACount = 'MMA machines'; ResourceId = 'Resource ID'; SubscriptionId = 'Subscription ID'
    WriteAccessResourceId = 'Write access resource ID'; TargetsWs = 'Targets workspace'; SkuName = 'SKU'
    DeltaVsCurrent = 'Change vs current'; AvgMinsToClose = 'Average minutes to close'; ClosedWithinHour = 'Closed within an hour'
    SignIn = 'Sign-in'; SearchRestore = 'Search and restore'; SubTechniques = 'Sub-techniques'; StixType = 'STIX type'
    DuplicateEventIds = 'Duplicate event IDs'; FirstPartyAlerts = 'First-party alerts'; LakeOnlyDays = 'Lake-only days'
    AnalyticsDays = 'Analytics days'; RetentionDays = 'Retention (days)'; TotalDays = 'Total days'; HasTransform = 'Transform'
    MonthlyCost = 'Monthly cost'; ProjectedMonthlyCost = 'Projected monthly cost'
}
function Format-ColumnLabel([string]$Name) {
    if ($script:ColumnLabels.ContainsKey($Name)) { return $script:ColumnLabels[$Name] }
    if ($Name -cnotmatch '^[A-Za-z][A-Za-z0-9]*$' -or $Name -cnotmatch '[a-z][A-Z]|[A-Z]{2}[a-z]') { return $Name }
    $words = @([regex]::Split($Name, '(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])'))
    $rest = @($words | Select-Object -Skip 1 | ForEach-Object { if ($_ -cmatch '^[A-Z]{2,}$') { $_ } else { $_.ToLowerInvariant() } })
    return (@($words[0]) + $rest) -join ' '
}

function Format-Table {
    <# Render an array of [pscustomobject] as a Markdown table. Headers come from -Columns,
       read as words through Format-ColumnLabel; cells still come from the named properties.
       -Items is intentionally non-mandatory because callers commonly pipe empty arrays
       through ForEach-Object — a null reaching this function is the empty case, not an
       error. #>
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] [object[]]$Items,
        [Parameter(Mandatory = $true)]  [string[]]$Columns,
        [Parameter(Mandatory = $false)] [string]$EmptyMessage = '_None._'
    )
    if (-not $Items -or @($Items).Count -eq 0) { return $EmptyMessage }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('| ' + (@($Columns | ForEach-Object { Format-ColumnLabel $_ }) -join ' | ') + ' |')
    [void]$sb.AppendLine('|' + (($Columns | ForEach-Object { '---' }) -join '|') + '|')
    foreach ($item in $Items) {
        $row = foreach ($col in $Columns) {
            $val = $null
            if ($item -is [hashtable] -and $item.ContainsKey($col)) { $val = $item[$col] }
            elseif ($item.PSObject.Properties.Name -contains $col) { $val = $item.$col }
            $cell = if ($null -eq $val) { '' } else { ([string]$val) -replace '\|','\|' -replace '[\r\n]+',' ' }
            $cell
        }
        [void]$sb.AppendLine('| ' + ($row -join ' | ') + ' |')
    }
    return $sb.ToString().TrimEnd()
}

# Pie slices for a label -> count map, largest first. Past $Limit the rest
# fold into one "Other" slice so the pie still sums to the total; a page that
# folds a tail always carries a table listing every item.
function Format-PieSlices { param([System.Collections.IDictionary]$Counts, [int]$Limit = 0)
    $sorted = @($Counts.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key)
    $shown = if ($Limit -gt 0 -and $sorted.Count -gt $Limit) { @($sorted | Select-Object -First $Limit) } else { $sorted }
    $lines = @($shown | ForEach-Object { "    `"$($_.Key -replace '"', "'")`" : $($_.Value)" })
    if ($shown.Count -lt $sorted.Count) {
        $rest = (@($sorted | Select-Object -Skip $shown.Count) | Measure-Object -Property Value -Sum).Sum
        $lines += "    `"Other ($($sorted.Count - $shown.Count))`" : $rest"
    }
    return ,$lines
}

# Full x-axis labels for a chart whose Mermaid labels are shortened to fit
# under the bars. Mermaid ignores a %% line; ConvertFrom-BlueprintMermaid
# reads it, so the SharePoint chart shows the whole names.
function Format-XyFullLabels { param([string[]]$Labels)
    return '    %% x-labels [' + ((@($Labels) | ForEach-Object { '"' + ([string]$_ -replace '"', "'") + '"' }) -join ', ') + ']'
}

# A purpose-built graphic's data on a Mermaid comment line. Mermaid ignores
# it, so the Markdown export keeps its diagram; ConvertFrom-BlueprintMermaid
# reads the kind and the JSON, and the SharePoint site and the dashboard
# draw the graphic made for that kind instead of the Mermaid.
function Format-VisualLine { param([string]$Kind, $Data)
    return "    %% visual $Kind " + ($Data | ConvertTo-Json -Compress -Depth 8)
}

# Workspace feature-flag boolean → display string. The Sentinel API omits
# these fields when they're at their default value (= False), so a missing
# property must render as "False" not as an empty cell. Otherwise readers
# can't tell "disabled by default" from "report didn't capture this field".
function Format-FeatureFlag {
    param([psobject]$Container, [string]$Property)
    if ($null -eq $Container) { return 'False' }
    if ($Container.PSObject.Properties.Name -notcontains $Property) { return 'False' }
    $val = $Container.$Property
    if ($null -eq $val) { return 'False' }
    return [string]$val
}

# ---------------------------------------------------------------------------
# Section: 00-overview
# ---------------------------------------------------------------------------
$workspace          = Read-Raw 'workspace.json'
$run                = Read-Raw 'run-context.json'
$rules              = Read-RawArray 'alert-rules.json'
$connectors         = Read-RawArray 'data-connectors-classic.json'
$workbooksSaved     = Read-RawArray 'workbooks-saved.json'
$dcrs               = Read-RawArray 'dcrs.json'
$tablesWithData     = Read-RawArray 'tables-with-data.json'
$workspaceTables    = Read-RawArray 'workspace-tables.json'
$watchlists         = Read-RawArray 'watchlists.json'
$autoRules          = Read-RawArray 'automation-rules.json'
$gapFindings        = Read-RawArray 'gap-analysis.json'
# Ids that fired in this run, so the maturity page links only the criterion
# ids that have a finding (and an anchor) on 90-gap-analysis.md.
$script:FiredFindingIds = @{}
foreach ($gf in @($gapFindings)) { if ($gf -and $gf.PSObject.Properties['Id'] -and $gf.Id) { $script:FiredFindingIds[[string]$gf.Id] = $true } }
$cost               = Read-Raw 'cost-estimate.json'

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
            id = [string]$_.Id; severity = [string]$_.Severity; title = [string]$_.Title; category = [string](_RProp $_ 'Category' '')
            evidence = [string](_RProp $_ 'Evidence' ''); remediation = [string](_RProp $_ 'Remediation' ''); learn = [string](_RProp $_ 'Learn' '')
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
$ruleTableRefs     = Read-RawArray 'rule-table-references.json'
$templateTableRefs = Read-RawArray 'template-table-references.json'
# Each template's Content Hub solution; a template only deprecated solutions
# ship (Threat Intelligence, replaced by Threat Intelligence (NEW)) is not
# one to enable, so it counts nowhere a template is offered.
$templateSolutionMap = Get-TemplateSolutionMap -Installed @(Read-RawArray 'content-packages.json') -Catalogue @(Read-RawArray 'content-product-packages.json')
$customDetectionRefs = Read-RawArray 'custom-detection-table-references.json'
$customDetectionsCaptured = Test-Path -LiteralPath (Join-Path $rawRoot 'defender-custom-detections.json')
$customDetectionTableSet = @{}
foreach ($cd in $customDetectionRefs) { if ($cd -and (_RProp $cd 'Enabled' $false) -eq $true) { foreach ($t in @(_RProp $cd 'Tables' @())) { if ($t) { $customDetectionTableSet[[string]$t] = $true } } } }
$ruleEffectiveness = Read-RawArray 'rule-effectiveness.json'
$rulesFired        = Read-RawArray 'rules-fired.json'
$playbookRuns      = Read-RawArray 'playbook-runs.json'
$hunts             = Read-RawArray 'hunts.json'
$bookmarks         = Read-RawArray 'bookmarks.json'
$bookmarkCountDoc  = Read-Raw 'bookmarks-count.json'
$ruleVolumesAll    = Read-RawArray 'analytics-rule-volumes.json'
$customDetectionsRaw = Read-RawArray 'defender-custom-detections.json'
$usageDaily        = Read-RawArray 'workspace-usage-daily.json'
$maturity          = Read-Raw 'maturity.json'
# A Gap criterion whose id is a finding id means that finding fired, so
# the maturity page can link it even when gap-analysis.json is partial.
if ($maturity) {
    foreach ($mArea in @(_RProp $maturity 'areas' @())) {
        foreach ($mCrit in @(_RProp $mArea 'criteria' @())) {
            $mid = [string](_RProp $mCrit 'id' '')
            if ($mid -and (_RProp $mCrit 'status' '') -eq 'Gap' -and $script:FindingIds.ContainsKey($mid)) { $script:FiredFindingIds[$mid] = $true }
        }
    }
}
$incSummary        = Read-RawArray 'incidents-summary.json' | Select-Object -First 1
$incMttr           = Read-RawArray 'incidents-mttr.json'    | Select-Object -First 1
# A failed maturity capture writes '{}', which is truthy, so test for the
# members the page needs rather than for the object.
$maturityOk = ($null -ne $maturity -and $null -ne $maturity.PSObject.Properties['areas'] -and $null -ne $maturity.PSObject.Properties['overall'])

# What the score is based on and what it covers. A maturity.json from an
# older collector carries neither, so fall back to the criteria file.
$maturityBasis = ''
$maturityScope = ''
if ($maturityOk) {
    $maturityBasis = [string](_RProp (_RProp $maturity 'methodology') 'basis' '')
    $maturityScope = [string](_RProp (_RProp $maturity 'methodology') 'scope' '')
    $criteriaFile = Join-Path $ResourcesRoot 'maturity-criteria.json'
    if ((-not $maturityBasis -or -not $maturityScope) -and (Test-Path -LiteralPath $criteriaFile)) {
        $criteriaDoc = Get-Content -LiteralPath $criteriaFile -Raw | ConvertFrom-Json
        if (-not $maturityBasis) { $maturityBasis = [string](_RProp $criteriaDoc.methodology 'basis' '') }
        if (-not $maturityScope) { $maturityScope = [string](_RProp $criteriaDoc.methodology 'scope' '') }
    }
}

# KQL result cells arrive as strings; fixtures carry typed values. Parse
# rather than cast so neither shape throws.
function _RendererNumber {
    param($Value)
    if ($null -eq $Value) { return 0.0 }
    $d = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return 0.0
}
# A KQL dynamic bag (ByClassification and friends) as an ordered name ->
# count map, whether it arrived as JSON text or as an object.
function _RendererBag {
    param($Value)
    $bag = [ordered]@{}
    if ($null -eq $Value) { return $bag }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $bag }
        try { $Value = $Value | ConvertFrom-Json } catch { return $bag }
        if ($null -eq $Value) { return $bag }
    }
    foreach ($prop in $Value.PSObject.Properties) { $bag[$prop.Name] = [long](_RendererNumber $prop.Value) }
    return $bag
}

# Source families -> ingestion -> detection -> alerts -> incidents: the
# numbers behind the estate flow on 00 and 01 and the pipeline table. Null
# safe; every input may be empty.
function New-EstateModel {
    $enabledRefs = @($ruleTableRefs | Where-Object { $_.Enabled -eq $true })
    $referenced = @{}
    foreach ($r in $enabledRefs) { foreach ($t in @($r.Tables)) { if ($t) { $referenced[[string]$t] = $true } } }
    foreach ($t in $customDetectionTableSet.Keys) { $referenced[$t] = $true }
    $byFamily = [ordered]@{}
    $tablesActive = 0; $tablesCovered = 0
    foreach ($t in $tablesWithData) {
        $name = [string]$t.DataType
        if (-not $name) { continue }
        $gb = _RendererNumber $t.BillableLast30d
        if ($gb -le 0) { continue }
        # Seen: data in the lookback. Active (still receiving data): some
        # in the recent window; coverage is counted among the active ones.
        $isActive = (_RendererNumber $t.BillableLast7d) -gt 0
        if ($isActive) { $tablesActive++ }
        $fam = Get-TableFamily -Table $name
        if (-not $byFamily.Contains($fam)) { $byFamily[$fam] = [pscustomobject]@{ Category = $fam; Tables = 0; Gb = 0.0; CoveredGb = 0.0; Covered = 0 } }
        $byFamily[$fam].Tables++
        $byFamily[$fam].Gb += $gb
        if ($referenced.ContainsKey($name)) { if ($isActive) { $tablesCovered++ }; $byFamily[$fam].Covered++; $byFamily[$fam].CoveredGb += $gb }
    }
    $sources = @($byFamily.Values | Sort-Object -Property Gb -Descending)
    $totalGb = 0.0; $coveredGb = 0.0
    foreach ($src in $sources) { $totalGb += $src.Gb; $coveredGb += $src.CoveredGb }
    $ruleAlerts = [long]0
    foreach ($f in $rulesFired) { $ruleAlerts += [long](_RendererNumber $f.Alerts) }
    # Fired, of the enabled Scheduled and NRT rules (by rule id, or by name
    # for an alert without one), as the ring says: a rule disabled or deleted
    # since it fired is not one of them.
    $queryRuleKeys = @{}
    foreach ($r in @($enabledRules | Where-Object { $_.kind -in @('Scheduled', 'NRT') })) {
        $queryRuleKeys[([string](_RProp $r 'name' '')).ToLowerInvariant()] = $true
        $dn = [string](_RProp $r.properties 'displayName' '')
        if ($dn) { $queryRuleKeys["name:$dn"] = $true }
    }
    $firedEnabled = @($rulesFired | Where-Object {
        if (-not $_) { return $false }
        $k = ([string](_RProp $_ 'AlertRuleId' '')).ToLowerInvariant(); if ($k -match '/') { $k = ($k -split '/')[-1] }
        if ($k) { $queryRuleKeys.ContainsKey($k) } else { $queryRuleKeys.ContainsKey("name:$([string](_RProp $_ 'AlertName' ''))") }
    }).Count
    # Every alert from every product, so alerts and incidents count the same
    # things (in a workspace joined to the Defender portal every incident is
    # a Defender XDR one, whichever product raised its alerts); the rules'
    # own alerts when the volumes were not captured.
    $alerts = [long]0
    foreach ($v in @($ruleVolumesAll | Where-Object { $_ })) { $alerts += [long](_RendererNumber (_RProp $v 'Alerts' 0)) }
    if ($alerts -le 0) { $alerts = $ruleAlerts }
    $incidents = if ($incSummary -and $incSummary.PSObject.Properties['Count'])  { [int](_RendererNumber $incSummary.Count) }  else { 0 }
    $closed    = if ($incSummary -and $incSummary.PSObject.Properties['Closed']) { [int](_RendererNumber $incSummary.Closed) } else { 0 }
    # First-party alerts by family: raised inside Defender XDR, Entra ID
    # Protection, Defender for Identity or Defender for Cloud, so they read
    # no workspace table and sit beside the family instead of in coverage.
    $productAgg = [ordered]@{}
    foreach ($v in @($ruleVolumesAll | Where-Object { $_ })) {
        $prod = [string](_RProp $v 'ProductName' '')
        if (-not $prod -or $prod -match 'Sentinel') { continue }
        $famName = Get-ProductFamily -Product $prod
        $key = "$famName|$prod"
        if (-not $productAgg.Contains($key)) { $productAgg[$key] = [pscustomobject]@{ Family = $famName; Product = $prod; Alerts = [long]0; Detections = 0 } }
        $productAgg[$key].Alerts += [long](_RendererNumber (_RProp $v 'Alerts' 0))
        $productAgg[$key].Detections++
    }
    [pscustomobject]@{
        Sources             = $sources
        ProductAlerts       = @($productAgg.Values | Sort-Object { -$_.Alerts })
        CustomDetectionsCaptured = $customDetectionsCaptured
        CustomDetectionsTotal    = @($customDetectionsRaw | Where-Object { $_ }).Count
        CustomDetectionsEnabled  = @($customDetectionRefs | Where-Object { $_ -and (_RProp $_ 'Enabled' $false) -eq $true }).Count
        TablesSeen          = @($tablesWithData | Where-Object { $_ -and (_RendererNumber $_.BillableLast30d) -gt 0 }).Count
        TablesActive        = $tablesActive
        TablesCovered       = $tablesCovered
        TotalGb             = [math]::Round($totalGb, 2)
        CoveredGb           = [math]::Round($coveredGb, 2)
        UncoveredGb         = [math]::Round($totalGb - $coveredGb, 2)
        TemplatesApplicable = @($templateTableRefs | Where-Object { $_.Deprecated -ne $true -and -not (Test-TemplateRetired -Map $templateSolutionMap -TemplateId ([string]$_.TemplateId)) }).Count
        RulesEnabled        = $enabledRules.Count
        RulesQueryEnabled   = @($enabledRules | Where-Object { $_.kind -in @('Scheduled', 'NRT') }).Count
        RulesFired          = $firedEnabled
        Alerts              = $alerts
        RuleAlerts          = $ruleAlerts
        XdrAlerts           = [long](($productAgg.Values | Measure-Object -Property Alerts -Sum).Sum)
        Incidents           = $incidents
        IncidentsClosed     = $closed
        IncidentsOpen       = [math]::Max(0, $incidents - $closed)
    }
}
$estate = New-EstateModel

function Format-EstateFamilyTable {
    # One row per source family: tables, GB, how many of those tables a
    # detection reads, and the first-party alerts raised beside the family.
    param($Estate)
    $alertsByFamily = @{}
    foreach ($p in @($Estate.ProductAlerts)) {
        $fam = [string]$p.Family
        if (-not $alertsByFamily.ContainsKey($fam)) { $alertsByFamily[$fam] = New-Object System.Collections.Generic.List[string] }
        $alertsByFamily[$fam].Add("$($p.Product) $($p.Alerts)")
    }
    $rows = @($Estate.Sources | ForEach-Object {
        $fam = [string]$_.Category
        [pscustomobject]@{
            Family           = $fam
            Tables           = $_.Tables
            Gb30d            = [math]::Round($_.Gb, 2)
            TablesRead       = $_.Covered
            GbRead           = [math]::Round($_.CoveredGb, 2)
            FirstPartyAlerts = $(if ($alertsByFamily.ContainsKey($fam)) { $alertsByFamily[$fam] -join '; ' } else { '' })
        }
    })
    foreach ($fam in @($alertsByFamily.Keys | Sort-Object)) {
        if (-not @($rows | Where-Object { $_.Family -eq $fam }).Count) {
            $rows += [pscustomobject]@{ Family = $fam; Tables = 0; Gb30d = 0; TablesRead = 0; GbRead = 0; FirstPartyAlerts = ($alertsByFamily[$fam] -join '; ') }
        }
    }
    $customLine = if ($Estate.CustomDetectionsCaptured) {
        "**Defender XDR custom detections:** $($Estate.CustomDetectionsEnabled) enabled of $($Estate.CustomDetectionsTotal) defined; the tables they read count as covered above."
    } else {
        '**Defender XDR custom detections:** not captured in this run (the identity needs the Microsoft Graph permission CustomDetection.Read.All), so coverage counts Sentinel rules only.'
    }
@"
### Source families

Each family's share of the last {lookback} of billable data, how many of its tables an enabled Sentinel rule or Defender custom detection reads, and the first-party alerts (Defender XDR, Entra ID Protection, Defender for Identity, Defender for Cloud) raised beside it in the same window. First-party detections run inside their product and read no workspace table, so they never move a table into the covered column.

$(Format-Table -Items $rows -Columns 'Family','Tables','Gb30d','TablesRead','GbRead','FirstPartyAlerts')

$customLine
"@
}

function Format-EstateSankey {
    # sankey-beta reads CSV rows: source,target,value. Labels are quoted so
    # a family name with a comma cannot split a row; values are GB.
    param($Estate)
    function _Gb([double]$v) {
        if ($v -le 0) { return $null }
        return ([math]::Max(0.01, [math]::Round($v, 2))).ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($src in $Estate.Sources) {
        $c = _Gb $src.CoveredGb
        $u = _Gb ($src.Gb - $src.CoveredGb)
        if ($c) { $rows.Add("`"$($src.Category)`",`"Ingestion`",$c") }
        if ($u) { $rows.Add("`"$($src.Category)`",`"Not monitored`",$u") }
    }
    $covered = _Gb $Estate.CoveredGb
    if ($covered) {
        $det = "Detection ($($Estate.RulesEnabled) enabled rules)"
        $al  = "Alerts ($($Estate.Alerts) in {lookback-d})"
        $inc = "Incidents ($($Estate.Incidents) in {lookback-d})"
        $rows.Add("`"Ingestion`",`"$det`",$covered")
        $rows.Add("`"$det`",`"$al`",$covered")
        $rows.Add("`"$al`",`"$inc`",$covered")
        if ($Estate.Incidents -gt 0) {
            $closedShare = [double]$Estate.CoveredGb * $Estate.IncidentsClosed / $Estate.Incidents
            $c2 = _Gb $closedShare
            $o2 = _Gb ($Estate.CoveredGb - $closedShare)
            if ($c2) { $rows.Add("`"$inc`",`"Closed ($($Estate.IncidentsClosed))`",$c2") }
            if ($o2) { $rows.Add("`"$inc`",`"Open ($($Estate.IncidentsOpen))`",$o2") }
        }
    }
    if ($rows.Count -eq 0) { return '_Nothing to draw._' }
    $height = [math]::Max(360, 40 * $Estate.Sources.Count + 200)
    # The estate as data for the SharePoint graphic: every family's GB and
    # the part a detection reads, and the four stages as in use of a whole.
    # Counts with thousands separators, whatever the machine's culture.
    $n0 = { param($v) ([long]$v).ToString('N0', [System.Globalization.CultureInfo]::InvariantCulture) }
    $visual = Format-VisualLine -Kind 'estate' -Data ([ordered]@{
        windowDays = (Get-BpWindow).Days
        totalGb   = [math]::Round([double]$Estate.TotalGb, 2)
        coveredGb = [math]::Round([double]$Estate.CoveredGb, 2)
        sources   = @($Estate.Sources | Sort-Object { -[double]$_.Gb } | ForEach-Object { [ordered]@{ name = [string]$_.Category; gb = [math]::Round([double]$_.Gb, 2); coveredGb = [math]::Round([double]$_.CoveredGb, 2); tables = [int]$_.Tables; covered = [int]$_.Covered } })
        stages    = @(
            [ordered]@{ name = 'Ingestion'; value = [int]$Estate.TablesActive; of = [int]$Estate.TablesSeen; label = 'tables with data in {lookback} still receiving data in the last {recent}'; detail = "$([math]::Round([double]$Estate.TotalGb, 1)) GB in {lookback}" }
            [ordered]@{ name = 'Detection'; value = [int]$Estate.TablesCovered; of = [int]$Estate.TablesActive; label = 'active tables read by an enabled detection'; detail = "$(& $n0 $Estate.RulesEnabled) enabled rules" }
            [ordered]@{ name = 'Alerts'; value = [int]$Estate.RulesFired; of = [int]$Estate.RulesQueryEnabled; label = 'scheduled and NRT rules that fired'; detail = "$(& $n0 $Estate.RuleAlerts) Sentinel alerts$(if ([long]$Estate.XdrAlerts -gt 0) { " and $(& $n0 $Estate.XdrAlerts) Defender XDR alerts" }) in {lookback}" }
            [ordered]@{ name = 'Incidents'; value = [int]$Estate.IncidentsClosed; of = [int]$Estate.Incidents; label = 'incidents closed'; detail = "$(& $n0 $Estate.IncidentsOpen) still open" }
        )
    })
    @"
``````mermaid
---
config:
  sankey:
    showValues: true
    width: 1200
    height: $height
---
sankey-beta
$visual

$($rows -join [Environment]::NewLine)
``````
"@
}

function Format-EstateRingsTable {
    # The four pipeline stages as in-use / of / share, with a rating so the
    # reader does not have to do the division: 80%+ strong, 65%+ fair.
    param($Estate)
    function _Row([string]$Stage, [int]$Value, [int]$Of) {
        if ($Of -le 0) { return "| $Stage | $Value | $Of | _n/a_ | _n/a_ |" }
        $pct = [int][math]::Round(100.0 * $Value / $Of, 0)
        $badge = if ($pct -ge 80) { 'Strong' } elseif ($pct -ge 65) { 'Fair' } else { 'Weak' }
        return "| $Stage | $Value | $Of | $pct% | $badge |"
    }
    @"
| Stage | In use | Of | Share | Rating |
|---|---:|---:|---:|---|
$(_Row 'Ingestion: tables still receiving data ({recent-d}, of those with data in {lookback-d})' $Estate.TablesActive $Estate.TablesSeen)
$(_Row 'Detection: active tables read by at least one enabled rule' $Estate.TablesCovered $Estate.TablesActive)
$(_Row 'Alerts: enabled Scheduled/NRT rules that fired in {lookback-d}' $Estate.RulesFired $Estate.RulesQueryEnabled)
$(_Row 'Incidents: closed, of those created in {lookback-d}' $Estate.IncidentsClosed $Estate.Incidents)
"@
}

$estateBlock = if ($estate.Sources.Count -gt 0 -and $estate.TotalGb -gt 0) {
@"

## Estate flow

Where the last {lookback} of billable data came from, how much of it an enabled analytics rule reads, and what the detections produced.

$(Format-EstateSankey -Estate $estate)

<!-- bp:shown-in-graphic -->

$(Format-EstateRingsTable -Estate $estate)

$(Format-EstateFamilyTable -Estate $estate)

GB that reaches **Not monitored** is ingested and billed but read by no enabled Sentinel analytics rule; detections that run inside Defender XDR, Entra ID Protection, Defender for Identity or Defender for Cloud do not read workspace tables and are not counted here. [28-detection-opportunities.md](28-detection-opportunities.md) lists those tables with the templates that would cover them.
"@
} else {
    # No billable ingestion, so no ribbons to draw; first-party alerts and
    # the custom-detection count still belong here when they exist.
    $familyTail = if (@($estate.ProductAlerts).Count -gt 0 -or $estate.CustomDetectionsCaptured) { "`n`n" + (Format-EstateFamilyTable -Estate $estate) } else { '' }
@"

## Estate flow

_No billable ingestion in the last {lookback}, so there is no flow to draw._$familyTail
"@
}

$maturityHeadline = if ($maturityOk -and $null -ne $maturity.overall.score) {
    "**Maturity:** $($maturity.overall.score) / 5 ($($maturity.overall.levelName))  ·  **Target:** $($maturity.targetLevel) ($($maturity.targetLevelName))  ·  **Areas below target:** $(@($maturity.areasBelowTarget).Count) of $(@($maturity.areas).Count)  ·  **Quick wins:** $(@($maturity.quickWins).Count)`n`nScored from the Sentinel workspace only: people and processes were not assessed. Detail in [91-maturity-assessment.md](91-maturity-assessment.md)."
} elseif ($maturityOk) {
    "_Maturity not assessed: no criterion could be evaluated in this run._ See [91-maturity-assessment.md](91-maturity-assessment.md)."
} else { '_Maturity assessment not available for this run._' }
$maturityCell = if ($maturityOk -and $null -ne $maturity.overall.score) {
    "$($maturity.overall.score) / $($maturity.targetLevel) ($($maturity.overall.levelName), target $($maturity.targetLevelName))"
} else { '_not assessed_' }

$usageTrendBlock = if ($usageDaily.Count -ge 2) {
    $pts = @($usageDaily | Sort-Object { [datetime]$_.Day })
    # Day labels read "13 Sep", not "09-13".
    $labels = ($pts | ForEach-Object { "`"$(([datetime]$_.Day).ToUniversalTime().ToString('d MMM', [System.Globalization.CultureInfo]::InvariantCulture))`"" }) -join ', '
    $bill = ($pts | ForEach-Object { [math]::Round((_RendererNumber $_.BillableGB), 2) }) -join ', '
    $free = ($pts | ForEach-Object { [math]::Round((_RendererNumber $_.FreeGB), 2) }) -join ', '
    $max = 1.0
    foreach ($pt in $pts) { $v = (_RendererNumber $pt.BillableGB) + (_RendererNumber $pt.FreeGB); if ($v -gt $max) { $max = $v } }
@"

### Daily ingestion (last {lookback})

``````mermaid
---
config:
  xyChart:
    width: 1400
    height: 420
---
xychart-beta
    title "Daily ingestion, GB (billable and free)"
    x-axis [$labels]
    y-axis "GB" 0 --> $([math]::Ceiling($max * 1.1) + 1)
    line "Billable" [$bill]
    line "Free" [$free]
``````

Billable GB per day, and free GB (the Sentinel benefit and other non-billable data), from ``Usage``. A step up that no connector change explains is the usual first sign of a runaway source.
"@
} else { '' }

# Rule ↔ watchlist cross-reference. Scans every rule's KQL query for
# `_GetWatchlist("alias")` calls (the canonical helper). The output is
# two hashtables consumed by sections 20 and 50:
#   $rulesByWatchlistAlias   alias  -> @(rule display names)
#   $watchlistsByRuleId      ruleId -> @(aliases)
# Both quote styles and a forgiving whitespace pattern are accepted —
# matches `_GetWatchlist("X")`, `_GetWatchlist('X')`, and `_GetWatchlist
# (  "X"  )` with case-insensitive function-name match.
$rulesByWatchlistAlias = @{}
$watchlistsByRuleId    = @{}
$rxWatchlistRef = [regex]::new("_GetWatchlist\s*\(\s*['""]([^'""]+)['""]\s*\)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
foreach ($r in $rules) {
    $q = $r.properties.query
    if (-not $q) { continue }
    $matches = $rxWatchlistRef.Matches([string]$q)
    if ($matches.Count -eq 0) { continue }
    $ruleName = $r.properties.displayName
    $ruleId   = $r.name
    $aliases  = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in $matches) { [void]$aliases.Add($m.Groups[1].Value) }
    $watchlistsByRuleId[$ruleId] = @($aliases)
    foreach ($a in $aliases) {
        if (-not $rulesByWatchlistAlias.ContainsKey($a)) { $rulesByWatchlistAlias[$a] = New-Object System.Collections.Generic.List[string] }
        [void]$rulesByWatchlistAlias[$a].Add($ruleName)
    }
}

# Severity + category counters hoisted up here (was computed twice further
# down at the gap-analysis and live-snapshot section blocks). Single
# computation drives the Mermaid pie/bar charts in 00, 01 and 90.
$gapBySeverity = @{ Critical = 0; Warning = 0; Info = 0 }
$gapByCategory = @{}
foreach ($f in $gapFindings) {
    if ($gapBySeverity.ContainsKey($f.Severity)) { $gapBySeverity[$f.Severity]++ }
    $cat = if ($f.Category) { [string]$f.Category } else { 'Other' }
    if (-not $gapByCategory.ContainsKey($cat)) { $gapByCategory[$cat] = @{ Warning = 0; Info = 0; Critical = 0 } }
    if ($gapByCategory[$cat].ContainsKey($f.Severity)) { $gapByCategory[$cat][$f.Severity]++ }
}

$overviewBody = @"
$(Format-Banner -Title "SIEM Overview")

## Findings at a glance

``````mermaid
pie showData title Open findings by severity
    "Critical" : $($gapBySeverity.Critical)
    "Warning"  : $($gapBySeverity.Warning)
    "Info"     : $($gapBySeverity.Info)
``````

$($gapFindings.Count) open findings against the best-practice catalogue. Drill into [90-gap-analysis.md](90-gap-analysis.md) for the per-category breakdown.

## Headline

| | |
|---|---|
| Workspace ID | ``$($workspace.properties.customerId)`` |
| Region | ``$($workspace.location)`` |
| SKU | ``$($workspace.properties.sku.name)`` |
| Default retention | $($workspace.properties.retentionInDays) days |
| Daily cap | $(if ($workspace.properties.workspaceCapping.dailyQuotaGb -eq -1) { 'Unlimited' } else { "$($workspace.properties.workspaceCapping.dailyQuotaGb) GB" }) |
| Replication | $(if ($workspace.properties.replication.enabled) { 'Enabled' } else { 'Disabled' }) |
| Public network access (ingestion) | ``$($workspace.properties.publicNetworkAccessForIngestion)`` |
| Public network access (query) | ``$($workspace.properties.publicNetworkAccessForQuery)`` |

## Counts

| Artefact | Count |
|---|---:|
| Data connectors | $($connectors.Count) |
| Analytics rules | $($rules.Count) (enabled: $($enabledRules.Count)) |
| Automation rules | $($autoRules.Count) |
| Watchlists | $($watchlists.Count) |
| Workbooks | $($workbooksSaved.Count) |
| Data Collection Rules | $($dcrs.Count) |
| Tables operational (populated + custom logs) | $($operationalTables.Count) |
| Tables receiving data ({lookback-d}) | $($populatedTables.Count) |
| Catalogue-only Microsoft schemas (never ingested) | $catalogueOnlyCount |
$estateBlock

## Maturity

$maturityHeadline

## Estimated monthly cost

$(if ($cost) {
"**$($cost.MonthlyTotal) $($cost.Currency)** for the workspace, computed from the last {lookback} of `Usage` against the Azure Retail Prices API on $(Format-DateUtc $cost.AsOfUtc). See [84-cost-estimate.md](84-cost-estimate.md) for breakdown and methodology."
} else { '_Cost estimate not available._' })

## Top findings

$(if ($top5Findings.Count -gt 0) { "The $($top5Findings.Count) most severe of $($gapFindings.Count) finding(s), each with what was found and how to fix it; [90-gap-analysis.md](90-gap-analysis.md) lists every one.`n`n$topFindingsVisual`n`n<!-- bp:shown-in-graphic -->`n`n" })$(if ($top5Findings.Count -gt 0) {
($top5Findings | ForEach-Object {
    "- **$($_.Severity)** [$($_.Id)] $($_.Title) - $($_.Evidence) [Learn]($($_.Learn))"
}) -join [Environment]::NewLine
} else { '_No findings: a clean run._' })

The deep-dive sections: [data connectors](10-data-connectors.md), [analytics rules](20-analytics-rules.md), [MITRE coverage](25-mitre-coverage.md), [detection opportunities](28-detection-opportunities.md), [workbooks](40-workbooks.md), [workspace](80-workspace.md), [table plans + retention](81-table-plans-retention.md), [data collection](83-data-collection.md), [cost estimate](84-cost-estimate.md), [access control (RBAC)](85-rbac.md), [gap analysis](90-gap-analysis.md), [maturity assessment](91-maturity-assessment.md).
"@

Write-Section '00-overview.md' $overviewBody

# ---------------------------------------------------------------------------
# Section: 10-data-connectors
# ---------------------------------------------------------------------------
# Classic connector resources are named by GUID and store per-data-type state
# under properties.dataTypes.<typename>.state. The earlier rendering pulled
# Name=$_.name (GUID) and State=$_.properties.connectorUiConfig.connectivityCriterias
# — a CCF field that doesn't exist on the classic schema, so State was always
# blank. The fix below maps Kind to a friendly Title, aggregates per-data-type
# state into a single overall state column, and lists the data-type names in
# their own column.
function Get-ConnectorFriendlyTitle {
    param([string]$Kind, [psobject]$Connector, [hashtable]$CcfTitleByName = @{})
    switch ($Kind) {
        'AzureActiveDirectory'                         { 'Microsoft Entra ID' }
        'MicrosoftCloudAppSecurity'                    { 'Microsoft Defender for Cloud Apps' }
        'MicrosoftDefenderAdvancedThreatProtection'    { 'Microsoft Defender for Endpoint' }
        'MicrosoftPurviewInformationProtection'        { 'Microsoft Purview Information Protection' }
        'MicrosoftThreatIntelligence'                  { 'Microsoft Defender Threat Intelligence' }
        'MicrosoftThreatProtection'                    { 'Microsoft Defender XDR' }
        'Office365'                                    { 'Microsoft 365 (Office 365)' }
        'AzureSecurityCenter'                          { 'Microsoft Defender for Cloud' }
        'GenericUI'                                    { if ($Connector.properties.connectorUiConfig.title) { $Connector.properties.connectorUiConfig.title } else { $Kind } }
        'StaticUI'                                     { if ($Connector.properties.connectorUiConfig.title) { $Connector.properties.connectorUiConfig.title } else { $Kind } }
        { $_ -in 'RestApiPoller','Push' }              {
            # CCF-derived kinds. Each connector instance carries a
            # connectorDefinitionName that points at the matching CCF
            # definition entry, where the human-readable title lives.
            $defName = $Connector.properties.connectorDefinitionName
            if ($defName -and $CcfTitleByName.ContainsKey($defName)) {
                "$($CcfTitleByName[$defName])  ($Kind)"
            } elseif ($defName) {
                "$defName  ($Kind)"
            } else {
                $Kind
            }
        }
        default                                        { $Kind }
    }
}

function Get-ConnectorAggregateState {
    param([psobject]$Connector)
    # RestApiPoller / Push connectors don't carry a dataTypes map. Treat the
    # presence of a dataType + dcrConfig as 'enabled' for that kind.
    if ($Connector.kind -in @('RestApiPoller','Push')) {
        $hasDataType = $Connector.properties.PSObject.Properties.Name -contains 'dataType' -and $Connector.properties.dataType
        $hasDcr = $Connector.properties.PSObject.Properties.Name -contains 'dcrConfig' -and $Connector.properties.dcrConfig
        if ($hasDataType -and $hasDcr) { return 'enabled' }
        if ($hasDataType -or $hasDcr) { return 'partial' }
        return 'unknown'
    }
    $dataTypes = $Connector.properties.dataTypes
    if ($null -eq $dataTypes) { return 'unknown' }
    $names = @($dataTypes.PSObject.Properties.Name)
    if ($names.Count -eq 0) { return 'unknown' }
    $states = foreach ($n in $names) {
        $s = $dataTypes.$n.state
        if ($s) { $s.ToLowerInvariant() } else { 'unknown' }
    }
    $enabled  = @($states | Where-Object { $_ -eq 'enabled' }).Count
    $disabled = @($states | Where-Object { $_ -eq 'disabled' }).Count
    if ($enabled -eq $states.Count) { 'enabled' }
    elseif ($disabled -eq $states.Count) { 'disabled' }
    elseif ($enabled -gt 0) { 'partial' }
    else { 'unknown' }
}

function Get-ConnectorDataTypes {
    param([psobject]$Connector)
    # RestApiPoller / Push schema: single string at properties.dataType.
    if ($Connector.kind -in @('RestApiPoller','Push')) {
        if ($Connector.properties.PSObject.Properties.Name -contains 'dataType' -and $Connector.properties.dataType) {
            return [string]$Connector.properties.dataType
        }
        return ''
    }
    $dataTypes = $Connector.properties.dataTypes
    if ($null -eq $dataTypes) { return '' }
    @($dataTypes.PSObject.Properties.Name) -join ', '
}

function Get-ConnectorTargetTable {
    # Map (Kind, dataType) -> Log Analytics table the connector writes to.
    # Returns $null when no known mapping exists; the renderer then leaves the
    # activity columns blank for that data type rather than guessing wrong.
    param([string]$Kind, [string]$DataType)
    $dt = if ($DataType) { $DataType.ToLowerInvariant() } else { '' }
    switch ("$Kind/$dt") {
        'Office365/sharepoint'                                   { 'OfficeActivity' }
        'Office365/exchange'                                     { 'OfficeActivity' }
        'Office365/teams'                                        { 'OfficeActivity' }
        'AzureActiveDirectory/signinlogs'                        { 'SigninLogs' }
        'AzureActiveDirectory/auditlogs'                         { 'AuditLogs' }
        'AzureActiveDirectory/noninteractiveusersigninlogs'      { 'AADNonInteractiveUserSignInLogs' }
        'MicrosoftCloudAppSecurity/alerts'                       { 'SecurityAlert' }
        'MicrosoftCloudAppSecurity/discoverylogs'                { 'McasShadowItReporting' }
        'MicrosoftDefenderAdvancedThreatProtection/alerts'       { 'SecurityAlert' }
        'MicrosoftThreatProtection/alerts'                       { 'SecurityAlert' }
        'MicrosoftThreatProtection/incidents'                    { 'SecurityIncident' }
        'MicrosoftThreatIntelligence/microsoftemergingthreatfeed' { 'ThreatIntelligenceIndicator' }
        'MicrosoftPurviewInformationProtection/logs'             { 'InformationProtectionLogs_CL' }
        'AzureSecurityCenter/alerts'                             { 'SecurityAlert' }
        default                                                  { $null }
    }
}

$ccfDefs = Read-RawArray 'data-connector-definitions.json'

# Index CCF definitions by name so RestApiPoller / Push connectors can look up
# their human-readable title via the `connectorDefinitionName` field.
$ccfTitleByName = @{}
foreach ($d in $ccfDefs) {
    if ($d.name -and $d.properties.connectorUiConfig.title) {
        $ccfTitleByName[$d.name] = $d.properties.connectorUiConfig.title
    }
}

# Pre-index tables-with-data by name so the connector rows can join on it
# without rebuilding the lookup once per row.
$tablesByNameForConnectors = @{}
foreach ($t in $tablesWithData) {
    if ($t.DataType) { $tablesByNameForConnectors[$t.DataType] = $t }
}
function Get-ConnectorData7d {
    param([psobject]$Connector)
    # RestApiPoller / Push connectors write to a single table at
    # properties.dataType. The table name itself is the join key — no
    # data-type-to-table mapping is needed.
    if ($Connector.kind -in @('RestApiPoller','Push')) {
        $tbl = $Connector.properties.dataType
        if (-not $tbl) { return '' }
        if ($tablesByNameForConnectors.ContainsKey($tbl)) {
            $row = $tablesByNameForConnectors[$tbl]
            $bill7d = if ($null -ne $row.BillableLast7d) { [double]$row.BillableLast7d } else { 0 }
            if ($bill7d -gt 0) { return 'Yes' }
        }
        return 'No'
    }
    $dataTypes = $Connector.properties.dataTypes
    if ($null -eq $dataTypes) { return '' }
    $anyData = $false
    foreach ($dtName in @($dataTypes.PSObject.Properties.Name)) {
        $table = Get-ConnectorTargetTable -Kind $Connector.kind -DataType $dtName
        if (-not $table) { continue }
        if ($tablesByNameForConnectors.ContainsKey($table)) {
            $row = $tablesByNameForConnectors[$table]
            $bill7d = if ($null -ne $row.BillableLast7d) { [double]$row.BillableLast7d } else { 0 }
            if ($bill7d -gt 0) { $anyData = $true; break }
        }
    }
    if ($anyData) { 'Yes' } else { 'No' }
}

$connectorRows = $connectors | ForEach-Object {
    [pscustomobject]@{
        Title     = Get-ConnectorFriendlyTitle -Kind $_.kind -Connector $_ -CcfTitleByName $ccfTitleByName
        Kind      = $_.kind
        DataTypes = Get-ConnectorDataTypes -Connector $_
        State     = Get-ConnectorAggregateState -Connector $_
        Data7d    = Get-ConnectorData7d -Connector $_
    }
}

$ccfRows = $ccfDefs | ForEach-Object {
    [pscustomobject]@{
        Name      = $_.name
        Title     = $_.properties.connectorUiConfig.title
        Publisher = $_.properties.connectorUiConfig.publisher
    }
}

# Build a per-connector / per-data-type activity table by joining each
# connector's data types to the corresponding workspace table via
# Get-ConnectorTargetTable, then looking up the table's last-ingested
# timestamp and 24h billable volume from tables-with-data.json. Rows where
# we can't map a data type to a known table are still listed (operators
# can recognise the mapping gap) with blank activity columns.
$tablesByName = @{}
foreach ($t in $tablesWithData) {
    if ($t.DataType) { $tablesByName[$t.DataType] = $t }
}

$healthRows = foreach ($c in $connectors) {
    $kind = $c.kind
    $title = Get-ConnectorFriendlyTitle -Kind $kind -Connector $c
    $dataTypes = $c.properties.dataTypes
    if ($null -eq $dataTypes) { continue }
    foreach ($dtName in @($dataTypes.PSObject.Properties.Name)) {
        $table = Get-ConnectorTargetTable -Kind $kind -DataType $dtName
        $lastIngested = ''
        $last24h = ''
        if ($table -and $tablesByName.ContainsKey($table)) {
            $row = $tablesByName[$table]
            if ($row.LastIngested) { $lastIngested = Format-DateUtc $row.LastIngested }
            if ($null -ne $row.BillableLast24h) { $last24h = Format-Gb $row.BillableLast24h }
        }
        [pscustomobject]@{
            Connector    = $title
            DataType     = $dtName
            Table        = if ($table) { $table } else { '_(no mapping)_' }
            LastIngested = $lastIngested
            BillableLast24hGB = $last24h
        }
    }
}

# Build the synthesised effective-connectors view. Covers DCR-driven and
# diagnostic-settings-driven ingestion which the Sentinel data-connectors
# endpoint doesn't enumerate. See Get-EffectiveConnectors for the precedence
# rules.
$diagSettings = Read-RawArray 'diagnostic-settings.json'
$workspaceResourceId = if ($workspace.id) { [string]$workspace.id } else { '' }
$effective = Get-EffectiveConnectors `
    -ClassicConnectors   $connectors `
    -CcfDefinitions      $ccfDefs `
    -Dcrs                $dcrs `
    -DiagnosticSettings  $diagSettings `
    -TablesWithData      $tablesWithData `
    -WorkspaceResourceId $workspaceResourceId

# The connector catalogue: every Sentinel data connector and the tables it
# writes. Each connector in the workspace is matched against it, and each
# table in the effective view is credited to the connector the catalogue
# names for it.
$connectorCatalogue = Import-ConnectorCatalogue -Path (Join-Path $ResourcesRoot 'connector-catalogue.json')
$tableActivity7d = Get-TableActivity -TablesWithData @($tablesWithData)
$connectedConnectorIds = @($connectors | Where-Object { $_ } | ForEach-Object { Get-WorkspaceConnectorId -Connector $_ } | Where-Object { $_ })
$catalogueStatus = if ($connectorCatalogue) { @(Get-ConnectorCatalogueStatus -Catalogue $connectorCatalogue -Connectors @($connectors) -Activity $tableActivity7d) } else { @() }
$catalogueStatusOrder = @{ 'Silent' = 0; 'Receiving data' = 1; 'No tables in the catalogue' = 2; 'Not in the catalogue' = 3 }
$catalogueRows = @($catalogueStatus | Sort-Object @{ Expression = { $catalogueStatusOrder[$_.Status] } }, Connector | ForEach-Object {
    [pscustomobject]@{
        Connector      = $_.Connector
        Solution       = $_.Solution
        Status         = $(if ($_.Deprecated) { "$($_.Status), deprecated connector" } else { $_.Status })
        TablesWithData = ($_.WithData -join ', ')
        QuietTables    = ($_.Quiet -join ', ')
    }
})
$effectiveRows = @($effective | Where-Object { $_ } | ForEach-Object {
    # A classic connector's row names its connector in the identifier.
    $ownId = if ([string]$_.Source -eq 'Classic') { ([string]$_.Identifier -split '/')[0] } else { '' }
    $label = if ($connectorCatalogue -and $_.Table) { Get-TableConnectorLabel -Catalogue $connectorCatalogue -Table ([string]$_.Table) -ConnectedIds $connectedConnectorIds -ConnectorId $ownId } else { '' }
    $_ | Select-Object *, @{ Name = 'CatalogueConnector'; Expression = { $label } }
})
$catalogueBlock = if (-not $connectorCatalogue) {
    '_The connector catalogue (``Private/Resources/connector-catalogue.json``) is missing from this Blueprint build._'
} else {
    Format-Table -Items $catalogueRows -Columns 'Connector','Solution','Status','TablesWithData','QuietTables' -EmptyMessage (Get-EmptyMessage 'data-connectors-classic.json' '_No data connectors in the workspace._')
}

# Connector-kind distribution for the headline pie. Excludes CCF defs
# (counted separately) since they're not deployed instances per se.
$kindCounts = @{}
foreach ($c in $connectors) {
    $k = if ($c.kind) { [string]$c.kind } else { 'unknown' }
    if (-not $kindCounts.ContainsKey($k)) { $kindCounts[$k] = 0 }
    $kindCounts[$k]++
}
$kindPieRows = $kindCounts.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}

# Defender XDR unification and Defender for Cloud: read from the classic
# connector list, the XDR table presence capture, the rules and the
# workspace. Defender-portal onboarding itself is not observable from the
# workspace API, so the table says so rather than guessing.
$mtpConnector = @($connectors | Where-Object { $_ -and (_RProp $_ 'kind') -eq 'MicrosoftThreatProtection' }) | Select-Object -First 1
$mtpTypes = _RProp (_RProp $mtpConnector 'properties') 'dataTypes'
$mtpState = { param($name) $dt = _RProp $mtpTypes $name; if ($dt) { [string](_RProp $dt 'state' 'unknown') } else { 'not configured' } }
$xdrPresenceRows = @(Read-RawArray 'xdr-table-presence.json' | Where-Object { $_ })
$xdrActive = @($xdrPresenceRows | Where-Object { (_RendererNumber (_RProp $_ 'RecordCount' 0)) -gt 0 }).Count
$legacyIncidentRulesEnabled = @($rules | Where-Object { $_ -and $_.kind -eq 'MicrosoftSecurityIncidentCreation' -and (_RProp (_RProp $_ 'properties') 'enabled' $false) }).Count
$mdcSubscription = @($connectors | Where-Object { $_ -and (_RProp $_ 'kind') -eq 'AzureSecurityCenter' }).Count
$mdcTenant = @($connectors | Where-Object { $_ -and (_RProp $_ 'kind') -eq 'MicrosoftDefenderForCloudTenantBased' }).Count
$unifiedBillingFlag = [bool](_RProp (_RProp (_RProp $workspace 'properties') 'features') 'unifiedSentinelBillingOnly' $false)
$onboardingRow = @(Read-RawArray 'onboarding-state.json' | Where-Object { $_ }) | Select-Object -First 1
# What actually flows: incidents created through the unified queue, Defender
# XDR alerts in SecurityAlert, and alerts still labelled with the retired
# Azure Security Center product name.
$unifiedIncidents = if ($incSummary -and $incSummary.PSObject.Properties['Unified7d']) {
    "$([int](_RendererNumber $incSummary.Unified7d)) of $([int](_RendererNumber (_RProp $incSummary 'Count7d' 0)))"
} else { 'Not captured' }
$alertVolumes10 = @(Read-RawArray 'analytics-rule-volumes.json' | Where-Object { $_ })
$xdrAlerts30d = [long](@($alertVolumes10 | Where-Object { [string]$_.ProductName -match 'Microsoft 365 Defender|Microsoft Defender XDR' } | ForEach-Object { _RendererNumber $_.Alerts }) | Measure-Object -Sum).Sum
$ascAlerts30d = [long](@($alertVolumes10 | Where-Object { [string]$_.ProductName -eq 'Azure Security Center' } | ForEach-Object { _RendererNumber $_.Alerts }) | Measure-Object -Sum).Sum
$unificationRows = @(
    [pscustomobject]@{ Check = 'Defender XDR connector (MicrosoftThreatProtection)'; Value = $(if ($mtpConnector) { 'Present' } else { 'Not configured' }); Meaning = 'Brings XDR incidents and alerts into the workspace; without it Sentinel and Defender run separate queues' }
    [pscustomobject]@{ Check = 'XDR incidents data type'; Value = (& $mtpState 'incidents'); Meaning = 'Enabled means Defender incidents (and their alerts) are synchronised, the unified-queue path' }
    [pscustomobject]@{ Check = 'XDR alerts data type'; Value = (& $mtpState 'alerts'); Meaning = 'Enabled means raw XDR alerts also land in SecurityAlert' }
    [pscustomobject]@{ Check = 'XDR advanced-hunting tables with data ({lookback-d})'; Value = "$xdrActive of $($xdrPresenceRows.Count) checked"; Meaning = 'Device, Email, Identity and CloudApp tables streaming into the workspace; see 14-coverage-breakdowns.md' }
    [pscustomobject]@{ Check = 'Incidents raised through Defender XDR ({recent-d})'; Value = $unifiedIncidents; Meaning = 'Incidents whose provider is Microsoft XDR (or Microsoft 365 Defender), against all incidents updated in the window; see 15-incidents.md' }
    [pscustomobject]@{ Check = 'Defender XDR alerts in SecurityAlert ({lookback-d})'; Value = $xdrAlerts30d; Meaning = 'Alerts whose product is Microsoft 365 Defender or Microsoft Defender XDR; zero with the connector present means the alerts data type is off' }
    [pscustomobject]@{ Check = 'Alerts under the retired Azure Security Center name ({lookback-d})'; Value = $ascAlerts30d; Meaning = 'Non-zero means the legacy Azure Security Center connector path is still feeding alerts; Defender for Cloud replaces it' }
    [pscustomobject]@{ Check = 'Legacy Microsoft incident-creation rules enabled'; Value = $legacyIncidentRulesEnabled; Meaning = 'The pre-unification way of promoting Defender alerts; with the incidents data type enabled they duplicate work ([SAC-DET-08])' }
    [pscustomobject]@{ Check = 'Unified Sentinel and Defender billing'; Value = $(if ($unifiedBillingFlag) { 'true' } else { 'false / absent' }); Meaning = 'features.unifiedSentinelBillingOnly on the workspace, set once the workspace is on the unified billing model' }
    [pscustomobject]@{ Check = 'Sentinel onboarding state resource'; Value = $(if ($onboardingRow) { 'Present' } else { 'Not captured' }); Meaning = 'Microsoft.SecurityInsights/onboardingStates/default exists on every Sentinel-enabled workspace; it does not prove Defender-portal onboarding' }
    [pscustomobject]@{ Check = 'Defender portal onboarding'; Value = 'Not observable'; Meaning = 'No workspace-scope API reports it; confirm under Defender portal, System, Settings, Microsoft Sentinel' }
    [pscustomobject]@{ Check = 'Defender for Cloud connector (subscription level)'; Value = $(if ($mdcSubscription -gt 0) { "Configured ($mdcSubscription)" } else { 'Not configured' }); Meaning = 'AzureSecurityCenter connector per subscription' }
    [pscustomobject]@{ Check = 'Defender for Cloud connector (tenant level)'; Value = $(if ($mdcTenant -gt 0) { 'Configured' } else { 'Not configured' }); Meaning = 'MicrosoftDefenderForCloudTenantBased connector, the newer tenant-wide path' }
)
$connectorBody = @"
$(Format-Banner -Title "Data Connectors")

## Connector mix

``````mermaid
pie showData title Connectors by kind
$($kindPieRows -join [Environment]::NewLine)
``````

$($connectors.Count) connector(s) deployed across $($kindCounts.Count) distinct kinds.

## Classic connectors

$(Format-Table -Items $connectorRows -Columns 'Title','Kind','DataTypes','State','Data7d')

## Codeless Connector Framework definitions

$(Format-Table -Items $ccfRows -Columns 'Name','Title','Publisher')

## Effective connectors (synthesised view)

Modern Sentinel workspaces ingest most of their data through DCRs and diagnostic settings that don't register against the Sentinel ``dataConnectors`` endpoint. This table fuses every ingestion source the captured inventory can attribute, with precedence rules to avoid double-counting:

1. **Classic**: a classic data-connector explicitly covers the target table.
2. **CCF**: a Codeless Connector Framework definition. Listed by name; table claim depends on connector implementation.
3. **DCR**: derived from each data flow's ``outputStream`` (Microsoft-/Custom- prefixes stripped). Skipped when the table is already classic-claimed.
4. **Diagnostic**: derived from enabled diagnostic-setting log categories. Skipped when already claimed.
5. **Active-table**: a remaining table receiving billable data (>0 GB in the last 24h) that no captured ingestion mechanism explains. Surfaces as a visibility signal.

See ``Docs/Modules/iSOCBlueprint/Sentinel-Blueprint.md`` for the design note.

**Catalogue connector** is the data connector the connector catalogue credits with the table: the row's own connector for a classic connector, otherwise the connectors that list the table when there are at most three (marked when connected), otherwise how many connectors share it.

$(Format-Table -Items $effectiveRows -Columns 'Source','Identifier','Table','CatalogueConnector','Last24hGB','LastIngested')

## Connected connectors against the catalogue

Each data connector in the workspace matched to the connector catalogue: the Content Hub data connectors and the tables each one writes, taken from the Azure-Sentinel repository (catalogue of $(if ($connectorCatalogue) { $connectorCatalogue.Version } else { 'n/a' })). **Silent** means none of the tables the catalogue lists for the connector received data in the last {recent}, free tables included ([SAC-PLT-10]). The catalogue takes a connector's tables from the connector's own mapping where Microsoft publishes one, otherwise from every table its solution's content reads, so a quiet table in the list is not always one the connector writes; a connector with data in any of its tables counts as receiving data.

$catalogueBlock

## Connector health (24h activity)

Last ingested and 24-hour billable volume per **classic** data-connector's data type, joined against the workspace ``Usage`` summary. Rows with a blank Table column have no known data-type-to-table mapping in the renderer; cross-reference [83-data-collection.md](83-data-collection.md) for DCRs and [81-table-plans-retention.md](81-table-plans-retention.md) for the full per-table view.

$(Format-Table -Items $healthRows -Columns 'Connector','DataType','Table','LastIngested','BillableLast24hGB')

## Defender XDR unification

How far this workspace is on the unified Sentinel and Defender model: the XDR connector and its data types, the advanced-hunting tables actually streaming, the legacy incident-creation rules that the unified queue makes redundant, and the Defender for Cloud connectors.

$(Format-Table -Items $unificationRows -Columns 'Check','Value','Meaning')

[Connector reference (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/data-connectors-reference) · [Connector health monitoring](https://learn.microsoft.com/azure/sentinel/monitor-data-connectors-health)
"@

Write-Section '10-data-connectors.md' $connectorBody

# ---------------------------------------------------------------------------
# Section: 20-analytics-rules
# ---------------------------------------------------------------------------
$ruleRows = $rules | ForEach-Object {
    [pscustomobject]@{
        Kind     = $_.kind
        Name     = $_.properties.displayName
        Severity = $_.properties.severity
        Enabled  = if ($_.properties.enabled) { 'Yes' } else { 'No' }
        Tactics  = ($_.properties.tactics -join ', ')
    }
}

# Per-kind / per-state aggregate counts. Microsoft-managed kinds (Fusion etc)
# are excluded from the Scheduled/NRT counts because they aren't user-editable.
$schedEnabled  = @($rules | Where-Object { $_.kind -eq 'Scheduled' -and $_.properties.enabled }).Count
$schedDisabled = @($rules | Where-Object { $_.kind -eq 'Scheduled' -and -not $_.properties.enabled }).Count
$nrtEnabled    = @($rules | Where-Object { $_.kind -eq 'NRT' -and $_.properties.enabled }).Count
$nrtDisabled   = @($rules | Where-Object { $_.kind -eq 'NRT' -and -not $_.properties.enabled }).Count

# Mouldy rules — Scheduled / NRT rules enabled but last-modified > 1 year ago.
$yearAgo = (Get-Date).ToUniversalTime().AddYears(-1)
$mouldyRows = $rules | Where-Object {
    $_.kind -in @('Scheduled','NRT') -and
    $_.properties.enabled -and
    $_.properties.lastModifiedUtc -and
    ([datetime]$_.properties.lastModifiedUtc) -lt $yearAgo
} | ForEach-Object {
    [pscustomobject]@{
        Name         = $_.properties.displayName
        Kind         = $_.kind
        Severity     = $_.properties.severity
        LastModified = ([datetime]$_.properties.lastModifiedUtc).ToString('yyyy-MM-dd')
    }
}

# MS Incident Creation rules — these aren't user-editable detection rules
# in the usual sense; they translate first-party security alerts into
# Sentinel incidents based on per-product filter criteria. Surface those
# filter fields explicitly since they don't fit the standard row schema.
$msIncidentRows = $rules | Where-Object { $_.kind -eq 'MicrosoftSecurityIncidentCreation' } | ForEach-Object {
    [pscustomobject]@{
        Name              = $_.properties.displayName
        Product           = $_.properties.productFilter
        Severities        = (@($_.properties.severitiesFilter) -join ', ')
        Includes          = (@($_.properties.displayNamesFilter) -join '; ')
        Excludes          = (@($_.properties.displayNamesExcludeFilter) -join '; ')
        Enabled           = if ($_.properties.enabled) { 'Yes' } else { 'No' }
    }
}

# Template mismatch — rules whose templateVersion does not match the latest
# template version. Look up the template by alertRuleTemplateName in the
# captured alert-rule-templates.json.
$alertRuleTemplates = Read-RawArray 'alert-rule-templates.json'
$templateByName = @{}
foreach ($t in $alertRuleTemplates) {
    if ($t.name) { $templateByName[$t.name] = $t }
}
$mismatchRows = $rules | Where-Object {
    $_.properties.alertRuleTemplateName -and
    $_.properties.templateVersion -and
    $templateByName.ContainsKey($_.properties.alertRuleTemplateName) -and
    $templateByName[$_.properties.alertRuleTemplateName].properties.version -and
    $templateByName[$_.properties.alertRuleTemplateName].properties.version -ne $_.properties.templateVersion
} | ForEach-Object {
    $tplName = $_.properties.alertRuleTemplateName
    [pscustomobject]@{
        Name           = $_.properties.displayName
        Kind           = $_.kind
        CurrentVersion = $_.properties.templateVersion
        LatestVersion  = $templateByName[$tplName].properties.version
    }
}

# Rule-kind distribution for the headline.
$ruleKindCounts = @{}
foreach ($r in $rules) {
    $k = if ($r.kind) { [string]$r.kind } else { 'unknown' }
    if (-not $ruleKindCounts.ContainsKey($k)) { $ruleKindCounts[$k] = 0 }
    $ruleKindCounts[$k]++
}
$schedNote = if ($ruleKindCounts.ContainsKey('Scheduled')) { "$($ruleKindCounts['Scheduled']) deployed" } else { 'not deployed' }
$msicNote  = if ($ruleKindCounts.ContainsKey('MicrosoftSecurityIncidentCreation')) { "$($ruleKindCounts['MicrosoftSecurityIncidentCreation']) deployed" } else { 'not deployed' }

# Fusion vs Defender XDR Correlation Engine state. When a workspace is
# onboarded to the Microsoft Defender unified portal (USOP), Microsoft
# automatically disables the Fusion analytic rule and the Defender XDR
# Correlation Engine takes over alert-to-incident correlation. The
# canonical, capture-derivable signal is the combination of:
#   - whether a Fusion rule exists and is enabled, AND
#   - whether the Microsoft Defender XDR connector
#     (kind = MicrosoftThreatProtection) is enabled.
# The four (fusion × defender) cells map to four reader-facing narratives
# below.
$fusionRules    = @($rules | Where-Object { $_.kind -eq 'Fusion' })
$fusionPresent  = $fusionRules.Count -gt 0
$fusionEnabled  = @($fusionRules | Where-Object { $_.properties.enabled }).Count -gt 0

$m365DefenderConnected = $false
foreach ($c in $connectors) {
    if ($c.kind -ne 'MicrosoftThreatProtection') { continue }
    $dts = $c.properties.dataTypes
    if ($dts) {
        foreach ($p in $dts.PSObject.Properties) {
            if ($p.Value.state -eq 'Enabled') { $m365DefenderConnected = $true; break }
        }
    }
    if ($m365DefenderConnected) { break }
}

$correlationState = if ($fusionEnabled -and $m365DefenderConnected) {
    '**Fusion enabled, Defender XDR connector enabled.** If this workspace is onboarded to the Microsoft Defender unified portal (USOP), Microsoft auto-disables Fusion regardless of the displayed state above and the Defender XDR Correlation Engine performs alert-to-incident correlation. Confirm by checking the workspace''s onboarding state in the Defender portal. If it is onboarded, treat the displayed Fusion state as informational only.'
} elseif ((-not $fusionEnabled) -and $m365DefenderConnected) {
    '**Fusion disabled, Defender XDR connector enabled.** This workspace is using the **Defender XDR Correlation Engine** for alert-to-incident correlation. Microsoft auto-disables the Fusion rule on workspaces onboarded to the Defender unified portal, where Defender XDR''s correlation replaces it.'
} elseif ($fusionEnabled -and (-not $m365DefenderConnected)) {
    '**Fusion enabled, no Defender XDR connector.** Fusion is performing multi-source ML-based incident correlation across Sentinel data sources. Onboarding the workspace to the Defender unified portal would auto-disable Fusion and hand correlation to Defender XDR.'
} elseif ($fusionPresent -and -not $fusionEnabled -and -not $m365DefenderConnected) {
    '**Fusion present but disabled, no Defender XDR connector.** No ML-based incident correlation is active on this workspace.'
} else {
    '**No Fusion rule deployed, no Defender XDR connector.** No ML-based incident correlation. Either enable the Fusion rule for multi-source correlation, or onboard to the Defender unified portal to inherit the Defender XDR Correlation Engine.'
}

# The rule kinds as data for the SharePoint graphic: every kind with its
# settings, what it does, and how many this workspace deploys and enables.
$ruleKindEnabled = @{}
foreach ($r in $rules) {
    if (-not ($r.properties -and $r.properties.enabled -eq $true)) { continue }
    $k = if ($r.kind) { [string]$r.kind } else { 'unknown' }
    if (-not $ruleKindEnabled.ContainsKey($k)) { $ruleKindEnabled[$k] = 0 }
    $ruleKindEnabled[$k]++
}
$ruleKindDefs = @(
    [ordered]@{ kind = 'Scheduled'; label = 'Scheduled'; summary = 'A KQL query on a schedule; raises an alert when its results pass a threshold.'; fields = @('queryFrequency', 'queryPeriod', 'triggerThreshold', 'query'); legacy = $false }
    [ordered]@{ kind = 'NRT'; label = 'Near real time'; summary = 'A KQL query run every minute with no threshold, for detections that cannot wait.'; fields = @('query', 'eventGrouping'); legacy = $false }
    [ordered]@{ kind = 'Fusion'; label = 'Fusion'; summary = 'Microsoft machine learning that correlates low-fidelity alerts into high-fidelity incidents.'; fields = @('alertRuleTemplateName', 'sourceSettings'); legacy = $false }
    [ordered]@{ kind = 'MicrosoftSecurityIncidentCreation'; label = 'Microsoft incident creation'; summary = 'Turns alerts from a Microsoft security product into incidents: the pattern from before Defender XDR.'; fields = @('productFilter', 'severitiesFilter', 'displayNamesFilter', 'displayNamesExcludeFilter'); legacy = $true }
    [ordered]@{ kind = 'ThreatIntelligence'; label = 'Threat intelligence'; summary = 'Matches Microsoft threat intelligence indicators against the workspace logs.'; fields = @('templateVersion'); legacy = $false }
    [ordered]@{ kind = 'MLBehaviorAnalytics'; label = 'ML behaviour analytics'; summary = 'Built-in machine learning anomaly detections, such as unusual SSH or RDP sign-ins.'; fields = @('alertRuleTemplateName'); legacy = $false }
)
$ruleKindItems = [System.Collections.Generic.List[object]]::new()
foreach ($d in $ruleKindDefs) {
    $n = if ($ruleKindCounts.ContainsKey($d.kind)) { $ruleKindCounts[$d.kind] } else { 0 }
    # The five kinds every workspace can have always show; ML behaviour analytics only when deployed.
    if ($d.kind -eq 'MLBehaviorAnalytics' -and $n -eq 0) { continue }
    $item = [ordered]@{}; foreach ($key in $d.Keys) { $item[$key] = $d[$key] }
    $item.deployed = $n
    $item.enabled = $(if ($ruleKindEnabled.ContainsKey($d.kind)) { $ruleKindEnabled[$d.kind] } else { 0 })
    $ruleKindItems.Add($item)
}
foreach ($k in @($ruleKindCounts.Keys | Where-Object { $_ -notin @($ruleKindDefs | ForEach-Object { $_.kind }) } | Sort-Object)) {
    $ruleKindItems.Add([ordered]@{ kind = $k; label = $k; summary = 'A rule kind this report does not describe.'; fields = @(); legacy = $false; deployed = $ruleKindCounts[$k]; enabled = $(if ($ruleKindEnabled.ContainsKey($k)) { $ruleKindEnabled[$k] } else { 0 }) })
}
$ruleKindsVisualLine = Format-VisualLine -Kind 'rule-kinds' -Data ([ordered]@{
    total  = $rules.Count
    common = @('id', 'kind', 'displayName', 'severity', 'enabled', 'lastModifiedUtc', 'tactics', 'techniques')
    kinds  = $ruleKindItems.ToArray()
})

$rulesBody = @"
$(Format-Banner -Title "Analytics Rules")

## Rule taxonomy

Sentinel's ``alertRules`` API surfaces every kind of detection logic under a single base: the fields every rule carries, then the settings only each kind has, with how many of each this workspace deploys. Worth knowing when later sections refer to "MS Incident Creation rules", because those rules have a completely different shape from Scheduled:

``````mermaid
classDiagram
$ruleKindsVisualLine
    class AlertRule {
        +string id
        +string kind
        +string displayName
        +string severity
        +bool enabled
        +datetime lastModifiedUtc
        +string[] tactics
        +string[] techniques
    }

    class Scheduled {
        +string queryFrequency
        +string queryPeriod
        +int triggerThreshold
        +string query
    }

    class NRT {
        +string query
        +bool eventGrouping
    }

    class Fusion {
        +string alertRuleTemplateName
        +string[] sourceSettings
    }

    class MicrosoftSecurityIncidentCreation {
        +string productFilter
        +string[] severitiesFilter
        +string[] displayNamesFilter
        +string[] displayNamesExcludeFilter
    }

    class ThreatIntelligence {
        +string templateVersion
    }

    AlertRule <|-- Scheduled
    AlertRule <|-- NRT
    AlertRule <|-- Fusion
    AlertRule <|-- MicrosoftSecurityIncidentCreation
    AlertRule <|-- ThreatIntelligence

    note for Scheduled "$schedNote on this workspace"
    note for MicrosoftSecurityIncidentCreation "$msicNote (legacy pre-Defender XDR pattern)"
``````

## Incident correlation engine

$correlationState

[Microsoft Sentinel Fusion technology (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/fusion)
[Microsoft Defender XDR correlation in the unified SecOps portal (Microsoft Learn)](https://learn.microsoft.com/defender-xdr/microsoft-365-defender)

## Per-kind / per-state aggregate

| Total | Enabled | Disabled | Scheduled-Enabled | Scheduled-Disabled | NRT-Enabled | NRT-Disabled |
|---:|---:|---:|---:|---:|---:|---:|
| $($rules.Count) | $($enabledRules.Count) | $($rules.Count - $enabledRules.Count) | $schedEnabled | $schedDisabled | $nrtEnabled | $nrtDisabled |

The Microsoft-managed rules, recent modifications, the Content Hub solution breakdown and the Defender XDR custom detections follow below on this page. Alert volume and incident outcomes per rule are in [21-rule-performance.md](21-rule-performance.md); run failures, complexity, stale rules, template drift and the entity-mapping and incident-creation anti-patterns are in [22-rule-health-quality.md](22-rule-health-quality.md); tables no enabled rule reads, with the templates that would cover them, are in [28-detection-opportunities.md](28-detection-opportunities.md).

## All rules

$(Format-Table -Items $ruleRows -Columns 'Kind','Name','Severity','Enabled','Tactics')

## MS Incident Creation rules

These translate first-party security alerts (Defender for Cloud Apps, Defender XDR, etc.) into Sentinel incidents based on per-product filter criteria. They aren't editable as KQL rules; the ``Product`` column is the source product, and ``Includes`` / ``Excludes`` are the alert-name filters.

$(Format-Table -Items $msIncidentRows -Columns 'Name','Product','Severities','Includes','Excludes','Enabled')
"@
# $rulesBody is the first part of 20-analytics-rules.md; the alert-volume,
# Microsoft-managed, modifications and solution subsections are built after
# section 15 (they need its effectiveness rows) and the page is written there.

# ---------------------------------------------------------------------------
# Section: 25-mitre-coverage
# ---------------------------------------------------------------------------
# Catalogue file (resource-bundled) carries:
#   tactics[]    { id, name, shortname (kebab, STIX), sentinelShortName
#                  (PascalCase, what Sentinel rules return in tactics[]) }
#   techniques[] { id, name, tactics (kebab), tacticsSentinel (PascalCase),
#                  isSubtechnique, parentId, url, platforms, dataSources }
# The renderer joins each rule's `properties.techniques` against the
# catalogue so cells show "T1078 — Valid Accounts" rather than a bare ID.
$mitreFile = Join-Path $ResourcesRoot 'mitre-attack.json'
$tactics = @()
$mitreTechniques = @()
if (Test-Path $mitreFile) {
    $mitreCatalogue = Get-Content $mitreFile -Raw | ConvertFrom-Json
    $tactics = @($mitreCatalogue.tactics)
    $mitreTechniques = @($mitreCatalogue.techniques)
}

# Build a technique-id -> name lookup so every render path resolves names
# consistently. Sub-techniques also get their parent's name prefixed in a
# separate fullName lookup so a row reading "T1078.004 — Cloud Accounts" can
# fall back to "Valid Accounts: Cloud Accounts" when richer context helps.
$techNameById = @{}
$techFullNameById = @{}
foreach ($t in $mitreTechniques) {
    if (-not $t.id) { continue }
    $techNameById[$t.id] = $t.name
    if ($t.PSObject.Properties.Name -contains 'parentId' -and $t.parentId) {
        $parent = $techNameById[$t.parentId]
        if ($parent) { $techFullNameById[$t.id] = "${parent}: $($t.name)" }
    }
}
function Format-MitreTechniqueCell {
    param([string]$Id, [bool]$Sub = $false)
    if (-not $Id) { return '' }
    $name = $techNameById[$Id]
    $urlId = if ($Sub) { $Id.Replace('.', '/') } else { $Id }
    if ($name) {
        return "[${Id}: $name](https://attack.mitre.org/techniques/$urlId/)"
    }
    return "[$Id](https://attack.mitre.org/techniques/$urlId/)"
}

$tacticCounts = @{}
foreach ($t in $tactics) { $tacticCounts[$t.sentinelShortName] = 0 }
foreach ($r in $enabledRules) {
    # Some rule kinds (e.g. MicrosoftSecurityIncidentCreation) omit the
    # tactics property entirely; @($null) iterates once with $t = $null
    # which would throw on ContainsKey. Filter nulls.
    foreach ($t in @($r.properties.tactics | Where-Object { $_ })) {
        if ($tacticCounts.ContainsKey($t)) { $tacticCounts[$t]++ }
    }
}

$mitreRows = foreach ($t in $tactics) {
    $count = $tacticCounts[$t.sentinelShortName]
    [pscustomobject]@{
        ID = $t.id
        Tactic = $t.name
        EnabledRules = $count
        Coverage = if ($count -eq 0) { 'None' } elseif ($count -lt 3) { 'Thin' } else { 'Covered' }
    }
}

# Build the hierarchy: tactic -> technique -> sub-technique -> rules, from
# Get-AttackCoverage (Private/Get-AttackCoverage.ps1), which the dashboard's
# ATT&CK grid reads too, so the two agree. It maps every rule, enabled or
# not; the tactic and technique tables count enabled rules only, and the
# rule table at the end lists every rule with its status.
$attackCoverage = Get-AttackCoverage -Rules @($rules) -Catalogue $(if (Test-Path $mitreFile) { $mitreCatalogue } else { $null })
$subTotalByParent = $attackCoverage.SubTotals
$tacticNameByShort = @{}
foreach ($t in $tactics) { $tacticNameByShort[[string]$t.sentinelShortName] = [string]$t.name }
$enabledIdx = [System.Collections.Generic.HashSet[int]]::new()
foreach ($row in $attackCoverage.Rules) { if ($row.Enabled) { [void]$enabledIdx.Add($row.Index) } }
$mitreHierarchy = @{}
$anyTechniques = [System.Collections.Generic.HashSet[string]]::new()
foreach ($tac in $attackCoverage.Cells.Keys) {
    foreach ($tech in $attackCoverage.Cells[$tac].Keys) {
        [void]$anyTechniques.Add($tech)
        $cell = $attackCoverage.Cells[$tac][$tech]
        $on = [System.Collections.Generic.List[int]]::new()
        foreach ($i in $cell.Rules) { if ($enabledIdx.Contains($i)) { $on.Add($i) } }
        if (-not $on.Count) { continue }
        if (-not $mitreHierarchy.ContainsKey($tac)) { $mitreHierarchy[$tac] = @{} }
        $subs = @{}
        foreach ($sub in $cell.Subs.Keys) {
            $subOn = [System.Collections.Generic.List[int]]::new()
            foreach ($i in $cell.Subs[$sub]) { if ($enabledIdx.Contains($i)) { $subOn.Add($i) } }
            if ($subOn.Count) { $subs[$sub] = $subOn }
        }
        $mitreHierarchy[$tac][$tech] = @{ Rules = $on; Subs = $subs }
    }
}
$ruleAttackRows = @($attackCoverage.Rules | Sort-Object @{ Expression = { -not $_.Enabled } }, Name | ForEach-Object {
        [pscustomobject]@{
            'Rule'           = $_.Name
            'Status'         = $(if ($_.Enabled) { 'Enabled' } else { 'Disabled' })
            'Tactics'        = $(if ($_.Tactics.Count) { ($_.Tactics | ForEach-Object { if ($tacticNameByShort.ContainsKey($_)) { $tacticNameByShort[$_] } else { $_ -creplace '([a-z])([A-Z])', '$1 $2' } }) -join ', ' } else { 'None' })
            'Techniques'     = $(if ($_.Techniques.Count) { $_.Techniques -join ', ' } else { 'None' })
            'Sub-techniques' = $(if ($_.SubTechniques.Count) { $_.SubTechniques -join ', ' } else { 'None' })
        }
    })
$rulesEnabledCount = $enabledIdx.Count
$rulesWithoutTechnique = @($attackCoverage.Rules | Where-Object { $_.Enabled -and -not $_.Techniques.Count }).Count
$rulesWithSub = @($attackCoverage.Rules | Where-Object { $_.Enabled -and $_.SubTechniques.Count }).Count
$enabledTechniques = [System.Collections.Generic.HashSet[string]]::new()
foreach ($tac in $mitreHierarchy.Keys) { foreach ($tech in $mitreHierarchy[$tac].Keys) { [void]$enabledTechniques.Add($tech) } }
$disabledOnlyTechniques = @($anyTechniques | Where-Object { -not $enabledTechniques.Contains($_) }).Count

# Build the headline tactic matrix from the same data.
$mitreRowsRich = foreach ($t in $tactics) {
    $key = $t.sentinelShortName
    $tacticBucket = if ($mitreHierarchy.ContainsKey($key)) { $mitreHierarchy[$key] } else { @{} }
    $techCount = $tacticBucket.Count
    $subCount = 0
    foreach ($v in $tacticBucket.Values) { $subCount += $v.Subs.Count }
    $ruleCount = $tacticCounts[$key]
    $coverage = if ($ruleCount -eq 0) { 'None' } elseif ($ruleCount -lt 3) { 'Thin' } else { 'Covered' }
    [pscustomobject]@{
        ID = $t.id
        Tactic = $t.name
        EnabledRules = $ruleCount
        Techniques = $techCount
        SubTechniques = $subCount
        Coverage = $coverage
    }
}
$mitreTacticsTotal   = @($mitreRowsRich).Count
$mitreTacticsCovered = @($mitreRowsRich | Where-Object { $_.Coverage -eq 'Covered' }).Count
$mitreTacticsThin    = @($mitreRowsRich | Where-Object { $_.Coverage -eq 'Thin' }).Count
$mitreTacticsNone    = @($mitreRowsRich | Where-Object { $_.Coverage -eq 'None' }).Count
$mitreTechTotal = @(@($mitreHierarchy.Values | ForEach-Object { $_.Keys }) | Sort-Object -Unique).Count
$mitreSubTotal  = @(@($mitreHierarchy.Values | ForEach-Object { $_.Values } | ForEach-Object { $_.Subs.Keys }) | Sort-Object -Unique).Count

# One table per tactic the rules reach: each technique, then its
# sub-techniques, with the number of enabled rules on each. Rule names are
# not listed here; the table at the end of the page carries every rule with
# its mapping, so a technique's rules are a filter on that table.
$detailSections = New-Object System.Text.StringBuilder
$uncoveredTactics = [System.Collections.Generic.List[string]]::new()
foreach ($t in $tactics) {
    $key = $t.sentinelShortName
    if (-not $mitreHierarchy.ContainsKey($key) -or $mitreHierarchy[$key].Count -eq 0) {
        $uncoveredTactics.Add("[$($t.id) $($t.name)](https://attack.mitre.org/tactics/$($t.id)/)")
        continue
    }
    $techRows = foreach ($techId in ($mitreHierarchy[$key].Keys | Sort-Object)) {
        $bucket = $mitreHierarchy[$key][$techId]
        $subTotal = [int]$subTotalByParent[$techId]
        [pscustomobject]@{
            'Technique'              = Format-MitreTechniqueCell -Id $techId -Sub $false
            'Sub-technique'          = ''
            'Rules'                  = $bucket.Rules.Count
            'Sub-techniques covered' = $(if ($subTotal) { "$($bucket.Subs.Count) of $subTotal" } else { 'n/a' })
        }
        foreach ($subId in ($bucket.Subs.Keys | Sort-Object)) {
            [pscustomobject]@{
                'Technique'              = ''
                'Sub-technique'          = Format-MitreTechniqueCell -Id $subId -Sub $true
                'Rules'                  = $bucket.Subs[$subId].Count
                'Sub-techniques covered' = ''
            }
        }
    }
    [void]$detailSections.AppendLine("")
    [void]$detailSections.AppendLine("### $($t.id) · $($t.name)")
    [void]$detailSections.AppendLine("")
    [void]$detailSections.AppendLine((Format-Table -Items $techRows -Columns 'Technique', 'Sub-technique', 'Rules', 'Sub-techniques covered'))
}
$uncoveredLine = if ($uncoveredTactics.Count) { "No enabled rule maps a technique in: $($uncoveredTactics -join ', ')." } else { 'Every tactic has at least one technique mapped by an enabled rule.' }

# Build the bar-chart inputs from $mitreRowsRich (already sorted by tactic).
# Short labels per tactic so x-axis fits 14 entries; full names live in the
# matrix table below.
$labelMap = @{
    'Reconnaissance' = 'Recon'; 'ResourceDevelopment' = 'ResDev'; 'InitialAccess' = 'Initial'
    'Execution' = 'Exec'; 'Persistence' = 'Persist'; 'PrivilegeEscalation' = 'PrivEsc'
    'DefenseEvasion' = 'DefEva'; 'CredentialAccess' = 'CredAcc'; 'Discovery' = 'Discov'
    'LateralMovement' = 'LatMov'; 'Collection' = 'Collect'; 'CommandAndControl' = 'C2'
    'Exfiltration' = 'Exfil'; 'Impact' = 'Impact'
}
$mitreAxis = ($tactics | ForEach-Object {
    $key = $_.sentinelShortName
    $lbl = if ($labelMap.ContainsKey($key)) { $labelMap[$key] } else { $key.Substring(0, [math]::Min(7, $key.Length)) }
    "`"$lbl`""
}) -join ', '
$mitreBars = ($mitreRowsRich | ForEach-Object { $_.EnabledRules }) -join ', '
$mitreMax = 1
foreach ($r in $mitreRowsRich) { if ($r.EnabledRules -gt $mitreMax) { $mitreMax = $r.EnabledRules } }
$mitreYmax = [int]([math]::Ceiling(($mitreMax + 1) / 10.0)) * 10

$mitreBody = @"
$(Format-Banner -Title "MITRE ATT&CK Coverage")

Coverage comes from every **enabled** Sentinel detection rule: its ``tactics``, its ``techniques`` and its ``subTechniques``. A sub-technique (such as ``T1078.004``) also counts towards its parent technique. Each technique sits under the tactics ATT&CK gives it, so a rule tagged with several tactics does not spread every technique across all of them. Every ID links to its entry on attack.mitre.org.

## Coverage shape: rules per tactic

``````mermaid
---
config:
  xyChart:
    width: 1400
    height: 480
---
xychart-beta
    title "Enabled rules per MITRE tactic"
    x-axis [$mitreAxis]
$(Format-XyFullLabels @($tactics | ForEach-Object { $_.name }))
    y-axis "Enabled rules" 0 --> $mitreYmax
    bar [$mitreBars]
``````

**$mitreTacticsCovered Covered · $mitreTacticsThin Thin · $mitreTacticsNone None** of $mitreTacticsTotal tactics (Covered: three or more enabled rules; Thin: one or two). Enabled rules map **$mitreTechTotal** techniques and **$mitreSubTotal** sub-techniques.

## Tactic matrix

$(Format-Table -Items $mitreRowsRich -Columns 'ID','Tactic','EnabledRules','Techniques','SubTechniques','Coverage')

## Technique and sub-technique breakdown

One table per tactic: each technique an enabled rule maps, then the sub-techniques mapped under it, with the number of enabled rules on each. **Sub-techniques covered** compares the sub-techniques mapped with the number ATT&CK defines for the technique (n/a when it defines none). To see which rules cover a technique, filter the rule table at the end of this page by its ID; the dashboard's ATT&CK grid shows the same coverage as a matrix.

$uncoveredLine
$($detailSections.ToString())
## Rules and their ATT&CK mapping

Every analytics rule, enabled first and then disabled, with the tactics, techniques and sub-techniques it maps, so a rule can be found by name or by an ATT&CK ID. The tables above count enabled rules only: **$rulesEnabledCount** of **$(@($ruleAttackRows).Count)** rules are enabled. $rulesWithoutTechnique enabled rules map no technique, so they count in the rules-per-tactic chart but not in the technique tables; $rulesWithSub map at least one sub-technique.$(if ($disabledOnlyTechniques) { " Enabling the disabled rules would add **$disabledOnlyTechniques** techniques that no enabled rule covers." })$(if ($rulesEnabledCount -and -not $rulesWithSub) { ' No enabled rule maps a sub-technique in this snapshot. Collections before release 26.10 did not read sub-techniques (every GA version of the rules API leaves them out); a new collection picks them up.' })

$(Format-Table -Items $ruleAttackRows -Columns 'Rule', 'Status', 'Tactics', 'Techniques', 'Sub-techniques' -EmptyMessage '_No analytics rules._')

[MITRE coverage in Sentinel (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/mitre-coverage) · [ATT&CK Enterprise (mitre.org)](https://attack.mitre.org/matrices/enterprise/)
"@

Write-Section '25-mitre-coverage.md' $mitreBody

# ---------------------------------------------------------------------------
# Section: 30 / 35 — hunting & parsers
# ---------------------------------------------------------------------------
$hunting = Read-RawArray 'hunting-queries.json'
$parsers = Read-RawArray 'parsers-functions.json'

$huntingRows = $hunting | ForEach-Object {
    [pscustomobject]@{
        Name = $_.properties.displayName
        Tags = ($_.properties.tags | ForEach-Object { "$($_.name)=$($_.value)" }) -join ', '
    }
}
# Aggregate hunting queries by tactic (parsed from the tactics= tag value).
$huntByTactic = @{}
foreach ($h in $hunting) {
    # Named so it cannot shadow $tactics, the MITRE catalogue that the
    # section-01 headline counts.
    $huntTacticTags = @($h.properties.tags | Where-Object { $_.name -eq 'tactics' } | ForEach-Object { $_.value })
    if (-not $huntTacticTags) { $huntTacticTags = @('Untagged') }
    foreach ($t in $huntTacticTags) {
        # tactics tag can be a comma-separated list
        foreach ($tac in ($t -split ',')) {
            $key = $tac.Trim()
            if (-not $key) { continue }
            if (-not $huntByTactic.ContainsKey($key)) { $huntByTactic[$key] = 0 }
            $huntByTactic[$key]++
        }
    }
}
$huntPieRows = Format-PieSlices -Counts $huntByTactic
$huntChartBlock = if ($hunting.Count -gt 0 -and $huntPieRows.Count -gt 0) {
    @"

## Hunting queries by tactic

``````mermaid
pie showData title Hunting queries by MITRE tactic
$($huntPieRows -join [Environment]::NewLine)
``````

$($hunting.Count) hunting query(ies). Tactic distribution reveals where the SOC's free-form investigation library is strongest and where the gaps live.
"@
} else { '' }

$bookmarkRows = @($bookmarks | Where-Object { $_ } | ForEach-Object {
    $p = _RProp $_ 'properties' $null
    $created = [string](_RProp $p 'created' '')
    [pscustomobject]@{
        Name    = [string](_RProp $p 'displayName' (_RProp $_ 'name' ''))
        Created = $(if ($created) { try { Format-DateUtc $created } catch { $created } } else { '' })
        Labels  = (@(_RProp $p 'labels' @()) -join ', ')
        Notes   = [string](_RProp $p 'notes' '')
    }
})
$bookmarkBlock = if ($bookmarkRows.Count -gt 0) {
    "Bookmarks saved from hunting and investigation, newest first. Their labels are the analyst's own tags.`n`n" + (Format-Table -Items @($bookmarkRows | Sort-Object Created -Descending) -Columns 'Name','Created','Labels','Notes')
} elseif ($bookmarkCountDoc -and [int](_RendererNumber (_RProp $bookmarkCountDoc 'Count' 0)) -gt 0) {
    "**$([int](_RendererNumber (_RProp $bookmarkCountDoc 'Count' 0))) bookmarks** exist. The list was too large for the API to return, so only the count was captured."
} else { '_None._' }
$huntRows = @($hunts | ForEach-Object {
    $p = if ($_.PSObject.Properties['properties'] -and $_.properties) { $_.properties } else { $_ }
    $owner = ''
    if ($p.PSObject.Properties['owner'] -and $p.owner) {
        if ($p.owner.PSObject.Properties['assignedTo'] -and $p.owner.assignedTo) { $owner = $p.owner.assignedTo }
        elseif ($p.owner.PSObject.Properties['email'] -and $p.owner.email) { $owner = $p.owner.email }
    }
    [pscustomobject]@{
        Name       = if ($p.PSObject.Properties['displayName']) { $p.displayName } elseif ($_.PSObject.Properties['name']) { $_.name } else { '' }
        Status     = if ($p.PSObject.Properties['status']) { $p.status } else { '' }
        Hypothesis = if ($p.PSObject.Properties['hypothesisStatus']) { $p.hypothesisStatus } else { '' }
        Tactics    = if ($p.PSObject.Properties['attackTactics']) { @($p.attackTactics) -join ', ' } else { '' }
        Owner      = $owner
    }
})

Write-Section '30-hunting-queries.md' (@"
$(Format-Banner -Title "Hunting Queries")
$huntChartBlock

$(Format-Table -Items $huntingRows -Columns 'Name','Tags')

## Hunts

Hunts recorded through the Hunts feature, with their hypothesis status. Bookmarks promoted from a hunt show on the incidents they were attached to. [SAC-HNT-01] fires when there are no hunts and no bookmarks at all.

$(Format-Table -Items $huntRows -Columns 'Name','Status','Hypothesis','Tactics','Owner')

## Bookmarks

$bookmarkBlock

[Hunts in Microsoft Sentinel (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/hunts)
"@)

$parserRows = $parsers | ForEach-Object {
    [pscustomobject]@{
        Name = $_.properties.displayName
        Alias = $_.properties.functionAlias
        Category = $_.properties.category
    }
}

# Pie of parsers/functions by category.
$parserByCat = @{}
foreach ($p in $parserRows) {
    $c = if ($p.Category) { [string]$p.Category } else { 'Uncategorised' }
    if (-not $parserByCat.ContainsKey($c)) { $parserByCat[$c] = 0 }
    $parserByCat[$c]++
}
$parserPieRows = Format-PieSlices -Counts $parserByCat -Limit 8
$parserChartBlock = if ($parserRows.Count -gt 0 -and $parserPieRows.Count -gt 0) {
    @"

## Parsers by category

``````mermaid
pie showData title Parsers and functions by category
$($parserPieRows -join [Environment]::NewLine)
``````

$($parserRows.Count) parser(s) / function(s). Each entry is a `let`-style KQL definition reusable across rules and hunting queries.
"@
} else { '' }

# Saved searches that are neither hunting queries nor parsers: queries
# saved from Logs under categories such as Log Management.
$otherSavedRows = @(Read-RawArray 'kql-savedsearches.json' | Where-Object { $_ } | ForEach-Object {
    $p = _RProp $_ 'properties'
    $cat = [string](_RProp $p 'category' '')
    if ($cat -eq 'Hunting Queries' -or $cat -eq 'Functions' -or [string](_RProp $p 'functionAlias' '')) { return }
    $q = [string](_RProp $p 'query' '')
    [pscustomobject]@{
        Category   = $(if ($cat) { $cat } else { 'Uncategorised' })
        Name       = [string](_RProp $p 'displayName' (_RProp $_ 'name' ''))
        QueryLines = $(if ($q) { @($q -split "\r?\n").Count } else { 0 })
    }
} | Sort-Object Category, Name)

Write-Section '35-parsers-functions.md' (@"
$(Format-Banner -Title "Parsers and Functions")
$parserChartBlock

$(Format-Table -Items $parserRows -Columns 'Name','Alias','Category')

## Other saved searches

Saved searches in the workspace that are neither hunting queries ([30-hunting-queries.md](30-hunting-queries.md)) nor parsers: queries saved from Logs under categories such as Log Management or General Exploration. Ones nobody owns are clutter; the ones worth keeping belong in source control as hunting queries or functions.

$(Format-Table -Items $otherSavedRows -Columns 'Category','Name','QueryLines' -EmptyMessage (Get-EmptyMessage 'kql-savedsearches.json' '_None: every saved search is a hunting query or a parser._'))
"@)

# ---------------------------------------------------------------------------
# Section: 40 / 50 / 60 / 70
# ---------------------------------------------------------------------------
$workbookTemplates = Read-RawArray 'workbook-templates.json'
$wbRows = $workbooksSaved | ForEach-Object {
    [pscustomobject]@{ Name = $_.properties.displayName; Category = $_.properties.category }
}
$wbUnsaved = [math]::Max(0, $workbookTemplates.Count - $workbooksSaved.Count)
Write-Section '40-workbooks.md' (@"
$(Format-Banner -Title "Workbooks")

## Adoption

``````mermaid
pie showData title Workbook coverage
    "Saved (deployed)" : $($workbooksSaved.Count)
    "Available templates not deployed" : $wbUnsaved
``````

$($workbooksSaved.Count) of $($workbookTemplates.Count) available templates deployed in this workspace. The "templates not deployed" gap is where new visibility opportunities live.

## Saved workbooks

$(Format-Table -Items $wbRows -Columns 'Name','Category')

## Templates available (Content Hub)

Total available: $($workbookTemplates.Count)
"@)

# Freshness from the shared helper (the gap check SAC-DET-15 reads the
# same): stale and read by enabled rules first, then stale, current, and
# the watchlists Content Hub solutions ship.
$wlFresh = @(Get-WatchlistFreshness -Watchlists @($watchlists) -RuleUse (Get-WatchlistRuleUse -Rules @(Read-RawArray 'alert-rules.json')))
$wlFreshByAlias = @{}
foreach ($f in $wlFresh) { if ($f.Alias) { $wlFreshByAlias[$f.Alias] = $f } }
$wlStatusRank = @{ 'Stale, used by rules' = 0; 'Stale' = 1; 'Current' = 2; 'Content Hub' = 3 }
$wlRows = @($watchlists | Where-Object { $_ -and $_.properties } | ForEach-Object {
    $alias = $_.properties.watchlistAlias
    $f = if ($alias -and $wlFreshByAlias.ContainsKey($alias)) { $wlFreshByAlias[$alias] } else { $null }
    [pscustomobject]@{
        Name            = $_.properties.displayName
        Freshness       = $(if ($f) { $f.Status } else { '' })
        'Age (days)'    = $(if ($f -and $null -ne $f.AgeDays) { $f.AgeDays } else { '' })
        Updated         = Format-DateUtc $_.properties.updated
        'Enabled rules' = $(if ($f) { $f.EnabledRules } else { 0 })
        'Maintained by' = $(if ($f) { $f.MaintainedBy } else { '' })
        'Search key'    = $_.properties.itemsSearchKey
        Provider        = if ($_.properties.provider) { [string]$_.properties.provider } else { '' }
        Description     = if ($_.properties.description) { [string]$_.properties.description } else { '' }
        _Rank           = $(if ($f) { $wlStatusRank[$f.Status] } else { 9 })
        _Age            = $(if ($f -and $null -ne $f.AgeDays) { $f.AgeDays } else { -1 })
    }
} | Sort-Object _Rank, @{ Expression = '_Age'; Descending = $true }, Name)
$wlOwn = @($wlFresh | Where-Object MaintainedBy -EQ 'Workspace').Count
$wlStale = @($wlFresh | Where-Object { $_.Status -like 'Stale*' }).Count
$wlStaleUsed = @($wlFresh | Where-Object Status -EQ 'Stale, used by rules').Count
$wlHub = @($wlFresh | Where-Object MaintainedBy -EQ 'Content Hub').Count
$wlDescRows = @($wlRows | Where-Object { $_.Description } | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Description = $_.Description } })

# Detailed rule-by-watchlist mapping rendered as a separate subsection.
# Orphan watchlists (zero rule references) are surfaced explicitly —
# they may still be used by hunting queries, workbooks, or analyst
# KQL, but the absence of any analytics-rule reference is a useful
# signal that the watchlist might be stale.
$wlUsageRows = New-Object System.Collections.Generic.List[object]
foreach ($wl in $watchlists) {
    $alias = $wl.properties.watchlistAlias
    if (-not $alias) { continue }
    $ruleNames = if ($rulesByWatchlistAlias.ContainsKey($alias)) { @($rulesByWatchlistAlias[$alias]) } else { @() }
    $wlUsageRows.Add([pscustomobject]@{
        Alias     = $alias
        RuleCount = $ruleNames.Count
        Rules     = if ($ruleNames.Count -gt 0) { ($ruleNames | Sort-Object -Unique) -join '; ' } else { '_(no analytics rule references)_' }
    })
}

# Watchlist aliases referenced by rules but NOT present in the captured
# watchlist set. These are 'broken' references — the rule queries will
# fail at runtime. Surfaced as a separate subsection only when present.
$wlAliasSet = @{}
foreach ($wl in $watchlists) {
    $a = $wl.properties.watchlistAlias
    if ($a) { $wlAliasSet[$a] = $true }
}
$brokenWatchlistRefs = New-Object System.Collections.Generic.List[object]
foreach ($alias in $rulesByWatchlistAlias.Keys) {
    if (-not $wlAliasSet.ContainsKey($alias)) {
        $brokenWatchlistRefs.Add([pscustomobject]@{
            MissingAlias = $alias
            RuleCount    = $rulesByWatchlistAlias[$alias].Count
            Rules        = ($rulesByWatchlistAlias[$alias] | Sort-Object -Unique) -join '; '
        })
    }
}

# Watchlists by provider for the headline pie (was "by source", but the
# source field is just the seed filename so all rows have a different
# value — useless as a pie distribution). Provider groups by who
# manages the watchlist (Microsoft vs first-party customer content).
$wlByProvider = @{}
foreach ($w in $wlRows) {
    $p = if ($w.Provider) { [string]$w.Provider } else { 'Unknown' }
    if (-not $wlByProvider.ContainsKey($p)) { $wlByProvider[$p] = 0 }
    $wlByProvider[$p]++
}
$wlPieRows = $wlByProvider.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}

# Pie only when 2+ provider buckets — single-slice pies are uninformative.
$wlChartBlock = if ($wlRows.Count -gt 0 -and $wlByProvider.Count -ge 2) {
    @"

## Watchlists by provider

``````mermaid
pie showData title Watchlists by provider
$($wlPieRows -join [Environment]::NewLine)
``````

"@
} else { '' }

$brokenRefsBlock = if ($brokenWatchlistRefs.Count -gt 0) { @"

## Broken watchlist references

Analytics rule(s) reference watchlist aliases that don't exist in this workspace. These rule queries will fail at runtime: investigate whether the watchlist was deleted or the alias is mistyped.

$(Format-Table -Items $brokenWatchlistRefs -Columns 'MissingAlias','RuleCount','Rules')
"@ } else { '' }

Write-Section '50-watchlists.md' (@"
$(Format-Banner -Title "Watchlists")
$wlChartBlock
**$($wlRows.Count)** watchlists  ·  **$wlOwn** maintained in the workspace  ·  **$wlStale** stale (not updated in $($script:WatchlistStaleDays) days)  ·  **$wlStaleUsed** stale and read by enabled rules  ·  **$wlHub** shipped by Content Hub solutions

A watchlist is reference data (assets, VIPs, allow-lists, IP ranges) that analytics rules and hunting queries look up with ``_GetWatchlist()``, and someone has to keep it current. **Freshness** is Stale when a watchlist maintained in the workspace has not been updated in $($script:WatchlistStaleDays) days, and **Stale, used by rules** when an enabled analytics rule still reads it: that rule is detecting against data that may be out of date ([SAC-DET-15]). Watchlists a Content Hub solution ships are its reference data, kept current by updating the solution. Item bodies are not captured; the source of truth for their contents is the IaC repository (``Watchlists/*.csv``).

$(Format-Table -Items $wlRows -Columns 'Name','Freshness','Age (days)','Updated','Enabled rules','Maintained by','Search key','Provider')

## Used by analytics rules

Cross-reference of every captured watchlist against every Scheduled / NRT analytics rule's KQL ``query`` field. Each row lists the rules that call ``_GetWatchlist("<alias>")`` against this watchlist. A "_(no analytics rule references)_" row doesn't necessarily mean the watchlist is orphaned (hunting queries, workbooks and ad-hoc KQL aren't scanned), but no rule reference is a useful signal that the watchlist may be stale.

$(Format-Table -Items $wlUsageRows -Columns 'Alias','RuleCount','Rules')
$brokenRefsBlock

## Descriptions

$(Format-Table -Items $wlDescRows -Columns 'Name','Description' -EmptyMessage '_No watchlist has a description._')

[Microsoft Sentinel watchlists overview (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/watchlists)
[``_GetWatchlist`` function reference (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/watchlists-queries)
"@)

$arRows = $autoRules | ForEach-Object {
    [pscustomobject]@{ Name = $_.properties.displayName; Order = $_.properties.order; Enabled = if ($_.properties.triggeringLogic.isEnabled) { 'Yes' } else { 'No' } }
}
$playbooks = Read-RawArray 'playbooks.json'
$miAssignments = Read-RawArray 'rbac-playbook-mi.json'
# Note on schema: the Microsoft.Logic/workflows ?api-version=2016-06-01 list
# response returns PascalCase properties at the top level (Name, State,
# Version, ProvisioningState, Definition, etc.) — NOT the nested
# `{ properties: { state, ... } }` shape the docs imply. Defensive lookups
# below try both paths so the renderer works against the live API response
# AND against fixtures shaped to the documented schema.
$pbRows = $playbooks | ForEach-Object {
    $pbName = if ($_.PSObject.Properties.Name -contains 'Name') { $_.Name } else { $_.name }
    $pbState = if ($_.PSObject.Properties.Name -contains 'State') { $_.State }
               elseif ($_.PSObject.Properties.Name -contains 'properties' -and $_.properties) { $_.properties.state }
               else { '' }
    # Closure-scoping note: `Where-Object { $_.Playbook -eq $_.Name }` is
    # ambiguous because $_ inside Where-Object refers to the miAssignment.
    # Capture the outer playbook name first.
    $mi = $miAssignments | Where-Object { $_.Playbook -eq $pbName } | Select-Object -First 1
    $roles = if ($mi -and @($mi.WorkspaceRoles).Count -gt 0) {
        @($mi.WorkspaceRoles) -join ', '
    } elseif ($mi) {
        '_(MI present, no workspace roles)_'
    } else {
        '_(no managed identity)_'
    }
    [pscustomobject]@{
        Name           = $pbName
        State          = $pbState
        WorkspaceRoles = $roles
    }
}
$autoCount = $arRows.Count
$pbCount   = $pbRows.Count
# Run health from playbook-runs.json (7-day window, written by the collector
# per enabled workflow).
$pbRunRows = @($playbookRuns | ForEach-Object {
    [pscustomobject]@{
        Playbook       = $_.Playbook
        Runs7d         = [int](_RendererNumber $_.Runs7d)
        Failed7d       = [int](_RendererNumber $_.Failed7d)
        LastRunStatus  = $_.LastRunStatus
        LastFailureUtc = Format-DateUtc $_.LastFailureUtc
        Note           = if ($_.PSObject.Properties['Note'] -and $_.Note) { [string]$_.Note } else { '' }
    }
} | Sort-Object -Property Failed7d -Descending)
$pbUnavailable = @($pbRunRows | Where-Object { $_.LastRunStatus -eq 'Unavailable' }).Count
$pbRunsTotal = 0; $pbFailedTotal = 0
foreach ($r in $pbRunRows) { $pbRunsTotal += $r.Runs7d; $pbFailedTotal += $r.Failed7d }
$pbFailingCount = @($pbRunRows | Where-Object { $_.Failed7d -gt 0 }).Count
$pbRunsWarning = if ($pbFailingCount -gt 0) {
    "> **$pbFailingCount playbook(s) had failed runs in the last {lookback}.** A failing playbook is a response step that is quietly not happening; [SAC-AUT-02] carries the detail.`n"
} else { '' }
$pbRunsPie = if ($pbRunsTotal -gt 0) {
@"
``````mermaid
pie showData title Playbook runs by outcome ({lookback-d})
    "Succeeded" : $($pbRunsTotal - $pbFailedTotal)
    "Failed" : $pbFailedTotal
``````
"@
} else { '' }
# Automation opportunities: incident titles that are frequent, close fast
# or close mostly as false positives, with a suggested response per title
# family. The title-to-action map is ported from the health check
# contributed by thinkndle.
$autoPlaybookMap = @(
    @{ Pattern = 'brute.?force|password.?spray|failed.?(sign|log).?in'; Action = 'Disable the account on threshold, require an MFA reset, notify IAM and tag the incident as identity attack'; Playbook = 'Disable-AADUser / Confirm-AADRiskyUser' }
    @{ Pattern = 'impossible travel|atypical travel|anomalous (sign|log).?in'; Action = 'Trigger an MFA challenge, revoke sessions, raise the Entra ID Protection risk and notify the manager'; Playbook = 'Block-AADUser-Sessions' }
    @{ Pattern = 'phish|suspicious mail|mail.?flow'; Action = 'Soft-delete similar messages through Defender for Office 365, block the sender, scan clicked URLs and isolate affected devices'; Playbook = 'ZAP-Phish-Mail / Defender-Submission' }
    @{ Pattern = 'malware|ransom|trojan|suspicious process'; Action = 'Isolate the device through Defender for Endpoint, run a full scan, block the file hash as a custom indicator and open an IR ticket'; Playbook = 'Isolate-MDEDevice' }
    @{ Pattern = 'data exfil|dlp|mass download|unusual upload'; Action = 'Suspend the session, block egress at the proxy, restrict sharing and escalate to the DLP team'; Playbook = 'Block-AADUser + Restrict-Sharing' }
    @{ Pattern = 'lateral movement|pass.?the.?hash|kerberoast|golden ticket'; Action = 'Isolate the source host, reset affected service accounts and review a krbtgt rotation'; Playbook = 'Isolate-Host + Reset-Account' }
    @{ Pattern = 'privilege escal|added to (admin|privileged)|role assign'; Action = 'Revert the role assignment outside a change window, notify the PIM owner and require a ticket reference'; Playbook = 'Remove-AADRole' }
    @{ Pattern = 'token theft|refresh token|primary refresh'; Action = 'Revoke refresh tokens, force re-authentication with MFA and audit OAuth grants'; Playbook = 'Revoke-AADUserTokens' }
    @{ Pattern = 'c2|command.?and.?control|beacon|dns tunneling'; Action = 'Isolate the device, sinkhole the domain in DNS and block the indicator at the firewall and proxy'; Playbook = 'Isolate-MDEDevice + Block-IoC' }
    @{ Pattern = 'defender|av disabled|tamper'; Action = 'Isolate the device, re-enable antivirus through Intune and escalate to the endpoint team'; Playbook = 'Isolate-MDEDevice' }
    @{ Pattern = 'guest|external user|b2b'; Action = 'Disable the guest pending review, audit external sharing and notify identity governance'; Playbook = 'Block-AADUser' }
    @{ Pattern = 'deprecated|legacy auth|basic auth'; Action = 'Block legacy authentication with Conditional Access and notify the owner of the affected app or account'; Playbook = 'Enforce-CAPolicy' }
)
$autoOppRows = @(Read-RawArray 'incident-title-stats.json' | Where-Object { $_ } | ForEach-Object {
    $title = [string](_RProp $_ 'Title' '')
    $total = _RendererNumber (_RProp $_ 'Total' 0); $closed = _RendererNumber (_RProp $_ 'Closed' 0)
    $fast = _RendererNumber (_RProp $_ 'ClosedWithinHour' 0); $fp = _RendererNumber (_RProp $_ 'FP' 0)
    $signal = if ($closed -gt 0 -and $fp / $closed -ge 0.5) { 'Mostly false positive' } elseif ($closed -gt 0 -and $fast / $closed -ge 0.5) { 'Fast-closing' } else { 'Volume' }
    $match = $autoPlaybookMap | Where-Object { $title -match $_.Pattern } | Select-Object -First 1
    [pscustomobject]@{
        Title = $title; Severity = [string](_RProp $_ 'Severity' ''); Total = [int]$total; Closed = [int]$closed
        AvgMinsToClose = _RProp $_ 'AvgMinsToClose' ''; ClosedWithinHour = [int]$fast; FP = [int]$fp; TP = [int](_RendererNumber (_RProp $_ 'TP' 0))
        Signal = $signal
        SuggestedAutomation = if ($match) { $match.Action } elseif ($signal -eq 'Mostly false positive') { 'Tune the rule or auto-close with a classification and comment through an automation rule' } else { 'Automation rule to assign, tag and enrich (TI, watchlists), then close on a verified benign pattern' }
        Playbook = if ($match) { $match.Playbook } else { 'Generic-Enrich-And-Close' }
    }
} | Sort-Object -Property @{ Expression = 'Total'; Descending = $true })
$autoOppCaptured = Test-Path -LiteralPath (Join-Path $rawRoot 'incident-title-stats.json')
# The alert-to-response chain as data for the SharePoint graphic: the target
# shape's steps by phase, each marked where a fired finding says this
# workspace is missing it or has it at risk.
$chainState = { param([string]$Id, [string]$State) if ($script:FiredFindingIds.ContainsKey($Id)) { [ordered]@{ state = $State; finding = $Id } } else { [ordered]@{ state = ''; finding = '' } } }
$chainStep = { param([int]$N, [string]$Actor, [string]$Target, [string]$Action, $Flag)
    $s = [ordered]@{ n = $N; actor = $Actor; target = $Target; action = $Action; state = ''; finding = '' }
    if ($Flag) { $s.state = $Flag.state; $s.finding = $Flag.finding }
    $s
}
$aut01 = & $chainState 'SAC-AUT-01' 'missing'
$responseChainVisualLine = Format-VisualLine -Kind 'response-chain' -Data ([ordered]@{ phases = @(
    [ordered]@{ name = 'Ingest'; figure = "$(@($connectors).Count) data connectors"; steps = @(
        (& $chainStep 1 'Data source' 'DCR / Logs Ingestion' 'Event sent' $null),
        (& $chainStep 2 'DCR / Logs Ingestion' 'Workspace table' 'Ingested after transform, about 5 minutes' $null)) }
    [ordered]@{ name = 'Detect'; figure = "$($enabledRules.Count) enabled analytics rules"; steps = @(
        (& $chainStep 3 'Analytics rule' 'Workspace table' 'KQL query on a schedule' $null),
        (& $chainStep 4 'Analytics rule' 'Incident' 'Incident created' $null)) }
    [ordered]@{ name = 'Automate'; figure = "$autoCount automation rules, $pbCount playbooks"; steps = @(
        (& $chainStep 5 'Incident' 'Automation rule' 'Trigger: incident created' $null),
        (& $chainStep 6 'Automation rule' 'Incident' 'Assign owner, tag tactic, set Active' $aut01),
        (& $chainStep 7 'Automation rule' 'Playbook' 'Run playbook' $aut01),
        (& $chainStep 8 'Playbook' 'Incident' 'Add an enrichment comment' $aut01)) }
    [ordered]@{ name = 'Notify'; figure = ''; steps = @(
        (& $chainStep 9 'Playbook' 'Microsoft Teams' 'Post to the SOC channel' (& $chainState 'SAC-AUT-05' 'risk')),
        (& $chainStep 10 'Microsoft Teams' 'SOC analyst' 'Notification' $null)) }
    [ordered]@{ name = 'Respond'; figure = ''; steps = @(
        (& $chainStep 11 'SOC analyst' 'Incident' 'Acknowledge and investigate' (& $chainState 'SAC-INC-05' 'risk'))) }
) })
Write-Section '60-automation-rules-playbooks.md' (@"
$(Format-Banner -Title "Automation Rules and Playbooks")

**$autoCount automation rule(s) · $pbCount playbook(s)** on this workspace.

## Alert-to-response chain: the target shape

The handoff path a response chain enriched by automation follows, from ingestion to the analyst, drawn against this workspace. A step this workspace is missing or has at risk names the finding behind it: steps 6 to 8 need automation rules ([SAC-AUT-01]), step 9 needs the playbook's managed identity role ([SAC-AUT-05]) and step 11 needs analysts to acknowledge incidents ([SAC-INC-05]).

``````mermaid
sequenceDiagram
$responseChainVisualLine
    autonumber
    participant DS as Data source
    participant DCR as DCR / Logs Ingest
    participant Tbl as Workspace table
    participant Rule as Analytics rule
    participant Inc as Incident
    participant Auto as Automation rule
    participant PB as Playbook
    participant Teams as MS Teams
    participant SOC as SOC analyst

    DS->>DCR: Event
    DCR->>Tbl: Ingest (after transform)
    Note over Tbl: ~5 min ingestion latency
    Rule->>Tbl: KQL query on schedule
    Rule-->>Inc: Create incident
    Inc->>Auto: Trigger: incident created
    Auto->>Inc: Assign owner, tag tactic, set Active
    Auto->>PB: Run playbook
    PB->>Inc: Add enrichment comment
    PB->>Teams: Post to SOC channel
    Teams-->>SOC: Notification
    SOC->>Inc: Acknowledge + investigate
``````

## Automation rules

$(Format-Table -Items $arRows -Columns 'Name','Order','Enabled')

## Playbooks (Logic Apps)

$(Format-Table -Items $pbRows -Columns 'Name','State','WorkspaceRoles')

## Playbook runs (last {lookback-d})

$pbRunsWarning
$pbRunsPie

$(if ($pbUnavailable -gt 0) { "_Run history could not be read for $pbUnavailable playbook(s) (LastRunStatus 'Unavailable'); their counts are not zero, they are unknown._`n" })
$(Format-Table -Items $pbRunRows -Columns 'Playbook','Runs7d','Failed7d','LastRunStatus','LastFailureUtc','Note')

## Automation opportunities (incident titles, last {lookback-d})

Incident titles seen five or more times in {lookback}, with how they close. "Fast-closing" (half or more closed within an hour) and "Mostly false positive" titles are the ones an automation rule or playbook can take off the analysts: enrich, classify and close the benign pattern, or respond automatically where the title maps to a known response. The suggested automation is a starting point per title family, not a prescription.

$(if (-not $autoOppCaptured) { '_Not captured in this run (``incident-title-stats.json`` is absent); re-run the collector to populate it._' } elseif ($autoOppRows.Count -eq 0) { '_No incident title reached five incidents in the last {lookback}._' } else { Format-Table -Items $autoOppRows -Columns 'Title','Severity','Total','Closed','AvgMinsToClose','ClosedWithinHour','FP','TP','Signal','SuggestedAutomation','Playbook' })

[Sentinel automation (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/automation/automate-responses-with-playbooks) · [Monitor automation health](https://learn.microsoft.com/azure/sentinel/monitor-automation-health)
"@)

$contentPackages = Read-RawArray 'content-packages.json'
$contentCatalogue = Read-RawArray 'content-product-packages.json'
$repos           = Read-RawArray 'repositories.json'

# Index catalogue versions by contentId so installed packages can join for
# "update available" detection.
$catalogueByContentId = @{}
foreach ($p in $contentCatalogue) {
    $cid = $p.properties.contentId
    if ($cid) { $catalogueByContentId[$cid] = $p }
}

# Dotted versions compare numerically (3.0.10 is newer than 3.0.9); a
# version [version] cannot read compares as text.
function _CompareVersion([string]$A, [string]$B) {
    $va = $null; $vb = $null
    if ([version]::TryParse($A, [ref]$va) -and [version]::TryParse($B, [ref]$vb)) { return $va.CompareTo($vb) }
    return [string]::CompareOrdinal($A, $B)
}
# One row per installed package with its status against the catalogue:
# Deprecated or Not in catalogue (no more updates), Update available, or Up
# to date; those needing attention first. With no catalogue capture there
# is nothing to compare, so the status stays blank.
$cpStatusRank = @{ 'Deprecated' = 0; 'Not in catalogue' = 1; 'Update available' = 2; 'Up to date' = 3; '' = 4 }
$cpRows = @($contentPackages | Where-Object { $_ } | ForEach-Object {
    $installed = [string]$_.properties.version
    $cid = $_.properties.contentId
    $cat = if ($cid -and $catalogueByContentId.ContainsKey($cid)) { $catalogueByContentId[$cid] } else { $null }
    $latest = if ($cat) { [string]$cat.properties.version } else { '' }
    $deprecated = $cat -and $cat.properties.PSObject.Properties['isDeprecated'] -and [string]$cat.properties.isDeprecated -eq 'true'
    $status = if ($contentCatalogue.Count -eq 0) { '' }
        elseif (-not $cat) { 'Not in catalogue' }
        elseif ($deprecated) { 'Deprecated' }
        elseif ($latest -and $installed -and (_CompareVersion $installed $latest) -lt 0) { 'Update available' }
        else { 'Up to date' }
    [pscustomobject]@{
        Name      = $_.properties.displayName
        Installed = $installed
        Latest    = $latest
        Status    = $status
        Source    = $_.properties.source.kind
    }
} | Sort-Object @{ Expression = { $cpStatusRank[[string]$_.Status] } }, Name)
$cpUpdates = @($cpRows | Where-Object Status -EQ 'Update available').Count
$cpRetired = @($cpRows | Where-Object { $_.Status -in 'Deprecated', 'Not in catalogue' }).Count
$omsSolutionRows = @(Read-RawArray 'solutions-installed.json' | Where-Object { $_ } | ForEach-Object {
    $plan = if ($_.PSObject.Properties['plan'] -and $_.plan) { $_.plan } else { $null }
    $sp = if ($_.PSObject.Properties['properties'] -and $_.properties) { $_.properties } else { $null }
    [pscustomobject]@{
        Name         = $_.name
        Product      = if ($plan -and $plan.PSObject.Properties['product']) { $plan.product } else { '' }
        Publisher    = if ($plan -and $plan.PSObject.Properties['publisher']) { $plan.publisher } else { '' }
        Provisioning = if ($sp -and $sp.PSObject.Properties['provisioningState']) { $sp.provisioningState } else { '' }
        LastModified = if ($sp -and $sp.PSObject.Properties['lastModifiedTime']) { Format-DateUtc $sp.lastModifiedTime } else { '' }
    }
})
$repoRows = $repos | ForEach-Object {
    [pscustomobject]@{ Name = $_.properties.displayName; Type = $_.properties.repoType; Url = $_.properties.repository.url }
}
# Content-source distribution for the headline pie.
$sourceCounts = @{}
foreach ($p in $cpRows) {
    $s = if ($p.Source) { [string]$p.Source } else { 'Custom / unknown' }
    if (-not $sourceCounts.ContainsKey($s)) { $sourceCounts[$s] = 0 }
    $sourceCounts[$s]++
}
$sourcePieRows = $sourceCounts.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}

# The installed packages as proportions for the SharePoint graphic: how
# many are current and how many need attention, and where they come from.
$cpStatusCount = { param([string]$S) @($cpRows | Where-Object { [string]$_.Status -eq $S }).Count }
$sourceTone = @{ Solution = 'info'; Community = 'violet'; Standalone = 'teal' }
$contentHubVisualLine = Format-VisualLine -Kind 'meters' -Data ([ordered]@{ meters = @(
    [ordered]@{ title = 'Installed packages'; caption = 'Against the Content Hub catalogue'; total = $cpRows.Count; parts = @(
        [ordered]@{ label = 'Up to date'; value = (& $cpStatusCount 'Up to date'); tone = 'ok' }
        [ordered]@{ label = 'Update available'; value = (& $cpStatusCount 'Update available'); tone = 'warn' }
        [ordered]@{ label = 'Deprecated'; value = (& $cpStatusCount 'Deprecated'); tone = 'bad' }
        [ordered]@{ label = 'Not in catalogue'; value = (& $cpStatusCount 'Not in catalogue'); tone = 'rose' }
        [ordered]@{ label = 'Not checked'; value = (& $cpStatusCount ''); tone = 'neutral' }
    ) }
    [ordered]@{ title = 'By source'; caption = 'Who publishes each package'; total = $cpRows.Count; parts = @($sourceCounts.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | ForEach-Object {
        [ordered]@{ label = [string]$_.Key; value = [int]$_.Value; tone = $(if ($sourceTone.ContainsKey([string]$_.Key)) { $sourceTone[[string]$_.Key] } else { 'neutral' }) }
    }) }
) })

Write-Section '70-content-hub.md' (@"
$(Format-Banner -Title "Content Hub and Repositories")

## Source mix

``````mermaid
pie showData title Installed Content Hub packages by source
$contentHubVisualLine
$($sourcePieRows -join [Environment]::NewLine)
``````

<!-- bp:shown-in-graphic -->

**$($cpRows.Count)** Content Hub package(s) installed  ·  **$cpUpdates** with an update available  ·  **$cpRetired** deprecated or no longer listed  ·  **$($sourceCounts.Count)** source kind(s)

## Solutions installed

Every installed package against the Content Hub catalogue, those needing attention first. **Update available**: the catalogue has a newer version; update it from Content Hub to get the latest rules, parsers and workbooks. **Deprecated** or **Not in catalogue**: it no longer receives updates, and [SAC-DET-13] fires on either. **Up to date**: the installed version is the latest.

$(Format-Table -Items $cpRows -Columns 'Name','Installed','Latest','Status','Source')

## Repositories

$(Format-Table -Items $repoRows -Columns 'Name','Type','Url')

## Legacy management solutions

``Microsoft.OperationsManagement/solutions`` resources linked to the workspace: the pre-Content-Hub way Sentinel (``SecurityInsights``), Security and other packs were installed. They are harmless once Content Hub is in use, but they are the first place to look when a solution appears installed that Content Hub does not list.

$(Format-Table -Items $omsSolutionRows -Columns 'Name','Product','Publisher','Provisioning','LastModified')

[Sentinel solutions (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/sentinel-solutions)
"@)

# ---------------------------------------------------------------------------
# Section: 80 — workspace
# ---------------------------------------------------------------------------
$features = $workspace.properties.features
$wsCreated = $workspace.properties.createdDate
$wsAgeDays = if ($wsCreated) {
    [int]([math]::Floor(((Get-Date).ToUniversalTime() - [datetime]$wsCreated).TotalDays))
} else { $null }
$wsAgeWarning = if ($null -ne $wsAgeDays -and $wsAgeDays -lt (Get-BpWindow).Days) {
    " _(The workspace is younger than the {lookback} the captures read, so figures over that window cover only its life so far.)_"
} else { '' }
$wsDefaultDcr = $null
if ($workspace.properties.PSObject.Properties.Name -contains 'defaultDataCollectionRuleResourceId') {
    $wsDefaultDcr = $workspace.properties.defaultDataCollectionRuleResourceId
}
# Timeline-line dates. wsCreatedShort = yyyy-MM-dd for the workspace
# creation event in the timeline diagram. Format-DateUtc returns
# "yyyy-MM-dd HH:mm" — the timeline expects just date so we split on space.
$wsCreatedShort = if ($wsCreated) { (Format-DateUtc $wsCreated).Split(' ')[0] } else { 'unknown' }
$todayShort = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)

# Build the workspace + platform history timeline as a sorted list.
# Mermaid `timeline` renders entries in source order — without an
# explicit chronological sort the entries appeared in the order they
# were declared in the heredoc, not by date. Each entry is a hashtable
# with Date (yyyy-MM-dd) and Lines (one or more colon-suffixed strings).
# Platform deprecation events pre-dating the workspace's creation are
# filtered out — they're irrelevant historical context for a new
# workspace (e.g. a 2026-created workspace doesn't need an MMA-retired
# bullet from 2024).
$timelineEvents = @()
$timelineEvents += [pscustomobject]@{
    Date  = $wsCreatedShort
    Lines = @(
        "Workspace created ($($workspace.properties.sku.name), $($workspace.properties.retentionInDays)d retention)",
        "First captured connector inventory"
    )
}
# Tables-in-use: operational subset (tables that have received billable
# data in 90 days, plus CustomLog tables). The 800+ Microsoft-defined
# schemas the workspace never ingested are catalogue, not deployment —
# surfaced as a separate number to avoid misreading "836 tables in
# catalogue" as "836 tables in use".
$timelineEvents += [pscustomobject]@{
    Date  = $todayShort
    Lines = @(
        "This documentation generated ($wsAgeDays-day-old workspace)",
        "$($enabledRules.Count) rules enabled · $($connectors.Count) connectors · $($operationalTables.Count) tables receiving data ($($workspaceTables.Count) in catalogue)"
    )
}

if ($wsCreatedShort -ne 'unknown') {
    $timelineEvents = @($timelineEvents | Where-Object { $_.Date -ge $wsCreatedShort })
}
$timelineEvents = @($timelineEvents | Sort-Object Date)

$timelineBody = ($timelineEvents | ForEach-Object {
    $lines = @($_.Lines)
    $first = "    $($_.Date) : $($lines[0])"
    if ($lines.Count -gt 1) {
        $rest = @($lines[1..($lines.Count - 1)] | ForEach-Object { "                    : $_" })
        ($first + [Environment]::NewLine + ($rest -join [Environment]::NewLine))
    } else { $first }
}) -join [Environment]::NewLine

# The workspace's own history as data for the SharePoint graphic. Platform
# retirements live on 02-deprecated-legacy-features.md and are not repeated.
$workspaceAgeVisualLine = Format-VisualLine -Kind 'workspace-age' -Data ([ordered]@{
    created         = $(if ($wsCreatedShort -ne 'unknown') { $wsCreatedShort } else { $null })
    today           = $todayShort
    ageDays         = $(if ($null -ne $wsAgeDays) { [int]$wsAgeDays } else { $null })
    sku             = [string]$workspace.properties.sku.name
    retentionDays   = [int]$workspace.properties.retentionInDays
    rulesEnabled    = $enabledRules.Count
    connectors      = @($connectors).Count
    tablesReceiving = @($operationalTables).Count
    tablesCatalogue = @($workspaceTables).Count
})

$wsBody = @"
$(Format-Banner -Title "Workspace Inventory")

## Workspace history

``````mermaid
timeline
$workspaceAgeVisualLine
    title Workspace history: $WorkspaceName
$timelineBody
``````

When the workspace was created and on what terms, and what it holds today. Platform retirements and their dates are on [02-deprecated-legacy-features.md](02-deprecated-legacy-features.md).

## Provenance

| Property | Value |
|---|---|
| Resource ID | ``$($workspace.id)`` |
| Created | $(Format-DateUtc $wsCreated) |
| Age | $(if ($null -ne $wsAgeDays) { "$wsAgeDays days$wsAgeWarning" } else { '_(unknown)_' }) |
| Default DCR | $(if ($wsDefaultDcr) { "``$wsDefaultDcr``" } else { '_(none set on the workspace)_' }) |

## SKU and pricing

| Property | Value |
|---|---|
| SKU name | ``$($workspace.properties.sku.name)`` |
| Capacity reservation level | $(if ($workspace.properties.sku.capacityReservationLevel) { "$($workspace.properties.sku.capacityReservationLevel) GB/day" } else { '_(n/a)_' }) |
| Default retention | $($workspace.properties.retentionInDays) days |
| Daily cap | $(if ($workspace.properties.workspaceCapping.dailyQuotaGb -eq -1 -or $null -eq $workspace.properties.workspaceCapping.dailyQuotaGb) { 'Unlimited' } else { "$($workspace.properties.workspaceCapping.dailyQuotaGb) GB" }) |

### Available service tiers

$( $availableTiers = Read-RawArray 'available-service-tiers.json'
   $tierRows = $availableTiers | ForEach-Object {
       [pscustomobject]@{
           SkuName            = $_.serviceTier
           CapacityReservation = if ($_.PSObject.Properties.Name -contains 'capacityReservationLevel') { $_.capacityReservationLevel } else { '' }
           Enabled            = $_.enabled
       }
   }
   Format-Table -Items $tierRows -Columns 'SkuName','CapacityReservation','Enabled' )

## Usage telemetry

$( $usage = Read-RawArray 'workspace-usage.json' | Select-Object -First 1
   if ($usage) {
@"
| Window | Total GB | Billable GB |
|---|---:|---:|
| Last {lookback} (sum) | $($usage.TotalGB) | $($usage.BillableTotalGB) |
| Last {lookback} (peak day) | $($usage.PeakDailyGB) | $($usage.BillablePeakDailyGB) |
| Last {lookback} (avg/day) | _(n/a)_ | $($usage.BillableAvgDailyGB) |
"@
   } else { '_No usage telemetry captured._' } )
$usageTrendBlock

## Networking + replication

| Property | Value |
|---|---|
| Public ingestion | ``$($workspace.properties.publicNetworkAccessForIngestion)`` |
| Public query | ``$($workspace.properties.publicNetworkAccessForQuery)`` |
| Replication enabled | $(if ($null -eq $workspace.properties.replication -or $null -eq $workspace.properties.replication.enabled) { 'False (not configured)' } else { [string]$workspace.properties.replication.enabled }) |
| Replication location | $(if ($workspace.properties.replication -and $workspace.properties.replication.location) { "``$($workspace.properties.replication.location)``" } else { '_(n/a)_' }) |

## Resilience summary

$( $wsProps80 = _RProp $workspace 'properties'
   $repl = _RProp $wsProps80 'replication'
   $replOn = [bool](_RProp $repl 'enabled' $false)
   $plsr = @(_RProp $wsProps80 'privateLinkScopedResources' @()).Count
   $capGb = _RProp (_RProp $wsProps80 'workspaceCapping') 'dailyQuotaGb' -1
   $identityType = [string](_RProp (_RProp $workspace 'identity') 'type' 'None')
   $onb80 = @(Read-RawArray 'onboarding-state.json' | Where-Object { $_ }) | Select-Object -First 1
   $cmk80 = _RProp (_RProp $onb80 'properties') 'customerManagedKey'
   $locks80 = @(Read-RawArray 'workspace-locks.json' | Where-Object { $_ }).Count
   $resRows = @(
       [pscustomobject]@{ Control = 'Workspace replication'; State = $(if ($replOn) { "Enabled (" + [string](_RProp $repl 'location' '?') + ")" } else { 'Not enabled' }); Note = 'Cross-region replica for regional outages; [SAC-PLT-05]' }
       [pscustomobject]@{ Control = 'Private Link scoped resources'; State = $(if ($plsr -gt 0) { "$plsr linked" } else { 'None' }); Note = 'AMPLS links on the workspace; [SAC-PLT-06] covers public access' }
       [pscustomobject]@{ Control = 'Public ingestion / query'; State = "$(_RProp $wsProps80 'publicNetworkAccessForIngestion' 'Enabled') / $(_RProp $wsProps80 'publicNetworkAccessForQuery' 'Enabled')"; Note = 'Disabled on both means every path goes through Private Link' }
       [pscustomobject]@{ Control = 'Customer-managed key'; State = $(if ($null -eq $cmk80) { 'Unknown (onboarding state not captured)' } elseif ($cmk80) { 'Yes' } else { 'No (platform-managed keys)' }); Note = 'From the Sentinel onboarding state; CMK also needs a dedicated cluster' }
       [pscustomobject]@{ Control = 'Managed identity'; State = $identityType; Note = 'Identity on the workspace resource itself' }
       [pscustomobject]@{ Control = 'Daily cap'; State = $(if ($null -eq $capGb -or [double]$capGb -eq -1) { 'Unlimited' } else { "$capGb GB / day" }); Note = 'A cap protects spend and drops data once hit; [SAC-LOG-03]' }
       [pscustomobject]@{ Control = 'Resource locks'; State = $(if ($locks80 -gt 0) { "$locks80 lock(s)" } else { 'None' }); Note = 'CanNotDelete on the workspace; [SAC-GOV-03]' }
   )
   Format-Table -Items $resRows -Columns 'Control','State','Note' )

## Feature flags

| Flag | Value |
|---|---|
| disableLocalAuth | $(Format-FeatureFlag $features 'disableLocalAuth') |
| enableLogAccessUsingOnlyResourcePermissions | $(Format-FeatureFlag $features 'enableLogAccessUsingOnlyResourcePermissions') |
| enableDataExport | $(Format-FeatureFlag $features 'enableDataExport') |
| immediatePurgeDataOn30Days | $(Format-FeatureFlag $features 'immediatePurgeDataOn30Days') |
| clusterResourceId | $(if ($features -and $features.PSObject.Properties.Name -contains 'clusterResourceId' -and $features.clusterResourceId) { "``$($features.clusterResourceId)``, see [82-dedicated-cluster.md](82-dedicated-cluster.md)" } else { '_(none)_' }) |

## Sentinel onboarding

$( $onboarding = @(Read-RawArray 'onboarding-state.json' | Where-Object { $_ }) | Select-Object -First 1
   if ($onboarding) {
       $obProps = if ($onboarding.PSObject.Properties['properties']) { $onboarding.properties } else { $null }
       $cmk = if ($obProps -and $obProps.PSObject.Properties['customerManagedKey'] -and $null -ne $obProps.customerManagedKey) { [string]$obProps.customerManagedKey } else { 'not set (platform-managed keys)' }
@"
| Property | Value |
|---|---|
| Onboarding state resource | ``$($onboarding.name)`` |
| Customer-managed key | $cmk |
"@
   } else { '_No Sentinel onboarding state resource was captured; either Sentinel is not enabled on this workspace or the identity cannot read it._' } )

## Resource locks

$( $wsLocks = Read-RawArray 'workspace-locks.json'
   $lockRows = $wsLocks | ForEach-Object {
       [pscustomobject]@{ Name = $_.name; Level = $_.properties.level; Notes = $_.properties.notes }
   }
   Format-Table -Items $lockRows -Columns 'Name','Level','Notes' )

A non-empty list of locks here is a deletion-protection signal. ``CanNotDelete`` blocks resource deletion; ``ReadOnly`` blocks both modification and deletion.

[Workspace design (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/logs/workspace-design) · [Manage access](https://learn.microsoft.com/azure/azure-monitor/logs/manage-access) · [Replication](https://learn.microsoft.com/azure/azure-monitor/logs/workspace-replication) · [Resource locks](https://learn.microsoft.com/azure/azure-resource-manager/management/lock-resources)
"@
Write-Section '80-workspace.md' $wsBody

# ---------------------------------------------------------------------------
# Section: 81 — table plans + retention
# ---------------------------------------------------------------------------
$tableSchemaByName = @{}
foreach ($t in $workspaceTables) { $tableSchemaByName[$t.name] = $t }

# Build rows for the OPERATIONAL set only (populated tables + custom logs).
# The full workspace catalogue (~800 entries) is summarised separately so a
# reader doesn't have to scroll through 750 unpopulated Microsoft schemas to
# find the 50 tables that actually matter.
$tableRows = foreach ($t in $operationalTables) {
    $name = $t.name
    $usage = $tablesWithData | Where-Object { $_.DataType -eq $name } | Select-Object -First 1
    [pscustomobject]@{
        Name = $name
        Plan = $t.properties.plan
        Interactive = $t.properties.retentionInDays
        Total = $t.properties.totalRetentionInDays
        Archive = $t.properties.archiveRetentionInDays
        Type = $t.properties.schema.tableType
        Gb90d = if ($usage) { [math]::Round([double]$usage.BillableLast90d, 2) } else { 0 }
        Last24h = if ($usage -and [double]$usage.BillableLast24h -gt 0) { 'Yes' } else { '' }
        LastIngested = if ($usage) { Format-DateUtc $usage.LastIngested } else { '' }
    }
}

$active  = @($tableRows | Where-Object { $_.Last24h })
$silent  = @($tableRows | Where-Object {
    # Had data in 90d window (LastIngested set) but nothing in last 24h —
    # likely connector breakage. Excludes orphan custom tables that never
    # received data.
    -not $_.Last24h -and $_.LastIngested
})
# Orphan = custom log table with NO ingestion in the last 90 days. We
# deliberately don't flag Microsoft pre-defined tables as orphans because
# their schema exists by default in every workspace.
$orphans = @($tableRows | Where-Object { -not $_.LastIngested -and $_.Type -eq 'CustomLog' })

# Plan summary covers operational tables only.
$gbByPlan = $tableRows | Group-Object Plan | ForEach-Object {
    [pscustomobject]@{
        Plan = $_.Name
        Tables = $_.Count
        Gb90d = [math]::Round(($_.Group | Measure-Object Gb90d -Sum).Sum, 2)
    }
}

# Catalogue summary: Microsoft pre-defined tables that never received
# data. Most workspaces carry hundreds of these; every name is listed.
$catalogueOnly = @($workspaceTables | Where-Object {
    ($_.properties.schema.tableType -ne 'CustomLog') -and
    (-not $populatedTableNames.ContainsKey($_.name))
})
$catalogueOnlyRows = @($catalogueOnly | ForEach-Object {
    $name = [string]$_.name
    [pscustomobject]@{
        Table     = $name
        Connector = $(if ($connectorCatalogue) { Get-TableConnectorLabel -Catalogue $connectorCatalogue -Table $name -ConnectedIds $connectedConnectorIds } else { '' })
    }
} | Sort-Object Table)

# Detection coverage per operational table, from the enabled rules' table
# references. Empty when the collector did not compute the mapping.
$rulesPerTable = @{}
foreach ($ref in $ruleTableRefs) {
    if ($ref.Enabled -ne $true) { continue }
    foreach ($t in @($ref.Tables)) {
        if (-not $t) { continue }
        if (-not $rulesPerTable.ContainsKey($t)) { $rulesPerTable[$t] = 0 }
        $rulesPerTable[$t]++
    }
}
$customDetectionsPerTable = @{}
foreach ($cd in $customDetectionRefs) {
    if (-not $cd -or (_RProp $cd 'Enabled' $false) -ne $true) { continue }
    foreach ($t in @(_RProp $cd 'Tables' @())) { if ($t) { if (-not $customDetectionsPerTable.ContainsKey($t)) { $customDetectionsPerTable[$t] = 0 }; $customDetectionsPerTable[$t]++ } }
}
$coverageRows = @($tableRows | Where-Object { $_.Gb90d -gt 0 } | ForEach-Object {
    $n = if ($rulesPerTable.ContainsKey($_.Name)) { $rulesPerTable[$_.Name] } else { 0 }
    $cdn = if ($customDetectionsPerTable.ContainsKey($_.Name)) { $customDetectionsPerTable[$_.Name] } else { 0 }
    [pscustomobject]@{ Name = $_.Name; Plan = $_.Plan; Gb90d = $_.Gb90d; Rules = $n; CustomDetections = $cdn; Coverage = if ($n -gt 0 -and $cdn -gt 0) { 'Rule and custom detection' } elseif ($n -gt 0) { 'Sentinel rule' } elseif ($cdn -gt 0) { 'Custom detection' } else { 'None' } }
} | Sort-Object -Property Gb90d -Descending)
$coverageBlock = if ($ruleTableRefs.Count -eq 0) {
    '_Table-to-rule mapping was not computed in this run._'
} else {
    Format-Table -Items $coverageRows -Columns 'Name','Plan','Gb90d','Rules','CustomDetections','Coverage'
}

# Silent tables in detail, split by whether an enabled rule reads them: a
# silent table nobody detects on is a cost question, one that rules depend
# on is a detection outage ([SAC-MON-06]).
$docNow = $(if ($run -and (_RProp $run 'CompletedAtUtc')) { ([datetime]::Parse([string]$run.CompletedAtUtc, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)).ToUniversalTime() } else { [datetime]::UtcNow })
$silentRows = @($silent | ForEach-Object {
    $name = $_.Name
    $use = @($tablesWithData | Where-Object { $_ -and (_RProp $_ 'DataType') -eq $name }) | Select-Object -First 1
    $lastRaw = _RProp $use 'LastIngested'
    $days = ''
    if ($lastRaw) { $parsed = [datetime]::MinValue; if ([datetime]::TryParse([string]$lastRaw, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { $days = [int][math]::Floor(($docNow - $parsed.ToUniversalTime()).TotalDays) } }
    $n = if ($rulesPerTable.ContainsKey($name)) { $rulesPerTable[$name] } else { 0 }
    [pscustomobject]@{ Name = $name; Plan = $_.Plan; Gb90d = $_.Gb90d; LastIngested = $_.LastIngested; DaysSilent = $days; Rules = $n; Impact = if ($n -gt 0) { 'Detection outage' } else { 'Cost only' } }
} | Sort-Object -Property @{ Expression = 'Rules'; Descending = $true }, @{ Expression = 'Gb90d'; Descending = $true })
$silentWithRules = @($silentRows | Where-Object { $_.Rules -gt 0 })
$silentDetail = if ($silentRows.Count -eq 0) { '' } else { @"

$($silentWithRules.Count) of these are read by enabled analytics rules; those rules still run on schedule and return nothing, so the detection has gone dark without an alert. The rest are cost-only questions: confirm the source was retired on purpose, then stop the collection or delete the table.

$(Format-Table -Items $silentRows -Columns 'Name','Plan','Gb90d','LastIngested','DaysSilent','Rules','Impact')
"@ }

# Classic custom tables: created through the legacy HTTP Data Collector API
# (or the MMA custom-log path) rather than a DCR. The API retires on
# 14 September 2026; every table still written through it needs a DCR
# before then. tableSubType is the authoritative marker when present.
$classicTables = @($workspaceTables | Where-Object {
    $_ -and (_RProp (_RProp (_RProp $_ 'properties') 'schema') 'tableType') -eq 'CustomLog' -and (_RProp (_RProp (_RProp $_ 'properties') 'schema') 'tableSubType') -eq 'Classic'
})
$dcrBasedCustom = @($workspaceTables | Where-Object { $_ -and (_RProp (_RProp (_RProp $_ 'properties') 'schema') 'tableSubType') -eq 'DataCollectionRuleBased' }).Count
$classicRows = @($classicTables | ForEach-Object {
    $name = [string]$_.name
    $props = _RProp $_ 'properties'
    $use = @($tablesWithData | Where-Object { $_ -and (_RProp $_ 'DataType') -eq $name }) | Select-Object -First 1
    $gb24 = _RendererNumber (_RProp $use 'BillableLast24h' 0); $gb7 = _RendererNumber (_RProp $use 'BillableLast7d' 0); $gb30 = _RendererNumber (_RProp $use 'BillableLast30d' 0); $gb90 = _RendererNumber (_RProp $use 'BillableLast90d' 0)
    $status = if ($gb24 -gt 0) { 'Active (last 24h)' } elseif ($gb7 -gt 0) { 'Active (last {recent-d})' } elseif ($gb30 -gt 0) { 'Intermittent' } elseif ($gb90 -gt 0) { 'Stale' } else { 'No data in {lookback-d}' }
    $n = if ($rulesPerTable.ContainsKey($name)) { $rulesPerTable[$name] } else { 0 }
    $action = if ($gb90 -le 0) { 'Confirm the source is retired, then delete the table' } elseif ($n -eq 0) { 'Still ingesting with no rule reading it: migrate to a DCR-based table or stop the collection' } else { 'Rules depend on it: migrate to the Logs Ingestion API and a DCR before the retirement date' }
    [pscustomobject]@{ Name = $name; Plan = [string](_RProp $props 'plan' ''); Interactive = _RProp $props 'retentionInDays' ''; Total = _RProp $props 'totalRetentionInDays' ''; Gb90d = [math]::Round($gb90, 2); LastIngested = $(if ($use) { Format-DateUtc (_RProp $use 'LastIngested') } else { '' }); Status = $status; Rules = $n; Action = $action }
} | Sort-Object -Property @{ Expression = { $_.Status -eq 'No data in {lookback-d}' } }, @{ Expression = 'Gb90d'; Descending = $true })
$classicActiveCount = @($classicRows | Where-Object { $_.Status -like 'Active*' }).Count
$classicDormantCount = @($classicRows | Where-Object { $_.Status -in @('Stale', 'No data in {lookback-d}') }).Count
$classicBlock = if ($classicRows.Count -eq 0) {
    "_No classic custom tables: every custom table in this workspace is DCR-based ($dcrBasedCustom table(s)), so nothing is exposed to the Data Collector API retirement._"
} else { @"
**$($classicRows.Count)** classic table(s): **$classicActiveCount** still ingesting, **$classicDormantCount** stale or empty, beside **$dcrBasedCustom** DCR-based custom table(s). [SAC-PLT-02] fires for the ones still receiving data.

$(Format-Table -Items $classicRows -Columns 'Name','Plan','Interactive','Total','Gb90d','LastIngested','Status','Rules','Action')
"@ }

# Plan pie inputs.
$planPieAnalytics  = ($gbByPlan | Where-Object { $_.Plan -eq 'Analytics' }  | Measure-Object -Property Tables -Sum).Sum
$planPieBasic      = ($gbByPlan | Where-Object { $_.Plan -eq 'Basic' }      | Measure-Object -Property Tables -Sum).Sum
$planPieAuxiliary  = ($gbByPlan | Where-Object { $_.Plan -eq 'Auxiliary' }  | Measure-Object -Property Tables -Sum).Sum
if (-not $planPieAnalytics) { $planPieAnalytics = 0 }
if (-not $planPieBasic)     { $planPieBasic = 0 }
if (-not $planPieAuxiliary) { $planPieAuxiliary = 0 }

$tablePlansBody = @"
$(Format-Banner -Title "Table Plans, Retention and Activity")

## Plan adoption

``````mermaid
pie showData title Operational tables by plan
    "Analytics" : $planPieAnalytics
    "Basic" : $planPieBasic
    "Auxiliary" : $planPieAuxiliary
``````

[SAC-LOG-02] flags high-volume Analytics tables that could move to Basic / Auxiliary for cost savings; this chart shows the current tier distribution at a glance.

The workspace catalogue carries every Microsoft-defined table schema regardless of whether your tenant has onboarded a source for it, typically several hundred. This section focuses on the **operational** subset: tables that have actually received data in the last {lookback} plus all custom (``CustomLog``) tables. The full catalogue counts are at the bottom.

| | |
|---|---:|
| Operational tables shown below | $($tableRows.Count) |
| Catalogue-only Microsoft schemas (never ingested, hidden) | $($catalogueOnly.Count) |
| Total tables in workspace | $($workspaceTables.Count) |

## Summary by plan

$(Format-Table -Items $gbByPlan -Columns 'Plan','Tables','Gb90d')

## Operational tables

$(Format-Table -Items ($tableRows | Sort-Object -Property Gb90d -Descending) -Columns 'Name','Plan','Interactive','Total','Archive','Type','Gb90d','Last24h','LastIngested')

## Active (received data in last 24h)

Total: **$($active.Count)** table(s).

## Silent (had data in {lookback-d}, nothing in last 24h)

Total: **$($silent.Count)** table(s), likely connector breakage.
$silentDetail

## Orphan custom tables (no data in {lookback-d})

Total: **$($orphans.Count)** custom ``_CL`` table(s): delete candidates or never-onboarded sources. Microsoft pre-defined tables without data are catalogue entries, not orphans, and are excluded from this list.

## Catalogue-only Microsoft schemas

$($catalogueOnly.Count) Microsoft pre-defined table schemas never received data in the last {lookback}. These are part of every workspace's table catalogue and don't represent a deployment problem. ``Connector`` is the data connector that would fill the table, from the connector catalogue (see [10-data-connectors.md](10-data-connectors.md)): the connectors that list it when there are at most three, otherwise how many share it; blank for a table no Content Hub connector writes.

$(Format-Table -Items $catalogueOnlyRows -Columns 'Table','Connector')

## Classic custom tables (legacy Data Collector API)

Custom tables created through the HTTP Data Collector API or the Microsoft Monitoring Agent custom-log path (``tableSubType = Classic``) rather than a data collection rule. The Data Collector API retires on 14 September 2026; a classic table that still receives data needs a DCR and the Logs Ingestion API before then, and one that rules depend on is a detection outage waiting to happen.

$classicBlock

## Tables by detection coverage

Operational tables with data in the last {lookback}, the number of enabled Sentinel analytics rules that read each one and the number of enabled Defender XDR custom detections that query it (from the Graph detection-rules capture; blank when that capture did not run). A high-volume table with no rules is cost without coverage; [28-detection-opportunities.md](28-detection-opportunities.md) lists the templates that would cover it.

$coverageBlock

Retention per table, with the workspace-level retention checks and what rolls into the lake, is in [89-retention.md](89-retention.md).

[Table plans (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/logs/logs-table-plans) · [Retention & archive](https://learn.microsoft.com/azure/azure-monitor/logs/data-retention-archive) · [Manage table tiers in Sentinel](https://learn.microsoft.com/azure/sentinel/manage-table-tiers-retention)
"@
Write-Section '81-table-plans-retention.md' $tablePlansBody

# ---------------------------------------------------------------------------
# Section: 82 — dedicated cluster
# ---------------------------------------------------------------------------
$cluster = Read-Raw 'dedicated-cluster.json'
# An empty capture ({}) means no cluster; reading it as one wrote a table of
# blanks whose empty code spans broke the table.
if ($cluster -and $cluster.PSObject.Properties['name'] -and $cluster.name) {
    $clusterBody = @"
$(Format-Banner -Title "Dedicated Cluster")

| Property | Value |
|---|---|
| Name | ``$($cluster.name)`` |
| Capacity reservation | $($cluster.properties.sku.capacity) GB/day |
| Billing type | $($cluster.properties.billingType) |
| Double encryption | $($cluster.properties.isDoubleEncryptionEnabled) |
| Availability zones | $($cluster.properties.isAvailabilityZonesEnabled) |
| CMK key vault | ``$($cluster.properties.keyVaultProperties.keyVaultUri)`` |
| Identity type | $($cluster.identity.type) |
| Associated workspaces | $(($cluster.properties.associatedWorkspaces | Measure-Object).Count) |

[Dedicated clusters (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/logs/logs-dedicated-clusters) · [Customer-managed keys](https://learn.microsoft.com/azure/azure-monitor/logs/customer-managed-keys)
"@
    Write-Section '82-dedicated-cluster.md' $clusterBody
} else {
    Write-Section '82-dedicated-cluster.md' (@"
$(Format-Banner -Title "Dedicated Cluster")

_No dedicated cluster linked to this workspace._

For workspaces sustaining > 500 GB/day, [a dedicated cluster](https://learn.microsoft.com/azure/azure-monitor/logs/logs-dedicated-clusters) unlocks cluster-level commitment pricing, customer-managed keys and availability-zone redundancy.
"@)
}

# ---------------------------------------------------------------------------
# Section: 83 — data collection
# ---------------------------------------------------------------------------
$dces = Read-RawArray 'dces.json'

# Split DCRs into in-scope (at least one LA destination targets this
# workspace) and out-of-scope (targeting other workspaces in the same
# subscription). The exporter captures DCRs at subscription scope, so
# without this filter a workspace's report lists every DCR the
# executing identity can see — even ones that have nothing to do with
# this workspace, which is confusing.
function _DcrTargetsWorkspace {
    param($Dcr, [string]$WorkspaceId)
    if (-not $WorkspaceId) { return $true }
    if (-not $Dcr.properties.PSObject.Properties.Name -contains 'destinations' -or -not $Dcr.properties.destinations) { return $false }
    if (-not $Dcr.properties.destinations.PSObject.Properties.Name -contains 'logAnalytics') { return $false }
    foreach ($d in @($Dcr.properties.destinations.logAnalytics)) {
        if ([string]::Equals([string]$d.workspaceResourceId, $WorkspaceId, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

$dcrsInScope    = @()
$dcrsOutOfScope = @()
foreach ($d in $dcrs) {
    if (_DcrTargetsWorkspace -Dcr $d -WorkspaceId $workspaceResourceId) { $dcrsInScope += $d } else { $dcrsOutOfScope += $d }
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
    [pscustomobject]@{ Name = $_.name; Location = $_.location }
}
# Topology flowchart — sourced from the synthesised $effective view
# rather than $connectors alone, so DCR-driven and diagnostic-settings-
# driven ingestion (the bulk of any modern workspace) appears too.
# Tables are grouped into source buckets via the same name-matching
# logic as the cost Sankey for consistency. Top 15 buckets render
# individually; anything beyond rolls up into "Other sources (N)".
function _TopologyBucketFor {
    param([string]$Table, [string]$Source, [string]$Identifier)
    if ($Source -eq 'CCF' -and $Identifier) { return $Identifier }
    if ($Source -eq 'Classic') {
        # Identifier is "kind/dataType"; the friendly title comes from
        # the Get-ConnectorFriendlyTitle helper above. Strip to kind.
        $kind = ($Identifier -split '/')[0]
        return (Get-ConnectorFriendlyTitle -Kind $kind -Connector $null -CcfTitleByName $ccfTitleByName)
    }
    if (-not $Table) { return 'Other sources' }
    switch -Regex ($Table) {
        '^ThreatIntel'                                                                                  { return 'Microsoft Defender TI' }
        '^(SigninLogs|AuditLogs|AAD.*|MicrosoftGraphActivityLogs|MicrosoftServicePrincipalSignInLogs)$' { return 'Microsoft Entra ID' }
        '^(Device|Email|Url|Alert|Cloud|Identity).*'                                                    { return 'Microsoft Defender XDR' }
        '^ASim'                                                                                         { return 'ASIM normaliser' }
        '^Office'                                                                                       { return 'Office 365' }
        '^(CommonSecurityLog|Syslog)$'                                                                  { return 'CEF / Syslog' }
        '^(SecurityEvent|WindowsEvent|Event)$'                                                          { return 'Windows events' }
        '^(AzureActivity)$'                                                                             { return 'Azure Activity' }
        '^(AzureDiagnostics|AzureMetrics)$'                                                             { return 'Azure resource diagnostics' }
        '^Intune'                                                                                       { return 'Intune' }
        '^App'                                                                                          { return 'Application Insights' }
        '^Dataverse'                                                                                    { return 'Power Platform' }
        '^(LAQueryLogs|Usage|Heartbeat|Operation|Perf|SentinelAudit)$'                                  { return 'Workspace operations' }
        '_CL$'                                                                                          { return 'Custom logs (CCF / DCR)' }
        default                                                                                         { return 'Other sources' }
    }
}

$sourceBuckets = @{}
foreach ($e in $effective) {
    $bucket = _TopologyBucketFor -Table $e.Table -Source $e.Source -Identifier $e.Identifier
    if (-not $sourceBuckets.ContainsKey($bucket)) { $sourceBuckets[$bucket] = 0 }
    $sourceBuckets[$bucket]++
}
# Order: highest item-count first, with the "Other sources" catch-all
# always last regardless of count.
$sortedBuckets = $sourceBuckets.GetEnumerator() |
    Sort-Object @{ Expression = { if ($_.Key -eq 'Other sources') { 1 } else { 0 } } }, @{ Expression = { -$_.Value } }, Key |
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
    $label = if ($b.Count -gt 1) { "$($b.Name) · $($b.Count)" } else { $b.Name }
    # Wrap label in double quotes — Mermaid flowchart treats `(` as a
    # node-shape directive, so unquoted labels containing parens parse-
    # error with "Expecting SQE/PE/STADIUMEND etc.".
    "    $shortId[`"$label`"]"
}
if ($overflowBuckets.Count -gt 0) {
    $srcLines += "    S99[`"Other sources · $overflowTotal`"]"
    $sourceEdges += "    S99 --> WS"
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
$sentinelDataLake = Read-RawArray 'sentinel-data-lake.json'
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
    $r  = [int]($t.properties.retentionInDays | ForEach-Object { if ($_) { $_ } else { 0 } })
    $tr = [int]($t.properties.totalRetentionInDays | ForEach-Object { if ($_) { $_ } else { 0 } })
    if ($tr -gt $r -and $tr -gt 0) { $archiveTables++ }
}
$hasBasic     = $plansInUse.ContainsKey('Basic')
$hasAuxiliary = $plansInUse.ContainsKey('Auxiliary')
$hasDataLake  = $plansInUse.ContainsKey('DataLake') -or @($sentinelDataLake).Count -gt 0 -or $unifiedBilling
$hasArchive   = $archiveTables -gt 0

$wspNodes = @('        WS[(Log Analytics workspace)]', "        RUL[Analytics rules · $($enabledRules.Count)]", '        INC[Incidents]')
$wspEdges = @('    WS --> RUL', '    RUL --> INC')
if ($hasBasic)     { $wspNodes += '        BAS[Basic plan tables]';     $wspEdges += '    WS --> BAS' }
if ($hasAuxiliary) { $wspNodes += '        AUX[Auxiliary plan tables]'; $wspEdges += '    WS --> AUX' }
if ($hasDataLake)  { $wspNodes += '        DL[(Sentinel Data Lake)]';   $wspEdges += '    WS --> DL' }
if ($hasArchive)   { $wspNodes += "        ARC[(Long-term archive · $archiveTables tables)]"; $wspEdges += '    WS --> ARC' }

# Downstream — render only the destinations the capture supports.
$dataExports = Read-RawArray 'data-exports.json'
$dataExportCount = @($dataExports).Count
$hasPlaybooks = @($playbooks).Count -gt 0

$dstNodes = @()
$dstEdges = @()
if ($m365DefenderConnected) {
    $dstNodes += '        XDR[Defender XDR portal]'
    $dstEdges += '    INC --> XDR'
}
if ($hasPlaybooks) {
    $dstNodes += "        PB[Playbooks · $(@($playbooks).Count)]"
    $dstEdges += '    INC --> PB'
}
if ($dataExportCount -gt 0) {
    $dstNodes += "        EXP[Data export · $dataExportCount destination(s)]"
    $dstEdges += '    WS --> EXP'
}
# Always-on destination — workbooks consume workspace data regardless
# of incidents. Surface it so the topology shows the reporting flow.
if (@($workbooksSaved).Count -gt 0) {
    $dstNodes += "        WB[Workbooks · $(@($workbooksSaved).Count)]"
    $dstEdges += '    WS --> WB'
}
$hasDownstream = $dstNodes.Count -gt 0
# The topology as data for the SharePoint graphic: every source family
# (none rolled up), the table plans in use and not, and the destinations.
$planTableCounts = @{}
foreach ($t in $workspaceTables) { $pl = [string]$t.properties.plan; if ($pl) { if (-not $planTableCounts.ContainsKey($pl)) { $planTableCounts[$pl] = 0 }; $planTableCounts[$pl]++ } }
$planDetail = { param([string]$Plan) if ($planTableCounts.ContainsKey($Plan)) { "$($planTableCounts[$Plan]) table$(if ($planTableCounts[$Plan] -ne 1) { 's' })" } else { 'In use' } }
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
        [ordered]@{ name = 'Playbooks'; inUse = $hasPlaybooks; detail = "$(@($playbooks).Count)" }
        [ordered]@{ name = 'Data export'; inUse = ($dataExportCount -gt 0); detail = "$dataExportCount destination$(if ($dataExportCount -ne 1) { 's' })" }
        [ordered]@{ name = 'Workbooks'; inUse = (@($workbooksSaved).Count -gt 0); detail = "$(@($workbooksSaved).Count)" }
    )
})
$dstClassLine = ''
if ($hasDownstream) {
    $dstIds = $dstNodes | ForEach-Object { ($_ -split '\[')[0].Trim() }
    $dstClassLine = "    class $($dstIds -join ',') dst"
}
$dcBody = @"
$(Format-Banner -Title "Data Collection Rules and Endpoints")

## Workspace topology

Every captured ingestion source, grouped into product families with the number of distinct sources feeding each; then the workspace, its analytics rules and the table plans it uses; then where its data goes. A plan or destination shows as in use only when the capture supports it: the Data Lake only when the tenant is enrolled, the Defender XDR portal only when the Microsoft 365 Defender connector is enabled.

``````mermaid
flowchart LR
$topologyVisualLine
    subgraph SRC["Connected sources"]
        direction TB
$($srcLines -join [Environment]::NewLine)
    end

    subgraph WSP["Sentinel workspace"]
        direction TB
$($wspNodes -join [Environment]::NewLine)
    end
$(if ($hasDownstream) { @"

    subgraph DST["Downstream"]
        direction TB
$($dstNodes -join [Environment]::NewLine)
    end
"@ })

$($sourceEdges -join [Environment]::NewLine)
$($wspEdges -join [Environment]::NewLine)
$(if ($hasDownstream) { $dstEdges -join [Environment]::NewLine })

    classDef src fill:#1a3b5b,stroke:#37a,color:#dfd
    classDef wsp fill:#5b3a1a,stroke:#a73,color:#fed
    classDef dst fill:#1a3b1a,stroke:#3a3,color:#dfd
    class $((@('WS','RUL','INC') + @(if ($hasBasic){'BAS'}) + @(if ($hasAuxiliary){'AUX'}) + @(if ($hasDataLake){'DL'}) + @(if ($hasArchive){'ARC'})) -join ',') wsp
$dstClassLine
``````

## DCRs

Only DCRs whose ``destinations.logAnalytics`` includes this workspace appear here. DCRs that live in this subscription but route to other workspaces are excluded from the primary table (see *Other DCRs in subscription* below).

$(Format-Table -Items $dcrRows -Columns 'Name','Kind','Streams','HasTransform')

$(if ($dcrOutOfScopeRows.Count -gt 0) { @"

## Other DCRs in subscription (targeting different workspaces)

These DCRs were captured at subscription scope but their LA destinations point at workspaces other than ``$WorkspaceName``. Useful for cleanup audits (orphaned DCRs from decommissioned workspaces, mis-routed DCRs after a workspace migration, etc.), not relevant to this workspace's ingestion.

$(Format-Table -Items $dcrOutOfScopeRows -Columns 'Name','Kind','TargetsWs')
"@ })

## DCEs

$(Format-Table -Items $dceRows -Columns 'Name','Location')

[Data collection rules (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview) · [Transformations](https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-transformations)
"@
Write-Section '83-data-collection.md' $dcBody

# ---------------------------------------------------------------------------
# Section: 84 — cost estimate
# ---------------------------------------------------------------------------
$costBody = if (-not $cost) { @"
$(Format-Banner -Title "Estimated Monthly Cost")

_Cost estimate not available. Confirm Export-SentinelInventory.ps1 ran with retail-prices fetch and tables-with-data KQL._
"@ } else {
$planRows = $cost.ByPlan.PSObject.Properties | ForEach-Object {
    [pscustomobject]@{ Plan = $_.Name; Gb30d = [math]::Round($_.Value.Gb30d, 2); MonthlyCost = $_.Value.MonthlyCost }
}
# How the workspace is priced, its commitment tier, and the data grants
# that may cover part of it; an estimate from before these were reported
# has none of them.
$costField = { param([string]$Name) if ($cost.PSObject.Properties.Name -contains $Name) { $cost.$Name } else { $null } }
$costTier = & $costField 'CommitmentTier'
# An estimate worked out before methodology 2.0.0 keeps the method it used.
$costMethodV2 = $false
try { $costMethodV2 = [version][string](& $costField 'MethodologyVersion') -ge [version]'2.0.0' } catch { $costMethodV2 = $false }
$costPricing = [string](& $costField 'PricingModel')
$costTierText = if ($costTier) {
    $ic = [System.Globalization.CultureInfo]::InvariantCulture
    "The workspace is on the **$(([double]$costTier.Level).ToString('N0', $ic)) GB a day commitment tier**: $(([double]$costTier.DailyPrice).ToString('N2', $ic)) $($cost.Currency) a day, an effective $(([double]$costTier.EffectivePerGb).ToString('N4', $ic)) $($cost.Currency) per GB. Analytics ingest averaged $(([double]$costTier.DailyAverageGb).ToString('N1', $ic)) GB a day, $($costTier.Utilisation)% of the tier: the tier is paid in full below it, and use above it is billed at its effective rate."
} elseif ($costPricing -eq 'Simplified') {
    'The workspace is on pay-as-you-go, priced at the simplified Microsoft Sentinel rate, which covers Log Analytics ingestion as well.'
} elseif ($costPricing -eq 'Classic') {
    'The price list had no simplified Microsoft Sentinel rate, so Analytics data is priced at the classic pair: Log Analytics ingestion plus Sentinel analysis.'
} else { '' }
$costCurrencySource = [string](& $costField 'CurrencySource')
$costCurrencyText = switch ($costCurrencySource) {
    'Region'    { "Prices are in $($cost.Currency), taken from the workspace's region (``$($cost.Region)``); billing currency follows the billing account, so set the collector's ``-Currency`` (the pipelines' currency setting) when that is wrong." }
    'Parameter' { "Prices are in $($cost.Currency), as the run's ``-Currency`` setting asked." }
    default     { '' }
}
$grantRows = @(@(& $costField 'BenefitEligible') | Where-Object { $_ } | ForEach-Object {
    [pscustomobject]@{ Grant = [string]$_.Benefit; Allowance = [string]$_.Allowance; Gb30d = $_.Gb30d; MonthlyCost = $_.MonthlyCost; Tables = [string]$_.Tables }
})

# ---------------------------------------------------------------------
# Sankey prep — computed outside the heredoc so $sankeyFlowText and
# $sankeyHeight can be interpolated, and the long-tail collapse logic
# is testable in isolation.
# ---------------------------------------------------------------------
function _CostSourceFor {
    param([string]$Table)
    switch -Regex ($Table) {
        '^ThreatIntel'                                             { return 'Microsoft Defender TI' }
        '^(SigninLogs|AuditLogs|AAD.*|MicrosoftGraphActivityLogs|MicrosoftServicePrincipalSignInLogs)$' { return 'Microsoft Entra ID' }
        '^(Device|Email|Url|Alert|Cloud|Identity).*'               { return 'Microsoft Defender XDR' }
        '^ASim'                                                    { return 'ASIM normaliser' }
        '^Office'                                                  { return 'Office 365' }
        '^(CommonSecurityLog|Syslog)$'                             { return 'CEF / Syslog' }
        '^(SecurityEvent|WindowsEvent|Event)$'                     { return 'Windows events' }
        '^(AzureActivity|AzureDiagnostics|AzureMetrics)$'          { return 'Azure platform' }
        '^Intune'                                                  { return 'Intune' }
        '^Unifi'                                                   { return 'UniFi' }
        '^Tailscale'                                               { return 'Tailscale' }
        '^App(Traces|Metrics|Requests|Dependencies|Exceptions|PageViews|PerformanceCounters|Events|SystemEvents|ServiceHTTPLogs|ServiceConsoleLogs|ServicePlatformLogs|ServiceFileAuditLogs|ServiceIPSecAuditLogs|ServiceAntivirusScanAuditLogs)$' { return 'Application Insights' }
        '^(LAQueryLogs|Usage|Heartbeat|Operation|Perf)$'           { return 'Workspace operations' }
        '^Dataverse'                                               { return 'Power Platform' }
        '_CL$'                                                     { return 'Custom (CCF / DCR)' }
        default                                                    { return 'Other' }
    }
}

# Use the full per-table cost list when the exporter wrote it; fall back
# to Top-10 for older captures so the chart still renders.
$allTables = if ($cost.PSObject.Properties.Name -contains 'AllTablesByCost' -and $cost.AllTablesByCost) {
    @($cost.AllTablesByCost)
} else {
    @($cost.Top10TablesByCost)
}

$flowFiltered = New-Object System.Collections.Generic.List[object]
foreach ($t in $allTables) {
    $gb = [double]$t.Gb30d
    if ($gb -lt 0.01) { continue }
    # The rate each table bills at is its plan's.
    $tier = switch ([string]$t.Plan) { 'Basic' { 'Basic rate' } 'Auxiliary' { 'Auxiliary rate' } 'DataLake' { 'Data lake rate' } default { 'Analytics rate' } }
    $flowFiltered.Add([pscustomobject]@{
        Table  = $t.Table
        Gb     = $gb
        Source = (_CostSourceFor $t.Table)
        Tier   = $tier
    })
}

# Decide which tables keep their own middle-column node. On a busy
# workspace with ~80+ tables the Sankey middle column becomes an
# unreadable wall — fix by collapsing the cost-insignificant tail into
# per-source bucket nodes. Rule: tables in the top 90% of billable GB
# stay individual; the remainder collapse to "<source> tail (N)".
# Workspaces with ≤25 tables skip the collapse entirely.
$totalGb = ($flowFiltered | Measure-Object -Property Gb -Sum).Sum
$sorted = $flowFiltered | Sort-Object -Property Gb -Descending
$keepIndividual = @{}
if ($sorted.Count -le 25 -or $totalGb -le 0) {
    foreach ($r in $sorted) { $keepIndividual[$r.Table] = $true }
} else {
    $cum = 0.0
    $threshold = $totalGb * 0.90
    foreach ($r in $sorted) {
        $keepIndividual[$r.Table] = $true
        $cum += $r.Gb
        if ($cum -ge $threshold) { break }
    }
}

# Promote single-occupant tail sources — a bucket of one is uglier than
# just showing the table.
$tailCount = @{}
foreach ($r in $flowFiltered) {
    if (-not $keepIndividual.ContainsKey($r.Table)) {
        if (-not $tailCount.ContainsKey($r.Source)) { $tailCount[$r.Source] = 0 }
        $tailCount[$r.Source]++
    }
}
foreach ($r in $flowFiltered) {
    if (-not $keepIndividual.ContainsKey($r.Table) -and $tailCount[$r.Source] -lt 2) {
        $keepIndividual[$r.Table] = $true
    }
}
# Recompute counts after promotions so the bucket labels show the
# accurate post-promotion count.
$tailCount = @{}
foreach ($r in $flowFiltered) {
    if (-not $keepIndividual.ContainsKey($r.Table)) {
        if (-not $tailCount.ContainsKey($r.Source)) { $tailCount[$r.Source] = 0 }
        $tailCount[$r.Source]++
    }
}

$bySourceTable = @{}
$byTableTier   = @{}
foreach ($r in $flowFiltered) {
    $tableNode = if ($keepIndividual.ContainsKey($r.Table)) {
        $r.Table
    } else {
        "$($r.Source) tail ($($tailCount[$r.Source]))"
    }
    $stKey = "$($r.Source)||$tableNode"
    $ttKey = "$tableNode||$($r.Tier)"
    if (-not $bySourceTable.ContainsKey($stKey)) { $bySourceTable[$stKey] = 0.0 }
    if (-not $byTableTier.ContainsKey($ttKey))   { $byTableTier[$ttKey]   = 0.0 }
    $bySourceTable[$stKey] += $r.Gb
    $byTableTier[$ttKey]   += $r.Gb
}

$flowRowsList = New-Object System.Collections.Generic.List[string]
# Largest flows first, then by name: hashtable order changes between runs.
foreach ($k in @($bySourceTable.Keys | Sort-Object @{ Expression = { $bySourceTable[$_] }; Descending = $true }, @{ Expression = { $_ } })) {
    $parts = $k -split '\|\|'
    $flowRowsList.Add("$($parts[0]),$($parts[1]),$([math]::Round($bySourceTable[$k], 3))")
}
foreach ($k in @($byTableTier.Keys | Sort-Object @{ Expression = { $byTableTier[$_] }; Descending = $true }, @{ Expression = { $_ } })) {
    $parts = $k -split '\|\|'
    $flowRowsList.Add("$($parts[0]),$($parts[1]),$([math]::Round($byTableTier[$k], 3))")
}
$sankeyFlowText = $flowRowsList -join [Environment]::NewLine

# Dynamic height — Mermaid sankey-beta crams labels when nodes exceed
# the configured height. Scale with the middle-column count (the wide
# axis) and the source-column count, whichever's larger.
$middleNodeCount = @(($bySourceTable.Keys | ForEach-Object { ($_ -split '\|\|')[1] }) | Sort-Object -Unique).Count
$sourceCount     = @(($bySourceTable.Keys | ForEach-Object { ($_ -split '\|\|')[0] }) | Sort-Object -Unique).Count
$tallestColumn   = [Math]::Max($middleNodeCount, $sourceCount)
$sankeyHeight    = [Math]::Max(720, 24 * $tallestColumn + 200)

# The cost as data for the SharePoint graphic: the total, GB and cost by
# plan, and every source family with every one of its tables (no tail
# buckets: the graphic lists them all behind each family).
$costVisualLine = Format-VisualLine -Kind 'cost-breakdown' -Data ([ordered]@{
    windowDays   = (Get-BpWindow).Days
    currency     = [string]$cost.Currency
    monthlyTotal = $cost.MonthlyTotal
    totalGb      = [math]::Round([double]$totalGb, 2)
    plans        = @($planRows | Sort-Object { -[double]$_.Gb30d } | ForEach-Object { [ordered]@{ name = [string]$_.Plan; gb = [double]$_.Gb30d; cost = $_.MonthlyCost } })
    sources      = @($flowFiltered | Group-Object Source | ForEach-Object {
        [ordered]@{
            name   = [string]$_.Name
            gb     = [math]::Round([double](($_.Group | Measure-Object -Property Gb -Sum).Sum), 2)
            tables = @($_.Group | Sort-Object -Property Gb -Descending | ForEach-Object { [ordered]@{ table = [string]$_.Table; gb = [math]::Round([double]$_.Gb, 2); tier = [string]$_.Tier } })
        }
    } | Sort-Object { -$_.gb })
})

@"
$(Format-Banner -Title "Estimated Monthly Cost")

> **Headline** **$($cost.MonthlyTotal) $($cost.Currency)** for the workspace, projected to a month from the last {lookback} of `Usage` × Azure Retail Prices for ``$($cost.Region)`` as of ``$(Format-DateUtc $cost.AsOfUtc)``.
$(if ($costTierText) { "`n$costTierText`n" })$(if ($costCurrencyText) { "`n$costCurrencyText`n" })
<!-- bp:tone warning -->

> **Public list prices only.** The estimate uses Azure's public retail prices. It does not include any discount or agreement your organisation may have that is not public, such as Enterprise Agreement or Microsoft Customer Agreement rates, a Microsoft Azure Consumption Commitment (MACC), negotiated pricing or credits, so what you are billed can differ.

## By plan

$(Format-Table -Items $planRows -Columns 'Plan','Gb30d','MonthlyCost')

## Tables by cost

``````mermaid
---
config:
  xyChart:
    width: 1400
    height: 480
---
xychart-beta
    title "Top tables by billable GB ({lookback-d})"
    x-axis [$(($cost.Top10TablesByCost | ForEach-Object {
        $t = if ($_.Table.Length -gt 14) { $_.Table.Substring(0,14) } else { $_.Table }
        "`"$t`""
    }) -join ', ')]
    y-axis "GB" 0 --> $([math]::Ceiling(([double]($cost.Top10TablesByCost | Measure-Object -Property Gb30d -Maximum).Maximum + 0.5)))
    bar [$(($cost.Top10TablesByCost | ForEach-Object { $_.Gb30d }) -join ', ')]
$(Format-XyFullLabels @($cost.Top10TablesByCost | ForEach-Object { $_.Table }))
``````

Long-tail concentration: the loudest table is always the right first cost-optimisation target. The chart shows the ten costliest tables; the table below lists every table with its full name.

$(Format-Table -Items @($allTables | ForEach-Object { [pscustomobject]@{ Table = $_.Table; Plan = $_.Plan; Gb30d = $_.Gb30d; MonthlyCost = $_.MonthlyCost; Grant = $(if ($_.PSObject.Properties.Name -contains 'Benefit') { [string]$_.Benefit } else { '' }) } }) -Columns 'Table','Plan','Gb30d','MonthlyCost','Grant')

## Cost by source and plan

``````mermaid
---
config:
  sankey:
    showValues: true
    nodeAlignment: justify
    nodePadding: 28
    height: $sankeyHeight
    width: 1200
    useMaxWidth: true
    linkColor: gradient
---
sankey-beta
$costVisualLine

$sankeyFlowText
``````

Where the billable data comes from, by source family and table, and the rate each table bills at, which is its plan's: Analytics, Basic, Auxiliary or the data lake. Findings [SAC-LOG-15], [SAC-LOG-16] and [SAC-LOG-18] flag tables that could move to a cheaper plan through DCR-based splits.

## Commitment-tier what-if

$(if ($cost.CommitmentTierWhatIf.Count -gt 0) {
    Format-Table -Items $cost.CommitmentTierWhatIf -Columns 'Rung','ProjectedMonthlyCost','DeltaVsCurrent'
} else { '_No commitment tier would cost less than the current pricing for this ingest, so no change is suggested._' })
$(if ($grantRows.Count -gt 0) { @"

## Data grants that may reduce this

Microsoft covers the ingestion of these tables free up to an allowance that depends on licences and servers the Blueprint does not read, so the estimate above prices them at list. Each figure is the most that grant could save over the month: the Microsoft 365 E5 grant covers up to 5 MB per licensed user a day, the Defender for Servers Plan 2 allowance 500 MB per server a day, and only data collected the way each grant requires.

$(Format-Table -Items $grantRows -Columns 'Grant','Allowance','Gb30d','MonthlyCost','Tables')
"@ })

## Methodology (v$($cost.MethodologyVersion))

1. Source of truth for ingestion: `Usage` table over the last {lookback}, `IsBillable` honoured, projected to 30 days for the monthly figures.
2. Plan attribution: each table's current `plan` decides which meter applies (Analytics / Basic / Auxiliary / DataLake).
$(if ($costMethodV2) { @"
3. Unit price: the public prices from the [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices) for ``$($cost.Region)`` at run-time. Analytics-plan tables are priced at the simplified Microsoft Sentinel rate, which covers Log Analytics ingestion (an older price list falls back to the classic Log Analytics and Sentinel pair); Basic tables at the Basic logs rate; tables on the data lake tier only at data lake ingestion plus data processing, and Auxiliary tables the same once the workspace is onboarded to the data lake.
4. Commitment tier: a workspace on a tier pays its price a day for its GB, and the Analytics GB above it at the tier's effective rate (the price over the GB), as Microsoft bills it; the cost is shared over the Analytics tables by their GB.
5. Data grants: the tables in `Private/Resources/sentinel-benefit-tables.json` are priced at list and reported under Data grants, not deducted, since their allowances depend on licence and server counts.
6. Commitment-tier what-if: every published tier priced against the window's Analytics ingest; the cheapest is shown when it beats the current cost.
7. Dedicated cluster break-even: candidate flag set when daily ingest > 500 GB and no cluster exists.
"@ } else { @"
3. Unit price: fetched from the [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices) for ``$($cost.Region)`` at collection.
4. Sentinel free benefit: the tables then listed in `Private/Resources/sentinel-benefit-tables.json` were priced at zero on the assumption the benefit was active.
5. Commitment-tier projection: illustrative, as actual discounts depend on published rates.
6. Dedicated cluster break-even: candidate flag set when daily ingest > 500 GB and no cluster exists.

This estimate was worked out at collection with that earlier method; the next collection prices with the current one.
"@ })

## Caveats: explicitly NOT priced

$($cost.Caveats | ForEach-Object { "- $_" }) -join "`n")

[Sentinel billing (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/billing) · [Reduce costs](https://learn.microsoft.com/azure/sentinel/billing-reduce-costs) · [Cost logs](https://learn.microsoft.com/azure/azure-monitor/logs/cost-logs)
"@
}
# What the Sentinel pricings endpoint reports, setting by setting. It is a
# preview API that returns nothing in some regions; the estimate itself is
# built from the workspace SKU and retail prices, not from it.
$pricingRows = @(foreach ($item in @(Read-RawArray 'sentinel-pricing.json' | Where-Object { $_ })) {
    $label = [string](_RProp $item 'name' (_RProp $item 'kind' 'pricing'))
    $props = _RProp $item 'properties'
    if ($props) {
        foreach ($pp in $props.PSObject.Properties) {
            [pscustomobject]@{ Pricing = $label; Setting = $pp.Name; Value = $(if ($null -eq $pp.Value -or $pp.Value -is [string] -or $pp.Value -is [ValueType]) { [string]$pp.Value } else { $pp.Value | ConvertTo-Json -Compress -Depth 6 }) }
        }
    }
    else { [pscustomobject]@{ Pricing = $label; Setting = 'kind'; Value = [string](_RProp $item 'kind' '') } }
})
$costBody += @"

## Sentinel pricing settings

What the Microsoft Sentinel pricings endpoint (``Microsoft.SecurityInsights/pricings``) reports for the workspace. It is a preview API that is not available in every region; the estimate above is built from the workspace SKU and Azure retail prices, not from it.

$(Format-Table -Items $pricingRows -Columns 'Pricing','Setting','Value' -EmptyMessage (Get-EmptyMessage 'sentinel-pricing.json' '_The endpoint returned nothing for this workspace._'))
"@
Write-Section '84-cost-estimate.md' $costBody

# ---------------------------------------------------------------------------
# Section: 85 — RBAC
# ---------------------------------------------------------------------------
$rbacWs = Read-RawArray 'rbac-workspace.json'
$rbacRg = Read-RawArray 'rbac-resourcegroup.json'

# Principal fallback chain — DisplayName is empty for some assignments
# (deleted SPs, certain group types, MIs without a friendly name). Fall
# back to SignInName, then to the GUID ObjectId so the column always
# has content. An ObjectId-only row is a signal the principal may have
# been deleted but the role assignment lingers — itself a useful audit
# finding.
function _RbacPrincipal {
    param($Row)
    if ($Row.DisplayName) { return [string]$Row.DisplayName }
    if ($Row.SignInName)  { return [string]$Row.SignInName }
    if ($Row.ObjectId)    { return "_(no display name)_ ``$($Row.ObjectId)``" }
    return '_(unknown)_'
}
$wsRows = $rbacWs | ForEach-Object {
    [pscustomobject]@{ Principal = (_RbacPrincipal $_); SignIn = [string](_RProp $_ 'SignInName' ''); Type = $_.ObjectType; Role = $_.RoleDefinitionName }
}
# Counts per role by principal type, and the three views the access review
# starts from: Sentinel roles, Log Analytics and monitoring roles, and the
# roles that can change or delete the workspace.
$roleCountRows = @($rbacWs | Where-Object { $_ } | Group-Object RoleDefinitionName | ForEach-Object {
    [pscustomobject]@{
        Role              = $_.Name
        Total             = $_.Count
        Users             = @($_.Group | Where-Object { $_.ObjectType -eq 'User' }).Count
        Groups            = @($_.Group | Where-Object { $_.ObjectType -eq 'Group' }).Count
        ServicePrincipals = @($_.Group | Where-Object { $_.ObjectType -eq 'ServicePrincipal' }).Count
    }
} | Sort-Object @{ Expression = 'Total'; Descending = $true }, Role)
$sentinelRoleRows = @($wsRows | Where-Object { $_.Role -match 'Sentinel' })
$lawRoleRows = @($wsRows | Where-Object { $_.Role -match 'Log Analytics|Monitoring (Reader|Contributor)' })
$highPrivRows = @($wsRows | Where-Object { $_.Role -in @('Owner', 'Contributor', 'User Access Administrator') })
$rgRows = $rbacRg | ForEach-Object {
    [pscustomobject]@{ Principal = (_RbacPrincipal $_); Type = $_.ObjectType; Role = $_.RoleDefinitionName }
}

# Build the RBAC flowchart. Group principals by role to keep the flow readable.
# Mark broad-role paths (Owner / Contributor) as warnings via dotted edges.
$rolesSeen = New-Object System.Collections.Generic.HashSet[string]
foreach ($r in $rbacWs) {
    $role = $r.RoleDefinitionName
    if ($role) { [void]$rolesSeen.Add($role) }
}
$roleNodeLines = @()
$roleIdMap = @{}
$roleIdx = 0
foreach ($role in $rolesSeen) {
    $roleIdx++
    $rId = "R$roleIdx"
    $roleIdMap[$role] = $rId
    $roleNodeLines += "        $rId[$role]"
}

# Per-role principal counts so the diagram doesn't list every individual SP.
$principalsByRole = @{}
foreach ($r in $rbacWs) {
    $role = $r.RoleDefinitionName
    $type = $r.ObjectType
    if (-not $principalsByRole.ContainsKey($role)) { $principalsByRole[$role] = @{ User = 0; Group = 0; ServicePrincipal = 0 } }
    if ($principalsByRole[$role].ContainsKey($type)) { $principalsByRole[$role][$type]++ }
}

$principalNodes = @()
$principalEdges = @()
$principalClicks = @()
$prinIdx = 0
foreach ($role in $rolesSeen) {
    foreach ($t in @('User', 'Group', 'ServicePrincipal')) {
        $n = $principalsByRole[$role][$t]
        if ($n -eq 0) { continue }
        $prinIdx++
        $prinId = "P$prinIdx"
        $principalNodes += "        $prinId[$n $t$(if ($n -gt 1) { 's' })]"
        if ($role -in @('Owner', 'Contributor')) {
            $sentId = if ($t -eq 'ServicePrincipal') { 'sac-gov-05' } else { 'sac-gov-06' }
            $principalEdges += "    $prinId -.->|broad| $($roleIdMap[$role])"
            $principalClicks += "    click $prinId href ""90-gap-analysis.md#$sentId"" ""$($sentId.ToUpper()): broad role recommendation"""
        } else {
            $principalEdges += "    $prinId --> $($roleIdMap[$role])"
        }
    }
}

# The assignments as data for the SharePoint graphic: every role in a band
# (broad roles, Microsoft Sentinel roles, Log Analytics and monitoring, the
# rest), with its users, groups and service principals.
$accessBand = { param([string]$Role)
    if ($Role -in 'Owner', 'Contributor', 'User Access Administrator') { 'broad' }
    elseif ($Role -like 'Microsoft Sentinel*') { 'sentinel' }
    elseif ($Role -like 'Log Analytics*' -or $Role -like 'Monitoring*') { 'monitor' }
    else { 'other' }
}
$accessRoles = { param([string]$Band)
    @($rolesSeen | Where-Object { (& $accessBand $_) -eq $Band } | ForEach-Object {
        $c = $principalsByRole[$_]
        [ordered]@{ role = [string]$_; users = [int]$c['User']; groups = [int]$c['Group']; servicePrincipals = [int]$c['ServicePrincipal'] }
    } | Sort-Object { -($_.users + $_.groups + $_.servicePrincipals) }, { $_.role })
}
$accessVisualLine = Format-VisualLine -Kind 'access' -Data ([ordered]@{ bands = @(
    [ordered]@{ name = 'Broad roles'; tone = 'bad'; findings = @(@('SAC-GOV-05', 'SAC-GOV-06') | Where-Object { $script:FiredFindingIds.ContainsKey($_) }); roles = @(& $accessRoles 'broad') }
    [ordered]@{ name = 'Microsoft Sentinel roles'; tone = 'ok'; findings = @(); roles = @(& $accessRoles 'sentinel') }
    [ordered]@{ name = 'Log Analytics and monitoring'; tone = 'info'; findings = @(); roles = @(& $accessRoles 'monitor') }
    [ordered]@{ name = 'Other roles'; tone = 'neutral'; findings = @(); roles = @(& $accessRoles 'other') }
) })

# Headline figures for the access review: how many assignments and to whom,
# then the ones that carry risk. A principal is counted once however many
# roles it holds; one with neither a display name nor a sign-in name is
# deleted or not readable by the collector.
$rbacValid = @($rbacWs | Where-Object { $_ })
$rbacPrincipals = @($rbacValid | Group-Object { $oid = [string](_RProp $_ 'ObjectId' ''); if ($oid) { $oid } else { [string](_RProp $_ 'DisplayName' '') + '|' + [string](_RProp $_ 'SignInName' '') } })
$rbacOfType = { param($t) @($rbacPrincipals | Where-Object { [string](_RProp $_.Group[0] 'ObjectType' '') -eq $t }).Count }
$rbacHigh = @($rbacValid | Where-Object { $_.RoleDefinitionName -in 'Owner', 'Contributor', 'User Access Administrator' }).Count
$rbacHighPct = if ($rbacValid.Count) { [math]::Round(100 * $rbacHigh / $rbacValid.Count) } else { 0 }
$rbacOwners = @($rbacValid | Where-Object RoleDefinitionName -EQ 'Owner').Count
$rbacSentinel = @($rbacValid | Where-Object { [string]$_.RoleDefinitionName -like 'Microsoft Sentinel*' }).Count
$rbacGuests = @($rbacPrincipals | Where-Object { [string](_RProp $_.Group[0] 'SignInName' '') -match '#EXT#' }).Count
$rbacUnnamed = @($rbacPrincipals | Where-Object { -not (_RProp $_.Group[0] 'DisplayName' '') -and -not (_RProp $_.Group[0] 'SignInName' '') }).Count

Write-Section '85-rbac.md' (@"
$(Format-Banner -Title "Access Control (RBAC)")

$($rbacWs.Count) workspace-scope assignment(s) across $($rolesSeen.Count) distinct role(s). Broad roles (Owner and Contributor) are marked out below; see [SAC-GOV-06] and [SAC-GOV-05] in the gap analysis.

**$($rbacValid.Count)** assignments at workspace scope  ·  **$(@($rbacRg | Where-Object { $_ }).Count)** at resource-group scope  ·  **$($rbacPrincipals.Count)** distinct principals  ·  **$(& $rbacOfType 'User')** users  ·  **$(& $rbacOfType 'Group')** groups  ·  **$(& $rbacOfType 'ServicePrincipal')** service principals

**$rbacHigh** high-privilege assignments  ·  **$rbacHighPct%** of assignments high-privilege  ·  **$rbacOwners** Owner assignments  ·  **$rbacSentinel** Microsoft Sentinel role assignments  ·  **$rbacGuests** guest accounts  ·  **$rbacUnnamed** principals with no name (deleted or not readable)

## Who-grants-what-to-whom

``````mermaid
flowchart LR
$accessVisualLine
    subgraph PRIN["Principals"]
        direction TB
$($principalNodes -join [Environment]::NewLine)
    end

    subgraph ROLES["Roles at workspace scope"]
        direction TB
$($roleNodeLines -join [Environment]::NewLine)
    end

$($principalEdges -join [Environment]::NewLine)

    classDef sentinelRole fill:#1a3b1a,stroke:#3a3,color:#dfd
    classDef broadRole fill:#5b1a1a,stroke:#a33,color:#fdd
$(($rolesSeen | ForEach-Object {
    if ($_ -in @('Owner', 'Contributor')) { "    class $($roleIdMap[$_]) broadRole" }
    elseif ($_ -like 'Microsoft Sentinel*') { "    class $($roleIdMap[$_]) sentinelRole" }
}) -join [Environment]::NewLine)
$($principalClicks -join [Environment]::NewLine)
``````

## Assignments by role

$(Format-Table -Items $roleCountRows -Columns 'Role','Total','Users','Groups','ServicePrincipals')

## Microsoft Sentinel role assignments

$(Format-Table -Items $sentinelRoleRows -Columns 'Principal','SignIn','Type','Role' -EmptyMessage '_No Microsoft Sentinel role is assigned at workspace scope._')

## Log Analytics and monitoring role assignments

$(Format-Table -Items $lawRoleRows -Columns 'Principal','SignIn','Type','Role' -EmptyMessage '_No Log Analytics or monitoring role is assigned at workspace scope._')

## High-privilege assignments (Owner, Contributor, User Access Administrator)

These roles can change or delete the workspace and everything in it, or grant access to others. Defender XDR portal roles are granted in Microsoft Entra ID and the Defender portal at tenant scope and cannot be read from the workspace.

$(Format-Table -Items $highPrivRows -Columns 'Principal','SignIn','Type','Role' -EmptyMessage '_No Owner, Contributor or User Access Administrator assignment at workspace scope._')

## At workspace scope

$(Format-Table -Items $wsRows -Columns 'Principal','SignIn','Type','Role')

## At resource group scope

$(Format-Table -Items $rgRows -Columns 'Principal','Type','Role')

[Sentinel roles (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/roles)
"@)

# ---------------------------------------------------------------------------
# Section: 86 — subscription context
# ---------------------------------------------------------------------------
$sub        = Read-Raw 'subscription.json'
$rps        = Read-RawArray 'resource-providers.json'
$locks      = Read-RawArray 'subscription-locks.json'
$policies   = Read-RawArray 'policy-assignments.json'

$rpRows = $rps | ForEach-Object { [pscustomobject]@{ Provider = $_.ProviderNamespace; State = $_.RegistrationState } }
$lockRows = $locks | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Level = $_.Properties.level; Notes = $_.Properties.notes } }
$polRows = $policies | ForEach-Object {
    # Az.Resources policy-assignment shape varies between versions; surface
    # whichever displayName/scope tier is present.
    $name = $null; $scope = $null
    if ($_.Properties) {
        $name  = $_.Properties.DisplayName
        $scope = $_.Properties.Scope
    }
    if (-not $name)  { $name  = $_.DisplayName }
    if (-not $name)  { $name  = $_.Name }
    if (-not $scope) { $scope = $_.Scope }
    [pscustomobject]@{ Name = $name; Scope = $scope }
}

# Resource-provider registration-state pie for the headline.
$rpStateCounts = @{}
foreach ($r in $rpRows) {
    $s = if ($r.State) { [string]$r.State } else { 'Unknown' }
    if (-not $rpStateCounts.ContainsKey($s)) { $rpStateCounts[$s] = 0 }
    $rpStateCounts[$s]++
}
$rpPieRows = $rpStateCounts.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}
$rpChartBlock = if ($rpRows.Count -gt 0) {
    @"

## Resource-provider registration state

``````mermaid
pie showData title Required resource providers: registration state
$($rpPieRows -join [Environment]::NewLine)
``````

[SAC-PLT-09] fires whenever any required provider is not in the `Registered` state. The pie surfaces that ratio at a glance.
"@
} else { '' }

# Who the collector ran as. Snapshots from before the account was recorded
# say so rather than showing a blank.
$runCtx86 = Read-Raw 'run-context.json'
$identityBlock = if ($runCtx86 -and $runCtx86.PSObject.Properties['Account']) {
    @"
| | |
|---|---|
| Account | ``$([string]$runCtx86.Account)`` |
| Type | $([string](_RProp $runCtx86 'AccountType' 'Unknown')) |
"@
} else { '_Not recorded in this snapshot._' }

Write-Section '86-subscription-context.md' (@"
$(Format-Banner -Title "Subscription and Tenant Context")

## Subscription

| | |
|---|---|
| Name | $($sub.Name) |
| ID   | ``$($sub.Id)`` |
| Tenant ID | ``$($sub.TenantId)`` |
| State | $($sub.State) |

## Signed-in identity

The identity the collector ran as: a pipeline signs in as its service connection's service principal or managed identity, a local run as the person running it. Every capture reflects what this identity could read.

$identityBlock
$rpChartBlock

## Resource providers

$(Format-Table -Items $rpRows -Columns 'Provider','State')

## Locks

$(Format-Table -Items $lockRows -Columns 'Name','Level','Notes')

## Sentinel-relevant policy assignments

$(Format-Table -Items $polRows -Columns 'Name','Scope')

[Resource providers (Microsoft Learn)](https://learn.microsoft.com/azure/azure-resource-manager/management/resource-providers-and-types)
"@)

# ---------------------------------------------------------------------------
# Section: 90 — gap analysis
# ---------------------------------------------------------------------------
# Findings and maturity are one assessment: each finding names the maturity
# criterion it decides, if any, and what closing it does to the score.
$findingMaturity = Get-FindingMaturityLink -CriteriaPath (Join-Path $ResourcesRoot 'maturity-criteria.json') -Maturity $(if ($maturityOk) { $maturity } else { $null })
function _FormatFindingMaturity([string]$Id) {
    $links = if ($findingMaturity.ContainsKey($Id)) { @($findingMaturity[$Id]) } else { @() }
    if ($links.Count -eq 0) { return 'not scored. This is a hygiene or cost check; it does not move the maturity score.' }
    return ((@($links | ForEach-Object {
        $state = if ($_.Status) { ", now $($_.Status)" } else { '' }
        $gain = if ($null -ne $_.Lift -and $_.Lift -gt 0) {
            $by = ([double]$_.Lift).ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
            if ($_.Shared) { "; closing all of its findings lifts the overall score by +$by" } else { "; closing it lifts the overall score by +$by" }
        } else { '' }
        $how = if ($_.Shared) { 'one of the findings behind' } else { 'decides' }
        "$how [$($_.CriterionId)](91-maturity-assessment.md#criteria) $($_.Name) ($($_.AreaName))$state$gain"
    })) -join '; ') + '.'
}
$gapRows = $gapFindings | ForEach-Object {
    [pscustomobject]@{
        ID       = "[$($_.Id)](#$(($_.Id).ToLower()))"
        Severity = $_.Severity
        Category = $_.Category
        Title    = $_.Title
        Maturity = Format-FindingMaturityShort $(if ($findingMaturity.ContainsKey($_.Id)) { @($findingMaturity[$_.Id]) } else { $null })
    }
}

# Evidence + Learn link formatters for the detailed remediation cards
# below. Evidence text from gap rules can be very long with semicolon-
# separated lists (e.g. 657 disabled rule names). Cramming that into a
# narrow table cell is unreadable. The detail-card form splits long
# semicolon lists into bullet items and renders short evidence inline.
# A list item that starts with a Markdown block marker (a rule named
# "* Detection ..." or "1. Test") would open a nested list, a heading or a
# quote and leave its own bullet empty; a backslash keeps it as text.
function _EscapeMdListItem {
    param([string]$Text)
    return (($Text -replace '^([*+\-#>])(?=\s|$)', '\$1') -replace '^(\d+)([.)])(?=\s|$)', '$1\$2')
}

function _FormatGapEvidence {
    param([string]$Evidence)
    if (-not $Evidence) { return '_(none)_' }
    # A snapshot collected before the gap checks named unnamed principals
    # holds "?" for them; say so in words rather than print the "?".
    $Evidence = [regex]::Replace($Evidence, '(?<=[:;]\s)\?(?=\s*(;|\.?\s*$))', 'Unnamed (no name in this snapshot)')
    # Threshold: only expand to bullets when the evidence is both long
    # AND list-shaped (4+ semicolons). Short evidence ("X 75% threshold
    # exceeded") stays inline.
    $semis = ([regex]::Matches($Evidence, ';')).Count
    if ($Evidence.Length -lt 200 -or $semis -lt 3) { return $Evidence }

    # Split on the colon-then-list pattern so the lead-in prose stays
    # before the bulleted list. Example:
    #   "Recommended connectors not deployed: A, B, C"
    #   -> "Recommended connectors not deployed:\n- A\n- B\n- C"
    $leadEnd = $Evidence.IndexOf(':')
    if ($leadEnd -gt 0 -and $leadEnd -lt 200) {
        $lead  = $Evidence.Substring(0, $leadEnd + 1).Trim()
        $tail  = $Evidence.Substring($leadEnd + 1).Trim()
        $items = $tail -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        return @"
$lead

$(($items | ForEach-Object { "  - $(_EscapeMdListItem $_)" }) -join [Environment]::NewLine)
"@
    }
    # No leading colon — bullet the whole list.
    $items = $Evidence -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    return ($items | ForEach-Object { "  - $(_EscapeMdListItem $_)" }) -join [Environment]::NewLine
}

function _FormatGapLearnLink {
    param([string]$Url)
    if (-not $Url) { return '_(no reference)_' }
    # Use a friendly title rather than a bare URL. Extract the last URL
    # path segment, replace hyphens with spaces, and title-case the
    # result. Falls back to "Microsoft Learn" if the path is empty.
    try {
        $u = [uri]$Url
        $last = ($u.AbsolutePath.TrimEnd('/') -split '/')[-1]
        if (-not $last) { $last = 'Microsoft Learn' }
        $words = ($last -replace '-', ' ')
        $titled = (Get-Culture).TextInfo.ToTitleCase($words.ToLower())
        if (-not $titled) { $titled = 'Microsoft Learn' }
        return "[$titled (Microsoft Learn)]($Url)"
    } catch {
        return "[Microsoft Learn]($Url)"
    }
}
# Findings landscape — grouped bar by category × severity. Sort categories
# by Warning-then-Info count desc so the worst buckets land on the left.
$catOrder = $gapByCategory.Keys | Sort-Object {
    -(1000 * ($gapByCategory[$_].Critical) + 10 * ($gapByCategory[$_].Warning) + ($gapByCategory[$_].Info))
}, { $_ }
$catAxis = ($catOrder | ForEach-Object { "`"$_`"" }) -join ', '
$catWarn = ($catOrder | ForEach-Object { $gapByCategory[$_].Warning }) -join ', '
$catInfo = ($catOrder | ForEach-Object { $gapByCategory[$_].Info }) -join ', '
$catMax = 1
foreach ($c in $catOrder) {
    $t = $gapByCategory[$c].Warning + $gapByCategory[$c].Info + $gapByCategory[$c].Critical
    if ($t -gt $catMax) { $catMax = $t }
}

Write-Section '90-gap-analysis.md' (@"
$(Format-Banner -Title "Gap Analysis")

The gap engine compares the live workspace against the rule set in [Private/Resources/best-practices.json](https://github.com/noodlemctwoodle/Sentinel-As-Code/blob/main/Modules/iSOCBlueprint/Engine/Private/Resources/best-practices.json). Each row is a Test-* function in [Private/GapChecks.ps1](https://github.com/noodlemctwoodle/Sentinel-As-Code/blob/main/Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1), and adding a new rule is a two-line change.

Findings and the [maturity assessment](91-maturity-assessment.md) are one assessment seen two ways: a finding says what is wrong now, a maturity criterion scores the capability it leaves missing. Each finding below says which criterion it decides and what closing it does to the overall score; a finding no criterion reads is a hygiene or cost check that does not move the score.

## Findings landscape

``````mermaid
xychart-beta
    title "Findings by category, split by severity"
    x-axis [$catAxis]
    y-axis "Findings" 0 --> $($catMax + 1)
    bar "Warning" [$catWarn]
    bar "Info"    [$catInfo]
``````

**$($gapFindings.Count) findings.** Categories sorted worst-first (Critical → Warning → Info weighting). Each bar is a category; adjacent Warning + Info bars per category make the severity mix visible at a glance.

## Findings summary

Each ID links to the detail card below, where the full evidence, remediation and reference links live. ``Maturity`` is the overall-score lift from closing the finding and the area it counts in, or Not scored for a hygiene or cost check. Sorted by severity first, then by category.

$(if ($gapRows.Count -gt 0) { Format-Table -Items $gapRows -Columns 'ID','Severity','Category','Title','Maturity' } else { '_No findings: a clean run._' })

## Findings detail

$(if ($gapFindings.Count -gt 0) {
    ($gapFindings | ForEach-Object { @"
<a id="$($_.Id.ToLower())"></a>

### $($_.Id): $($_.Title)

**Severity:** $($_.Severity)  ·  **Category:** $($_.Category)

**Maturity:** $(_FormatFindingMaturity $_.Id)

**Evidence**

$(_FormatGapEvidence $_.Evidence)

**Remediation**

$($_.Remediation)

**Reference:** $(_FormatGapLearnLink $_.Learn)

---
"@ }) -join [Environment]::NewLine
} else { '' })
"@)

# ---------------------------------------------------------------------------
# New sections aligned to the formal Sentinel Configuration TOC
# (TOC numbering shown alongside each MD filename).
# ---------------------------------------------------------------------------

# Section 01 — Live snapshot  (TOC 1)
# Living-documentation framing: this page is regenerated from the live
# workspace on every CI/CD pipeline trigger and every pull request, so the
# numbers reflect the workspace at the render timestamp — not a periodic
# audit deliverable. Title and description avoid "report" / "summary"
# language to reinforce that this is documentation-as-code, not a
# point-in-time deck.
# Synthesised from headline counts + cost + top gap findings + MITRE coverage.
# $gapBySeverity / $gapByCategory are computed up at the top of the file
# (around line 285) so 00-overview can also use them. Don't recompute here.

# Today + days-until calculations drive the deprecation gantt bar widths.
$today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
function _DaysUntilFromToday {
    param([string]$IsoDate)
    $target = [datetime]::Parse($IsoDate, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
    $delta = $target.ToUniversalTime() - (Get-Date).ToUniversalTime()
    [int][math]::Ceiling($delta.TotalDays)
}
$clv1Days = _DaysUntilFromToday '2026-09-14'
$tipDays  = _DaysUntilFromToday '2027-06-30'
$xdrDays  = _DaysUntilFromToday '2027-03-31'

# MITRE coverage rollup. Reuse $mitreRowsRich from section 25 — that view
# already does the intersect-with-catalogue (rules' tactic shortnames must
# match a catalogue.sentinelShortName) and categorises each tactic as
# Covered / Thin / None against the 3-rule threshold. Counting from the
# same source guarantees the headline and the section-25 matrix agree.
$tacticsTotal         = if ($tactics) { $tactics.Count } else { 14 }
$tacticsCoveredFull   = @($mitreRowsRich | Where-Object { $_.Coverage -eq 'Covered' }).Count
$tacticsThin          = @($mitreRowsRich | Where-Object { $_.Coverage -eq 'Thin'    }).Count
$tacticsNone          = @($mitreRowsRich | Where-Object { $_.Coverage -eq 'None'    }).Count
$thinTacticNames      = @($mitreRowsRich | Where-Object { $_.Coverage -eq 'Thin'    } | Select-Object -ExpandProperty Tactic)
$noneTacticNames      = @($mitreRowsRich | Where-Object { $_.Coverage -eq 'None'    } | Select-Object -ExpandProperty Tactic)
$mitreSuffix          = if ($thinTacticNames.Count -gt 0 -or $noneTacticNames.Count -gt 0) {
    $parts = @()
    if ($noneTacticNames.Count -gt 0) { $parts += "uncovered: $($noneTacticNames -join ', ')" }
    if ($thinTacticNames.Count -gt 0) { $parts += "thin: $($thinTacticNames -join ', ')" }
    "  ·  $($parts -join '  ·  ')"
} else { '' }

# Legacy and deprecated features still in use, one row each, read from the
# same captures their pages use. A capture missing from an older snapshot
# shows as Not captured rather than as not in use.
function _LegacyRow([string]$Feature, $Count, [bool]$Captured, [string]$Evidence, [string]$Where) {
    [pscustomobject]@{
        Feature  = $Feature
        Status   = $(if (-not $Captured) { 'Not captured' } elseif ([double]$Count -gt 0) { 'In use' } else { 'Not in use' })
        Evidence = $(if ($Captured) { $Evidence } else { '' })
        Where    = $Where
    }
}
$mmaMachines01 = [long](@(Read-RawArray 'ama-mma-migration.json' | Where-Object { $_ } | ForEach-Object { _RendererNumber (_RProp $_ 'MMACount' 0) }) | Measure-Object -Sum).Sum
$classicTables01 = @($workspaceTables | Where-Object { $_ -and [string](_RProp (_RProp (_RProp $_ 'properties') 'schema') 'tableSubType' '') -eq 'Classic' })
$tiLegacyRows01 = [long](@(Read-RawArray 'threat-intel-tables.json' | Where-Object { $_ -and [string]$_.Table -eq 'ThreatIntelligenceIndicator' } | ForEach-Object { _RendererNumber (_RProp $_ 'Records30d' 0) }) | Measure-Object -Sum).Sum
$tiLegacyRules01 = @($enabledRules | Where-Object { [string](_RProp (_RProp $_ 'properties') 'query' '') -match 'ThreatIntelligenceIndicator(?!s)' }).Count
$msIncidentRules01 = @($rules | Where-Object { $_ -and $_.kind -eq 'MicrosoftSecurityIncidentCreation' -and (_RProp (_RProp $_ 'properties') 'enabled' $false) }).Count
$ascAlerts01 = [long](@(Read-RawArray 'analytics-rule-volumes.json' | Where-Object { $_ -and [string]$_.ProductName -eq 'Azure Security Center' } | ForEach-Object { _RendererNumber $_.Alerts }) | Measure-Object -Sum).Sum
$fwLegacy01 = [long](@(Read-RawArray 'azure-firewall-categories.json' | Where-Object { $_ -and [string]$_.Category -like 'AzureFirewall*' } | ForEach-Object { _RendererNumber $_.LogCount }) | Measure-Object -Sum).Sum
$has01 = { param($f) Test-Path (Join-Path $rawRoot $f) }
$deprecatedConnectors01 = @($catalogueStatus | Where-Object Deprecated | ForEach-Object Connector | Sort-Object -Unique)
$legacyRows = @(
    _LegacyRow 'Deprecated data connectors still connected' $deprecatedConnectors01.Count ([bool]$connectorCatalogue -and (& $has01 'data-connectors-classic.json')) "$($deprecatedConnectors01.Count) connector(s)$(if ($deprecatedConnectors01.Count) { ': ' + ($deprecatedConnectors01 -join '; ') })" '[10-data-connectors.md](10-data-connectors.md)'
    _LegacyRow 'Legacy Log Analytics agent (MMA / OMS), retired 31 August 2024' $mmaMachines01 (& $has01 'ama-mma-migration.json') "$mmaMachines01 machine(s) still heartbeating through it in {lookback}" '[87-azure-monitor-agents.md](87-azure-monitor-agents.md), [SAC-PLT-03]'
    _LegacyRow 'Classic custom tables (HTTP Data Collector API), retiring 14 September 2026' $classicTables01.Count (& $has01 'workspace-tables.json') "$($classicTables01.Count) table(s) with tableSubType Classic" '[81-table-plans-retention.md](81-table-plans-retention.md), [SAC-PLT-02]'
    _LegacyRow 'Retired ThreatIntelligenceIndicator table (ingestion)' $tiLegacyRows01 (& $has01 'threat-intel-tables.json') "$tiLegacyRows01 record(s) in {lookback}" '[27-threat-intelligence.md](27-threat-intelligence.md), [SAC-TI-01]'
    _LegacyRow 'Retired ThreatIntelligenceIndicator table (rules reading it)' $tiLegacyRules01 (& $has01 'alert-rules.json') "$tiLegacyRules01 enabled rule(s) query it" '[20-analytics-rules.md](20-analytics-rules.md), [SAC-TI-02]'
    _LegacyRow 'Microsoft incident-creation rules (pre-unification)' $msIncidentRules01 (& $has01 'alert-rules.json') "$msIncidentRules01 enabled rule(s)" '[20-analytics-rules.md](20-analytics-rules.md), [SAC-DET-08]'
    _LegacyRow 'Azure Security Center alert path (replaced by Defender for Cloud)' $ascAlerts01 (& $has01 'analytics-rule-volumes.json') "$ascAlerts01 alert(s) in {lookback}" '[10-data-connectors.md](10-data-connectors.md)'
    _LegacyRow 'Azure Firewall legacy AzureDiagnostics categories' $fwLegacy01 (& $has01 'azure-firewall-categories.json') "$fwLegacy01 row(s) in {lookback}" '[14-coverage-breakdowns.md](14-coverage-breakdowns.md), [SAC-LOG-06]'
)

$execBody = @"
$(Format-Banner -Title "Live snapshot")

> Living documentation for the Microsoft Sentinel workspace ``$WorkspaceName``. Every page in this set is regenerated from the live workspace on every CI/CD pipeline run and every pull request, so the numbers below describe the workspace as it stands at the timestamp above, not a periodic audit deliverable. If a value looks stale, re-run the pipeline; there is no separate refresh cycle.

## Workspace at a glance

| Indicator | Value |
|---|---:|
| Workspace SKU | ``$($workspace.properties.sku.name)`` |
| Default retention | $($workspace.properties.retentionInDays) days |
| Daily cap | $(if ($workspace.properties.workspaceCapping.dailyQuotaGb -eq -1) { 'Unlimited' } else { "$($workspace.properties.workspaceCapping.dailyQuotaGb) GB" }) |
| Estimated monthly cost | $(if ($cost) { "$($cost.MonthlyTotal) $($cost.Currency)" } else { 'n/a' }) |
| Data connectors | $($connectors.Count) |
| Analytics rules (enabled / total) | $($enabledRules.Count) / $($rules.Count) |
| MITRE tactics: Covered / Thin / None | $tacticsCoveredFull / $tacticsThin / $tacticsNone of $tacticsTotal$mitreSuffix |
| Tables receiving data ({lookback-d}) | $($populatedTables.Count) populated · $($operationalTables.Count) operational · $($workspaceTables.Count) catalogue |
| Findings (Critical / Warning / Info) | $($gapBySeverity.Critical) / $($gapBySeverity.Warning) / $($gapBySeverity.Info) |
| Maturity (overall / target) | $maturityCell |
| Legacy features still in use | $(@($legacyRows | Where-Object Status -eq 'In use').Count) of $(@($legacyRows | Where-Object Status -ne 'Not captured').Count) checked; see [02-deprecated-legacy-features.md](02-deprecated-legacy-features.md) |

The findings by severity and the estate flow, from source families through detection to incidents, are on [00-overview.md](00-overview.md).

## Top recommendations

$(if ($top5Findings.Count -gt 0) { "The $($top5Findings.Count) most severe of $($gapFindings.Count) finding(s), each with what was found and how to fix it, are on [00-overview.md](00-overview.md); [90-gap-analysis.md](90-gap-analysis.md) lists every one." } else { '_No findings: a clean run._' })

## Where to read more

| Concern | See |
|---|---|
| Retirements and legacy features | [02-deprecated-legacy-features.md](02-deprecated-legacy-features.md) |
| What's new and retiring in Sentinel and Defender | [03-whats-new.md](03-whats-new.md) |
| Connectors and ingestion | [10-data-connectors.md](10-data-connectors.md), [83-data-collection.md](83-data-collection.md) |
| Detection coverage | [20-analytics-rules.md](20-analytics-rules.md), [21-rule-performance.md](21-rule-performance.md), [22-rule-health-quality.md](22-rule-health-quality.md), [25-mitre-coverage.md](25-mitre-coverage.md), [28-detection-opportunities.md](28-detection-opportunities.md) |
| Workspace, tables, retention | [80-workspace.md](80-workspace.md), [81-table-plans-retention.md](81-table-plans-retention.md), [89-retention.md](89-retention.md) |
| Cost | [84-cost-estimate.md](84-cost-estimate.md) |
| Operational health | [11-sentinel-health.md](11-sentinel-health.md), [12-soc-optimization.md](12-soc-optimization.md), [15-incidents.md](15-incidents.md), [16-alerts.md](16-alerts.md) |
| Identity and access | [85-rbac.md](85-rbac.md) |
| Findings vs. best practice | [90-gap-analysis.md](90-gap-analysis.md) |
| Maturity and roadmap | [91-maturity-assessment.md](91-maturity-assessment.md) |
"@
Write-Section '01-live-snapshot.md' $execBody

# Section 02: retired and retiring platform features, with the deadlines
# still ahead and whether this workspace uses each one.
# The runway as data for the SharePoint graphic: each deadline, and whether
# this workspace still uses what it retires (null when it cannot say).
$runwayUse = { param([bool]$Captured, [bool]$InUse) if ($Captured) { $InUse } else { $null } }
$mmaCaptured = & $has01 'ama-mma-migration.json'
$tiCaptured = (& $has01 'threat-intel-tables.json') -or (& $has01 'alert-rules.json')
$tipConnectors = @($connectors | Where-Object { $_ -and [string]$_.kind -eq 'ThreatIntelligence' }).Count
$runwayVisualLine = Format-VisualLine -Kind 'runway' -Data ([ordered]@{ today = $today; items = @(
    [ordered]@{ label = 'MMA / OMS agent retired'; date = '2024-08-31'; state = 'done'; inUse = (& $runwayUse $mmaCaptured ($mmaMachines01 -gt 0)); evidence = "$mmaMachines01 machine$(if ($mmaMachines01 -ne 1) { 's' })" }
    [ordered]@{ label = 'MMA ingestion degraded'; date = '2025-02-01'; state = 'done'; inUse = (& $runwayUse $mmaCaptured ($mmaMachines01 -gt 0)); evidence = "$mmaMachines01 machine$(if ($mmaMachines01 -ne 1) { 's' })" }
    [ordered]@{ label = 'Legacy threat intelligence ingestion stopped'; date = '2025-07-31'; state = 'done'; inUse = (& $runwayUse $tiCaptured ($tiLegacyRows01 -gt 0 -or $tiLegacyRules01 -gt 0)); evidence = "$tiLegacyRows01 records, $tiLegacyRules01 rules" }
    [ordered]@{ label = 'HTTP Data Collector API retires'; date = '2026-09-14'; state = 'crit'; inUse = (& $runwayUse (& $has01 'workspace-tables.json') ($classicTables01.Count -gt 0)); evidence = "$($classicTables01.Count) classic table$(if ($classicTables01.Count -ne 1) { 's' })" }
    [ordered]@{ label = 'Sentinel in the Azure portal retires (move to the Defender portal)'; date = '2027-03-31'; state = 'crit'; inUse = $null; evidence = '' }
    [ordered]@{ label = 'Legacy threat intelligence platform connector deprecates'; date = '2027-06-30'; state = 'active'; inUse = (& $runwayUse (& $has01 'data-connectors-classic.json') ($tipConnectors -gt 0)); evidence = 'connector connected' }
) })

$legacyBody = @"
$(Format-Banner -Title "Deprecated and Legacy Features")

What Microsoft has retired or is retiring on the Sentinel platform, and whether this workspace still depends on any of it. Each row links to the page with the detail.

## Platform deprecation runway

``````mermaid
gantt
$runwayVisualLine
    title Microsoft Sentinel platform deprecation runway
    dateFormat YYYY-MM-DD
    axisFormat %b %Y

    section Past deadlines
    MMA / OMS agent retired                :done,  mma,  2024-08-31, 1d
    MMA ingestion degraded                 :done,  mmaI, 2025-02-01, 1d
    Legacy TI ingestion stopped            :done,  ti,   2025-07-31, 1d

    section Upcoming
    Today                                  :milestone, today, $today, 0d
    HTTP Data Collector API retires        :crit,  clv1, $today, ${clv1Days}d
    Legacy TIP connector deprecates        :active, tip,  $today, ${tipDays}d
    Sentinel Azure portal retires (→ XDR)  :crit,  xdr,  $today, ${xdrDays}d
``````

## Legacy features still in use

Each retired or retiring feature the Blueprint can see, whether this workspace still uses it, and where the detail is. Sentinel's move from the Azure portal to the Defender portal is on the runway above; Defender-portal onboarding cannot be read from the workspace.

$(Format-Table -Items $legacyRows -Columns 'Feature','Status','Evidence','Where')

[What's new and deprecated in Microsoft Sentinel (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/whats-new)
"@
Write-Section '02-deprecated-legacy-features.md' $legacyBody

# Section 03: what Microsoft has released, previewed and announced for
# retirement in Sentinel and Defender XDR, from their What's new pages on
# Microsoft Learn (the collector's whats-new.json), each item linked to the
# report pages and maturity criteria it touches with this workspace's status.
$whatsNew = Read-Raw 'whats-new.json'
$wnItems = @(if ($whatsNew -and $whatsNew.PSObject.Properties['Items']) { @($whatsNew.Items | Where-Object { $_ }) })
$wnTopicsPath = Join-Path $ResourcesRoot 'whats-new-topics.json'
$wnTopics = @(if (Test-Path -LiteralPath $wnTopicsPath) { @((Get-Content -LiteralPath $wnTopicsPath -Raw | ConvertFrom-Json).topics) })
$wnCriterion = @{}
if ($maturityOk) { foreach ($a in @($maturity.areas)) { foreach ($c in @($a.criteria)) { if ($c -and $c.id) { $wnCriterion[[string]$c.id] = $c } } } }
# What an item touches here: each matching topic's page, then each of its
# criteria with this workspace's status; a criterion whose finding fired
# links to the finding. Semicolon-separated, so the site shows them as chips.
function Get-WhatsNewRelations {
    param($Item)
    $text = "$($Item.Title) $($Item.Summary)"
    $parts = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($t in $wnTopics) {
        if ($text -notmatch "(?i)$($t.match)") { continue }
        $link = "[$($t.label)]($($t.section).md)"
        if (-not $seen.ContainsKey($link)) { $seen[$link] = $true; $parts.Add($link) }
        foreach ($id in @($t.criteria)) {
            if ($seen.ContainsKey($id)) { continue }
            $seen[$id] = $true
            $c = $wnCriterion[[string]$id]
            $state = if ($c) { ([string]$c.status).ToLowerInvariant() } else { 'not assessed' }
            $ref = if ($script:FiredFindingIds.ContainsKey($id)) { "[$id]" } else { $id }
            $parts.Add("$ref $state")
        }
    }
    return ($parts -join '; ')
}
# An item's first sentence: the table stays readable, and the item links to
# its full entry on Learn.
$wnFirstSentence = { param([string]$T)
    $m = [regex]::Match($T, '^(.{40,}?[.!?])(\s|$)')
    $s = if ($m.Success) { $m.Groups[1].Value } else { $T }
    if ($s.Length -gt 240) { $cut = $s.LastIndexOf(' ', 240); $s = $s.Substring(0, $(if ($cut -gt 0) { $cut } else { 240 })) + [char]0x2026 }
    $s
}
# A deadline that has gone by says so.
$wnToday = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
$wnDeadline = { param([string]$D) if (-not $D) { '' } elseif ([string]::CompareOrdinal($D, $wnToday.Substring(0, $D.Length)) -lt 0) { "$D (passed)" } else { $D } }
$wnMonth = { param([string]$M) try { ([datetime]::ParseExact($M, 'yyyy-MM', [System.Globalization.CultureInfo]::InvariantCulture)).ToString('MMM yyyy', [System.Globalization.CultureInfo]::InvariantCulture) } catch { $M } }
$wnRows = @($wnItems | ForEach-Object {
    $rel = Get-WhatsNewRelations -Item $_
    [pscustomobject]@{
        Product   = [string]$_.Product
        Month     = (& $wnMonth ([string]$_.Month))
        Status    = [string]$_.Status
        Item      = "[$(([string]$_.Title) -replace '\|', '/')]($([string]$_.Link))"
        Summary   = ((& $wnFirstSentence ([string]$_.Summary)) -replace '\|', '/')
        Deadline  = $(if ($_.PSObject.Properties['Deadline'] -and $_.Deadline) { & $wnDeadline ([string]$_.Deadline) } else { '' })
        'Relates to here' = $rel
        Gap       = [bool]($rel -match '\b(gap|unknown)\b')
    }
})
$wnStatusOrder = 'Action needed', 'Retiring', 'Generally available', 'Preview', 'Update'
$wnCount = { param([string]$S, [string]$P) @($wnRows | Where-Object { $_.Status -eq $S -and (-not $P -or $_.Product -eq $P) }).Count }
$wnActionRows = @($wnRows | Where-Object { $_.Status -in 'Action needed', 'Retiring' } | Sort-Object @{ Expression = { if ($_.Deadline) { $_.Deadline } else { '9999' } } })
$wnGapCount = @($wnRows | Where-Object Gap).Count
$wnTone = @{ 'Action needed' = 'warn'; 'Retiring' = 'bad'; 'Generally available' = 'ok'; 'Preview' = 'info'; 'Update' = 'neutral' }
$wnVisualLine = Format-VisualLine -Kind 'meters' -Data ([ordered]@{
    meters = @(foreach ($p in 'Microsoft Sentinel', 'Microsoft Defender XDR') {
        [ordered]@{ title = $p; caption = "Items in the last $(if ($whatsNew) { $whatsNew.Months } else { 12 }) months"; total = @($wnRows | Where-Object Product -EQ $p).Count; parts = @(foreach ($s in $wnStatusOrder) { [ordered]@{ label = $s; value = (& $wnCount $s $p); tone = $wnTone[$s] } }) }
    })
    figures = @(
        [ordered]@{ label = 'Retiring or needing action'; value = $wnActionRows.Count; caption = 'Listed first below, soonest deadline first' }
        [ordered]@{ label = 'Touching a criterion not met here'; value = $wnGapCount; caption = 'A linked maturity criterion is a gap or unknown on this workspace' }
    )
})
$wnSources = @(if ($whatsNew -and $whatsNew.PSObject.Properties['Sources']) { @($whatsNew.Sources) })
$wnFetched = if ($whatsNew -and $whatsNew.PSObject.Properties['FetchedUtc']) { Format-DateUtc $whatsNew.FetchedUtc } else { '' }
$wnPages = if ($wnSources.Count) { $wnSources } else {
    @([pscustomobject]@{ Product = 'Microsoft Sentinel'; Url = 'https://learn.microsoft.com/en-us/azure/sentinel/whats-new' }
      [pscustomobject]@{ Product = 'Microsoft Defender XDR'; Url = 'https://learn.microsoft.com/en-us/defender-xdr/whats-new' })
}
$wnSourceLines = (@($wnPages | ForEach-Object {
    "- [What's new in $($_.Product) (Microsoft Learn)]($($_.Url))$(if ($_.PSObject.Properties['Ok'] -and -not $_.Ok) { ', which could not be read in this run' })"
}) -join [Environment]::NewLine)
$wnBody = if (-not $wnItems.Count) {
@"
$(Format-Banner -Title "What's New")

What Microsoft has released, previewed and announced for retirement in Microsoft Sentinel and Microsoft Defender XDR, read from their What's new pages on Microsoft Learn and linked to this report's pages and maturity criteria.

_Not captured in this snapshot: the collector reads the two What's new pages when it runs, and this inventory has no copy of them (the pages could not be reached, or an older collector took the inventory)._

$wnSourceLines
"@
} else {
@"
$(Format-Banner -Title "What's New")

What Microsoft has released, previewed and announced for retirement in Microsoft Sentinel and Microsoft Defender XDR over the last $($whatsNew.Months) months, read from their What's new pages on Microsoft Learn on $wnFetched. Each item links to its entry on Learn and to the pages of this report and the maturity criteria it touches, with this workspace's status for each criterion; a criterion whose finding fired links to the finding.

## At a glance

``````mermaid
pie showData title What's new by status (last $($whatsNew.Months) months)
$wnVisualLine
$(($wnStatusOrder | ForEach-Object { $n = (& $wnCount $_ ''); if ($n -gt 0) { "    `"$_`" : $n" } }) -join [Environment]::NewLine)
``````

<!-- bp:shown-in-graphic -->

**$($wnRows.Count)** items  ·  **$(& $wnCount 'Generally available' '')** generally available  ·  **$(& $wnCount 'Preview' '')** in preview  ·  **$($wnActionRows.Count)** retiring or needing action  ·  **$wnGapCount** touching a criterion not met here

## Retiring and action needed

Retirements, deprecations and calls to action, the soonest deadline first. Check each against the pages it links to before the date it names.

$(Format-Table -Items $wnActionRows -Columns 'Deadline','Product','Status','Item','Summary','Relates to here' -EmptyMessage '_Nothing retiring or needing action in this window._')

## Microsoft Sentinel

$(Format-Table -Items @($wnRows | Where-Object Product -EQ 'Microsoft Sentinel') -Columns 'Month','Status','Item','Summary','Relates to here' -EmptyMessage '_No items in this window._')

## Microsoft Defender XDR

$(Format-Table -Items @($wnRows | Where-Object Product -EQ 'Microsoft Defender XDR') -Columns 'Month','Status','Item','Summary','Relates to here' -EmptyMessage '_No items in this window._')

## How each item's status is set

The status comes from each entry's own wording: a call to action is Action needed; retired, retiring, deprecated or transitioning is Retiring; then Generally available or Preview as Microsoft marks it; anything else is Update. The links to this report come from Private/Resources/whats-new-topics.json.

$wnSourceLines
"@
}
Write-Section '03-whats-new.md' $wnBody

# Section 91 — Maturity assessment, from _raw/maturity.json. Engine:
# Private/Get-SentinelMaturity.ps1; methodology and criteria:
# Docs/Modules/iSOCBlueprint/Sentinel-Maturity-Model.md.
$maturityBody = if (-not $maturityOk) {
@"
$(Format-Banner -Title "Maturity Assessment")

_The maturity assessment was not produced in this run (``_raw/maturity.json`` is absent or empty). The collector writes it after the gap analysis; when that capture fails this page stays empty rather than scoring a workspace it cannot see._
"@
} else {
    $mAreas = @($maturity.areas)
    $areaAxis = ($mAreas | ForEach-Object { "`"$($_.id)`"" }) -join ', '
    $areaBars = ($mAreas | ForEach-Object { if ($null -eq $_.score) { 0 } else { $_.score } }) -join ', '
    $areaRows = @($mAreas | ForEach-Object {
        [pscustomobject]@{
            Id          = $_.id
            Area        = $_.name
            Score       = if ($null -eq $_.score) { 'n/a' } else { $_.score }
            Level       = if ($null -eq $_.level) { 'Not assessed' } else { "$($_.level) $($_.levelName)" }
            Evaluated   = "$($_.met) met of $($_.evaluated)"
            Unknown     = $_.unknown
            Confidence  = $_.confidence
            GapToTarget = if ($null -eq $_.score) { 'n/a' } elseif ($_.level -ge $maturity.targetLevel) { 'met' } else { [math]::Round($maturity.targetLevel - $_.score, 2) }
        }
    })
    $roadmapRows = @(@($maturity.roadmap) | ForEach-Object {
        [pscustomobject]@{ Priority = $_.priority; Criterion = "$($_.criterionId) $($_.name)"; Area = $_.area; Effort = $_.effort; Lift = $_.overallLift; Projected = $_.projectedScore; Guidance = $_.guidance }
    })
    $quickWinLines = if (@($maturity.quickWins).Count -gt 0) {
        (@($maturity.quickWins) | ForEach-Object { "- **$($_.criterionId)** $($_.name) ($($_.area), lift $($_.overallLift)): $($_.guidance)" }) -join [Environment]::NewLine
    } else { '_No Low-effort gaps remain; the rest of the roadmap is Medium or High effort._' }
    $csfRows = @(@($maturity.csf.functions) | ForEach-Object {
        [pscustomobject]@{ Function = "$($_.id) $($_.name)"; Criteria = $_.criteria; Met = $_.met; Gap = $_.gap; Unknown = $_.unknown }
    })
    $criteriaRows = @($mAreas | ForEach-Object {
        $areaId = $_.id
        @($_.criteria) | ForEach-Object {
            [pscustomobject]@{ Id = $_.id; Area = $areaId; Kind = $_.kind; Criterion = $_.name; Status = $_.status; Effort = $_.effort; Evidence = $_.evidence }
        }
    })
    $outOfScopeLines = (@($maturity.outOfScope) | ForEach-Object { "- **$($_.area)**: $($_.reason)" }) -join [Environment]::NewLine
    # The scale, with the score band each level covers and the target marked.
    $scaleRows = @(@($maturity.levels) | ForEach-Object {
        $lv = [int]$_.level
        [pscustomobject]@{
            Level  = $lv
            Name   = $_.name
            Scores = $(if ($lv -ge 5) { '5.00' } else { "$lv.00 to $lv.99" })
            Target = $(if ($lv -eq [int]$maturity.targetLevel) { 'Target' } else { '' })
        }
    })
    # Every open gap with what it costs the SOC today and what closes it.
    $openGapRows = @($mAreas | ForEach-Object {
        $areaId = $_.id
        @($_.criteria) | Where-Object { $_.status -eq 'Gap' } | ForEach-Object {
            [pscustomobject]@{ Id = $_.id; Area = $areaId; Criterion = $_.name; Effort = $_.effort; Impact = $_.impact; Guidance = $_.guidance }
        }
    })
    $overallText = if ($null -eq $maturity.overall.score) { 'not assessed' } else { "$($maturity.overall.score) / 5 ($($maturity.overall.levelName))" }
@"
$(Format-Banner -Title "Maturity Assessment")

> **$($maturity.methodology.name)** v$($maturity.methodology.version), criteria v$($maturity.methodology.criteriaVersion). $(if ($maturityBasis) { "$maturityBasis " })$($maturity.methodology.scaleNote)
$(if ($maturityScope) { "
> **Scope:** $maturityScope
" })

The maturity assessment and the [gap analysis](90-gap-analysis.md) are one assessment: the findings there are the evidence behind many of the criteria here, and each finding says which criterion it decides.

**Overall:** $overallText  ·  **Target:** $($maturity.targetLevel) ($($maturity.targetLevelName))  ·  **Areas below target:** $(@($maturity.areasBelowTarget).Count) of $($mAreas.Count)  ·  **Criteria:** $($maturity.totals.met) met · $($maturity.totals.gap) gaps · $($maturity.totals.unknown) unknown

Unknown criteria are those whose input was not captured or could not be measured in this run; they never count against the workspace. Confidence says how much of an area could be evaluated. The scoring, and every criterion's source, is in [Sentinel-Maturity-Model.md](https://github.com/noodlemctwoodle/Sentinel-As-Code/blob/main/Docs/Modules/iSOCBlueprint/Sentinel-Maturity-Model.md).

## Area scores

``````mermaid
---
config:
  xyChart:
    width: 1200
    height: 420
---
xychart-beta
    title "Maturity by area (0 to 5, target $($maturity.targetLevel))"
    x-axis [$areaAxis]
    y-axis "Score" 0 --> 5
    bar [$areaBars]
``````

## Areas

$(Format-Table -Items $areaRows -Columns 'Id','Area','Score','Level','Evaluated','Unknown','Confidence','GapToTarget')

## Maturity scale

An area's score is five times the weighted share of its evaluated criteria that are met; its level is the whole-number part of the score. Criteria that could not be evaluated are left out rather than counted as gaps.

$(Format-Table -Items $scaleRows -Columns 'Level','Name','Scores','Target')

## Open gaps and their impact

Every criterion that is not met, with what the gap costs the SOC today and the change that closes it. The roadmap below orders the same gaps by the lift each one gives.

$(Format-Table -Items $openGapRows -Columns 'Id','Area','Criterion','Effort','Impact','Guidance' -EmptyMessage '_No open gaps: every evaluated criterion is met._')

## Roadmap

Every gap ($(@($maturity.roadmap).Count) in all), ordered by how much closing it lifts the overall score, then by effort (Low first). ``Projected`` is the overall score after this entry and every one above it.

$(Format-Table -Items $roadmapRows -Columns 'Priority','Criterion','Area','Effort','Lift','Projected','Guidance')

## Quick wins

Every Low-effort entry on the roadmap, in roadmap order.

$quickWinLines

## NIST CSF 2.0 rollup

$(Format-Table -Items $csfRows -Columns 'Function','Criteria','Met','Gap','Unknown')

Subcategory identifiers are from the NIST Cybersecurity Framework 2.0 (NIST CSWP 29); the mapping and the outcome paraphrases are this project's own.

## Criteria

$(Format-Table -Items $criteriaRows -Columns 'Id','Area','Kind','Criterion','Status','Effort','Evidence')

## Out of scope

$outOfScopeLines
"@
}
Write-Section '91-maturity-assessment.md' $maturityBody

# Section 11 — Sentinel health (TOC 4.8)
$health = Read-RawArray 'sentinel-health.json'
$healthRows = $health | ForEach-Object {
    [pscustomobject]@{
        Resource = $_.SentinelResourceName
        Kind     = $_.SentinelResourceKind
        Type     = $_.SentinelResourceType
        Events   = $_.Events
        Failures = _RProp $_ 'Failures' ''
        Statuses = ((_RList (_RProp $_ 'Statuses')) -join ', ')
        'Last event' = Format-DateUtc $_.LastEvent
    }
}
# Data connectors that reported a failure. Failures arrived after the first
# captures; an older snapshot falls back to a non-Success status.
$healthFailuresCaptured = @($health | Where-Object { $_ -and $_.PSObject.Properties['Failures'] }).Count -gt 0
$connectorHealthRows = @($health | Where-Object {
    $_ -and (([string]$_.SentinelResourceType + ' ' + [string]$_.SentinelResourceKind) -match 'connector') -and
    $(if ($_.PSObject.Properties['Failures']) { [long]$_.Failures -gt 0 } else { @(_RList (_RProp $_ 'Statuses') | Where-Object { $_ -ne 'Success' }).Count -gt 0 })
} | ForEach-Object {
    [pscustomobject]@{
        Connector   = $_.SentinelResourceName
        Kind        = $_.SentinelResourceKind
        Failures    = _RProp $_ 'Failures' 'not captured'
        'Last failure' = Format-DateUtc (_RProp $_ 'LastFailure')
        Statuses    = ((_RList (_RProp $_ 'Statuses')) -join ', ')
    }
} | Sort-Object @{ Expression = { _RendererNumber $_.Failures }; Descending = $true }, Connector)
$healthSummary = Read-RawArray 'sentinel-health-summary.json'
$healthSummaryRows = $healthSummary | ForEach-Object {
    [pscustomobject]@{ OperationName = $_.OperationName; Status = $_.Status; LogCount = $_.LogCount }
}
$laQueryLogs = Read-RawArray 'la-query-logs.json' | Select-Object -First 1
$ingestionFailureRows = @(Read-RawArray 'ingestion-latency.json' | Where-Object { $_ } | ForEach-Object {
    [pscustomobject]@{ OperationKey = $_.OperationKey; Resource = $_.Resource; Failures = $_.Failures; Last = Format-DateUtc $_.Last }
} | Sort-Object { _RendererNumber $_.Failures } -Descending)
$laQueryLine = if ($laQueryLogs -and $laQueryLogs.QueryCount) {
    "**LAQueryLogs activity ({lookback-d}):** $($laQueryLogs.QueryCount) query records (query logging is active)."
} elseif ($laQueryLogs) {
    '_LAQueryLogs table is present but empty for the last {lookback}; query logging may be off._'
} else {
    '_LAQueryLogs table is not populated; query logging diagnostics are not configured._'
}
# Chart inputs: bucket health events by Status across all operations.
$healthByStatus = @{}
foreach ($r in $healthSummary) {
    $s = if ($r.Status) { [string]$r.Status } else { 'Unknown' }
    if (-not $healthByStatus.ContainsKey($s)) { $healthByStatus[$s] = 0 }
    $healthByStatus[$s] += [long]$r.LogCount
}
$healthPieRows = $healthByStatus.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}
$healthChartBlock = if ($healthSummary.Count -gt 0) {
    @"

## Health-event status mix

``````mermaid
pie showData title SentinelHealth events by status (last {lookback-d})
$($healthPieRows -join [Environment]::NewLine)
``````

Mostly-Success workspaces are operating cleanly. A non-trivial Failure / PartialSuccess slice means a Sentinel resource (rule, connector) has misfired recently.
"@
} else { '' }

Write-Section '11-sentinel-health.md' (@"
$(Format-Banner -Title "Sentinel Health and Resilience  (TOC 4.8)")

Health events are pulled from the workspace's ``SentinelHealth`` table for the last {lookback}, summarised per Sentinel resource. The table is empty on workspaces where Sentinel diagnostics have not been enabled: [turn on health diagnostics](https://learn.microsoft.com/azure/sentinel/health-audit) to start the data flowing.
$healthChartBlock

$(Format-Table -Items $healthRows -Columns 'Resource','Kind','Type','Events','Failures','Statuses','Last event')

## Connector and DCR health issues (last {lookback-d})

Data connectors whose health events reported a failure in the last {lookback}, most failures first. A failing connector silently stops feeding the tables its rules read; [83-data-collection.md](83-data-collection.md) lists the DCRs behind it.

$(Format-Table -Items $connectorHealthRows -Columns 'Connector','Kind','Failures','Last failure','Statuses' -EmptyMessage $(if ($health.Count -eq 0) { '_No connector health events in the last {lookback} (connector health diagnostics may be off)._' } else { '_No connector reported a failure in the last {lookback}._' }))

## Operations summary (per OperationName + Status)

$(Format-Table -Items $healthSummaryRows -Columns 'OperationName','Status','LogCount')

## Ingestion and schema failures (last {lookback-d})

Failed ingestion and schema operations from the ``Operation`` table, grouped by operation detail and category. A row here is a broken pipeline: a DCR transform that rejects records, a custom table whose schema no longer matches what is sent, or a connector writing to a table that cannot accept it. Empty means every ingestion and schema operation in the last {lookback} succeeded.

$(Format-Table -Items $ingestionFailureRows -Columns 'OperationKey','Resource','Failures','Last')

## Query logging activity

$laQueryLine

[Sentinel health, audit, and monitoring (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/health-audit)
"@)

# Section 12 — SOC Optimization Insights (TOC 4.9)
# Schema note: recommendation objects expose properties.recommendationTypeId
# (e.g. "Precision_Coverage", "Precision_DataValue"). AffectedItem comes from
# properties.additionalProperties on a per-kind basis (TableName for DataValue,
# UseCaseName for Coverage). Split into two sub-tables grouped by kind so the
# user-action drivers cluster — Coverage rows drive content-hub installs,
# DataValue rows drive ingestion-tuning.
$socOpt = Read-RawArray 'soc-optimization.json'
function _SocOptRow {
    param($Item, [string]$AffectedField)
    [pscustomobject]@{
        Title        = $Item.properties.title
        AffectedItem = $Item.properties.additionalProperties.$AffectedField
        State        = $Item.properties.state
        Description  = ($Item.properties.description -replace '\s+', ' ')
    }
}
$socCovRows = $socOpt | Where-Object { $_.properties.recommendationTypeId -eq 'Precision_Coverage'  } | ForEach-Object { _SocOptRow $_ 'UseCaseName' }
$socDvRows  = $socOpt | Where-Object { $_.properties.recommendationTypeId -eq 'Precision_DataValue' } | ForEach-Object { _SocOptRow $_ 'TableName'   }
$socOther   = $socOpt | Where-Object { $_.properties.recommendationTypeId -notin @('Precision_Coverage','Precision_DataValue') } | ForEach-Object {
    [pscustomobject]@{
        Kind         = $_.properties.recommendationTypeId
        Title        = $_.properties.title
        State        = $_.properties.state
        Description  = ($_.properties.description -replace '\s+', ' ')
    }
}
# Chart input: bucket recommendations by category for the headline pie.
$socCategoryCounts = [ordered]@{
    'Coverage' = $socCovRows.Count
    'Data Value' = $socDvRows.Count
    'Other' = $socOther.Count
}
$socPieRows = $socCategoryCounts.GetEnumerator() | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}
$socTotal = $socCategoryCounts.Values | Measure-Object -Sum | Select-Object -ExpandProperty Sum
$socChartBlock = if ($socTotal -gt 0) {
    @"

## Recommendation mix

``````mermaid
pie showData title SOC Optimization recommendations by category
$($socPieRows -join [Environment]::NewLine)
``````

$socTotal recommendations grouped by what action they drive. Coverage = onboard content; Data Value = tune ingestion; Other = MITRE tagging, UEBA, customers-like-me.
"@
} else { '' }

Write-Section '12-soc-optimization.md' (@"
$(Format-Banner -Title "SOC Optimization Insights  (TOC 4.9)")

Recommendations from the SOC Optimization service (preview). The endpoint is empty on workspaces where the service has not run, or in regions where it is not yet available. Recommendations are grouped by the kind of action they drive.
$socChartBlock

> Before tuning based on these recommendations, cross-reference [21-rule-performance.md](21-rule-performance.md): the highest-volume rules are usually the right place to start, regardless of which row of this section flagged them.

## Coverage recommendations

Drives Content Hub installs and rule activation. AffectedItem is the use-case name (e.g. ``BEC (Financial Fraud)``).

$(Format-Table -Items $socCovRows -Columns 'Title','AffectedItem','State','Description')

## Data Value recommendations

Drives ingestion tuning. AffectedItem is the workspace table name. A high count here is a sign that data is arriving but no detection coverage is matching it.

$(Format-Table -Items $socDvRows -Columns 'Title','AffectedItem','State','Description')

## Other recommendations

$(Format-Table -Items $socOther -Columns 'Kind','Title','State','Description')

[SOC optimization in Microsoft Sentinel (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/soc-optimization/soc-optimization-access)
"@)

# Section 13 — Data source hygiene
$cefDevices = Read-RawArray 'cef-devices.json'
$cefInSyslog = Read-RawArray 'cef-in-syslog.json'
$secEvtDupes = Read-RawArray 'security-event-duplicates.json'
$topEventIds = Read-RawArray 'top-event-ids.json'

$cefDevRows = $cefDevices | ForEach-Object {
    [pscustomobject]@{ DeviceVendor = $_.DeviceVendor; DeviceProduct = $_.DeviceProduct; LogCount = $_.LogCount }
}
$cefSyslogRows = $cefInSyslog | ForEach-Object {
    [pscustomobject]@{ Computer = $_.Computer; ProductVendor = _RProp $_ 'ProductVendor' ''; LogCount = $_.LogCount }
}
$secEvtDupeRows = $secEvtDupes | ForEach-Object {
    [pscustomobject]@{ Computer = $_.Computer; DuplicateRecords = _RProp $_ 'DuplicateRecords' ''; Copies = $_.LogCount; DuplicateEventIds = (@($_.DuplicateEventIds) -join ', ') }
}
$topEventIdRows = $topEventIds | ForEach-Object {
    [pscustomobject]@{ TableName = $_.TableName; EventID = $_.EventID; EventDescription = $_.EventDescription; LogCount = _RProp $_ 'LogCount' ''; BilledSizeGB = $_.BilledSizeGB }
}

# Aggregate CEF logs by DeviceVendor for the headline pie.
$cefByVendor = @{}
foreach ($r in $cefDevices) {
    $v = if ($r.DeviceVendor) { [string]$r.DeviceVendor } else { 'Unknown' }
    if (-not $cefByVendor.ContainsKey($v)) { $cefByVendor[$v] = 0 }
    $cefByVendor[$v] += [long]$r.LogCount
}
$cefPieRows = Format-PieSlices -Counts $cefByVendor -Limit 6
$cefChartBlock = if ($cefDevices.Count -gt 0) {
    @"

## CEF vendor mix

``````mermaid
pie showData title CommonSecurityLog by DeviceVendor (last {lookback-d})
$($cefPieRows -join [Environment]::NewLine)
``````

A single vendor dominating means CEF ingestion is mostly that source, likely a candidate for SAC-LOG-15 (`_CL` split) if volume is high.
"@
} else { '' }

# Log composition by host: who writes Syslog (by facility) and SecurityEvent.
$syslogContribRows = @(Read-RawArray 'syslog-contributors.json' | Where-Object { $_ } | ForEach-Object {
    [pscustomobject]@{ Computer = $_.Computer; Facility = $_.Facility; LogCount = $_.LogCount; SizeMB = $_.SizeMB }
})
$secEventHostRows = @(Read-RawArray 'securityevent-top-hosts.json' | Where-Object { $_ } | ForEach-Object {
    [pscustomobject]@{ Computer = $_.Computer; LogCount = $_.LogCount; SizeMB = $_.SizeMB }
})
Write-Section '13-data-source-hygiene.md' (@"
$(Format-Banner -Title "Data Source Hygiene")

Operational data-quality findings that drive ingestion-tuning actions: misrouted records, agent dual-collection, and noisy event types. Each table is independent and may show ``_None._`` when the workspace has nothing to report against that check.
$cefChartBlock

## CEF devices (last {lookback-d})

Per-vendor / per-product CEF record counts. A vendor + product combination with very low counts is usually either a misconfigured collector or a forwarder that needs filtering at source.

$(Format-Table -Items $cefDevRows -Columns 'DeviceVendor','DeviceProduct','LogCount')

## CEF records misrouted into Syslog (last {lookback-d})

A non-empty table here means a Linux syslog forwarder is shipping CEF-formatted records (a message starting ``CEF:`` or ``0|``) to the wrong workspace table, by forwarder and the vendor and product in the CEF header. Point a CEF data collection rule at the forwarder so the records land parsed in CommonSecurityLog ([SAC-LOG-23]).

$(Format-Table -Items $cefSyslogRows -Columns 'Computer','ProductVendor','LogCount')

## SecurityEvent duplicates (last 1h)

Computers reporting duplicate SecurityEvent records within a one-hour window: **Duplicate records** is how many distinct events arrived more than once, **Copies** the total rows those events produced. Almost always an MMA + AMA dual-collection misconfiguration or two DCRs collecting the same events; consolidate the collection path ([SAC-LOG-22]).

$(Format-Table -Items $secEvtDupeRows -Columns 'Computer','DuplicateRecords','Copies','DuplicateEventIds')

## Event IDs by billed size (last {lookback-d})

Every Windows event ID in the Event and SecurityEvent tables, largest billed size first, with the record count. Each row is a candidate for filtering at the DCR transform stage.

$(Format-Table -Items $topEventIdRows -Columns 'TableName','EventID','EventDescription','LogCount','BilledSizeGB')

## Syslog contributors (last {lookback-d})

Hosts and facilities writing to ``Syslog``, by record count and billed size. One host or facility out of proportion with the rest is the usual sign of a debug level left on or a forwarder relaying a whole network; both are DCR filter candidates.

$(Format-Table -Items $syslogContribRows -Columns 'Computer','Facility','LogCount','SizeMB')

## SecurityEvent hosts (last {lookback-d})

Every host writing ``SecurityEvent`` records, most records first. Domain controllers lead on every estate; a member server near the top usually means an audit policy or an event-ID set that is wider than the detections need.

$(Format-Table -Items $secEventHostRows -Columns 'Computer','LogCount','SizeMB')

[Filter Windows Security events via DCR (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/connect-windows-security-events)
"@)

# Section 14 — Coverage breakdowns
$azAct  = Read-RawArray 'azure-activity-coverage.json'
$azDiag = Read-RawArray 'azure-diagnostics-providers.json'
$xdrPres = Read-RawArray 'xdr-table-presence.json'

$azActRows = $azAct | ForEach-Object {
    [pscustomobject]@{ SubscriptionId = $_.SubscriptionId; LogCount = $_.LogCount }
}
$azDiagRows = $azDiag | ForEach-Object {
    [pscustomobject]@{ ResourceProvider = $_.ResourceProvider; LogCount = $_.LogCount }
}
# Entra ID tables: which of the well-known identity tables exist in the
# catalogue and which received data in the last 7 days.
$entraTableNames = @('SigninLogs','AuditLogs','AADNonInteractiveUserSignInLogs','AADServicePrincipalSignInLogs','AADManagedIdentitySignInLogs','AADProvisioningLogs','ADFSSignInLogs','AADRiskyUsers','AADUserRiskEvents','AADRiskyServicePrincipals','AADServicePrincipalRiskEvents','MicrosoftGraphActivityLogs','IdentityInfo')
$entraRows = @(foreach ($name in $entraTableNames) {
    $cat = @($workspaceTables | Where-Object { $_ -and (_RProp $_ 'name') -eq $name }) | Select-Object -First 1
    $use = @($tablesWithData | Where-Object { $_ -and (_RProp $_ 'DataType') -eq $name }) | Select-Object -First 1
    $gb7 = if ($use) { [math]::Round((_RendererNumber (_RProp $use 'BillableLast7d' 0)), 2) } else { 0 }
    $props = _RProp $cat 'properties'
    [pscustomobject]@{
        Table     = $name
        Plan      = if ($props) { [string](_RProp $props 'plan' '') } else { '' }
        Retention = if ($props) { [string](_RProp $props 'retentionInDays' '') } else { '' }
        Gb7d      = $gb7
        Status    = if ($gb7 -gt 0) { 'Receiving data' } elseif ($cat) { 'Catalogue only' } else { 'Not in catalogue' }
    }
})
$xdrRows = $xdrPres | ForEach-Object {
    [pscustomobject]@{ Table = $_.Type; RecordCount = $_.RecordCount }
}
# XDR-table-presence inputs for the bar chart. Short-label-axis with full
# names in the table below.
$xdrChartBlock = if ($xdrPres.Count -gt 0) {
    $xdrAxis = ($xdrRows | ForEach-Object {
        $n = $_.Table
        $s = if ($n.Length -gt 12) { $n.Substring(0,12) } else { $n }
        "`"$s`""
    }) -join ', '
    $xdrBars = ($xdrRows | ForEach-Object { [long]$_.RecordCount }) -join ', '
    $xdrYmax = [long]1
    foreach ($r in $xdrRows) { if ([long]$r.RecordCount -gt $xdrYmax) { $xdrYmax = [long]$r.RecordCount } }
    @"

## XDR table activity (last {lookback-d})

``````mermaid
---
config:
  xyChart:
    width: 1400
    height: 480
---
xychart-beta
    title "Defender XDR tables: records ingested in the last {lookback-d}"
    x-axis [$xdrAxis]
$(Format-XyFullLabels @($xdrRows | ForEach-Object { $_.Table }))
    y-axis "Records" 0 --> $($xdrYmax + ([math]::Ceiling($xdrYmax * 0.1)))
    bar [$xdrBars]
``````

A short bar means that XDR surface (email / device / identity / cloud-app) isn't producing data. Bar at 0 = the workspace's XDR connector is silent for that table: investigate it, or accept it (some XDR products gate certain tables behind licensing).
"@
} else { '' }

# AzureDiagnostics by category, and Azure Firewall in both its forms: the
# legacy AzureDiagnostics categories and the resource-specific AZFW* tables.
$azDiagCategoryRows = @(Read-RawArray 'azure-diagnostics-categories.json' | Where-Object { $_ } | ForEach-Object {
    [pscustomobject]@{ ResourceProvider = $_.ResourceProvider; Category = $_.Category; LogCount = $_.LogCount }
})
$fwCategoryRows = @(Read-RawArray 'azure-firewall-categories.json' | Where-Object { $_ } | ForEach-Object {
    [pscustomobject]@{
        Category = $_.Category
        Form     = $(if ([string]$_.Category -like 'AZFW*') { 'Resource-specific category' } else { 'Legacy category' })
        LogCount = $_.LogCount
    }
})
$fwTableRows = @($tablesWithData | Where-Object { $_ -and [string](_RProp $_ 'DataType' '') -like 'AZFW*' } | ForEach-Object {
    [pscustomobject]@{ Table = $_.DataType; Gb7d = [math]::Round((_RendererNumber (_RProp $_ 'BillableLast7d' 0)), 2); LastIngested = Format-DateUtc (_RProp $_ 'LastIngested') }
})
$fwLegacyRows = @($fwCategoryRows | Where-Object { $_.Form -eq 'Legacy category' })
$fwVerdict = if (-not (Test-Path (Join-Path $rawRoot 'azure-firewall-categories.json'))) { '_Not captured in this snapshot._' }
    elseif ($fwLegacyRows.Count -gt 0 -and ($fwTableRows.Count -gt 0 -or @($fwCategoryRows | Where-Object { $_.Form -ne 'Legacy category' }).Count -gt 0)) {
        '**Collected twice.** Azure Firewall writes legacy categories into AzureDiagnostics and the resource-specific form as well; remove the legacy diagnostic setting to stop paying for the same events twice ([SAC-LOG-06]).'
    }
    elseif ($fwCategoryRows.Count -eq 0 -and $fwTableRows.Count -eq 0) { '_No Azure Firewall logs in the last {lookback}._' }
    else { 'Azure Firewall logs arrive in one form only.' }

Write-Section '14-coverage-breakdowns.md' (@"
$(Format-Banner -Title "Coverage Breakdowns")

Per-source coverage gaps revealed by direct table queries. A subscription, resource provider, or XDR table missing from these tables is a coverage gap to triage.
$xdrChartBlock

## AzureActivity per subscription (last {lookback-d})

Each row is a subscription shipping Activity Logs into the workspace. Subscriptions absent from this table are either not connected or have no activity in the period.

$(Format-Table -Items $azActRows -Columns 'SubscriptionId','LogCount')

## AzureDiagnostics per resource provider (last {lookback-d})

Resource providers emitting diagnostic settings into the workspace. Maps directly to which Azure services have diagnostic settings wired up to this workspace.

$(Format-Table -Items $azDiagRows -Columns 'ResourceProvider','LogCount')

## AzureDiagnostics per category (last {lookback-d})

Every diagnostic category writing into AzureDiagnostics, by resource provider, busiest first. A service with a resource-specific table available (Azure Firewall, Key Vault, Application Gateway and others) is cheaper and easier to query in that form ([SAC-LOG-18]).

$(Format-Table -Items $azDiagCategoryRows -Columns 'ResourceProvider','Category','LogCount')

## Azure Firewall categories (last {lookback-d})

$fwVerdict

$(Format-Table -Items $fwCategoryRows -Columns 'Category','Form','LogCount' -EmptyMessage (Get-EmptyMessage 'azure-firewall-categories.json' '_No Azure Firewall categories in AzureDiagnostics._'))

Resource-specific Azure Firewall tables with data:

$(Format-Table -Items $fwTableRows -Columns 'Table','Gb7d','LastIngested')

## XDR table presence (last {lookback-d})

Subset of well-known Defender XDR tables that have received data in the last {lookback}. Empty rows would suggest XDR is connected but a particular surface (email, identity, device) is not producing data.

$(Format-Table -Items $xdrRows -Columns 'Table','RecordCount')

## Entra ID table presence (last {recent-d})

The well-known Microsoft Entra ID tables, with their plan and retention and whether they received billable data in the last {recent}. "Catalogue only" means the schema exists but nothing is writing to it, usually a connector data type that was never enabled.

$(Format-Table -Items $entraRows -Columns 'Table','Plan','Retention','Gb7d','Status')

[Microsoft Sentinel data connector reference (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/data-connectors-reference)
"@)

# Section 15 — Incidents (TOC 4.10)
# $incSummary and $incMttr are read at the top of the file (the estate flow
# on 00 and 01 needs them before this section runs).
$incByRule  = Read-RawArray 'incidents-by-rule.json'
# Alert volume by severity and by the product that raised it, from the same
# SecurityAlert aggregate the dashboard uses (every product, not only
# Sentinel rules).
$alertVolumeTotal = [long]0
foreach ($v in @($ruleVolumesAll | Where-Object { $_ })) { $alertVolumeTotal += [long](_RendererNumber (_RProp $v 'Alerts' 0)) }
$sevOrder = @{ High = 0; Medium = 1; Low = 2; Informational = 3 }
$sevAgg = [ordered]@{}
foreach ($v in @($ruleVolumesAll | Where-Object { $_ })) {
    $s = [string](_RProp $v 'AlertSeverity' '')
    if (-not $s) { $s = 'Other' }
    if (-not $sevAgg.Contains($s)) { $sevAgg[$s] = [long]0 }
    $sevAgg[$s] += [long](_RendererNumber (_RProp $v 'Alerts' 0))
}
$alertSeverityRows = @($sevAgg.GetEnumerator() | Sort-Object { if ($sevOrder.ContainsKey([string]$_.Key)) { $sevOrder[[string]$_.Key] } else { 9 } } | ForEach-Object {
    [pscustomobject]@{ Severity = $_.Key; Alerts = $_.Value; Share = $(if ($alertVolumeTotal -gt 0) { "$([math]::Round(100.0 * $_.Value / $alertVolumeTotal, 1))%" } else { '0%' }) }
})
$productLabel = @{ 'Microsoft Defender Advanced Threat Protection' = 'Defender for Endpoint'; 'Azure Sentinel' = 'Microsoft Sentinel' }
$srcAgg = [ordered]@{}
foreach ($v in @($ruleVolumesAll | Where-Object { $_ })) {
    $p = [string](_RProp $v 'ProductName' '')
    if (-not $p) { $p = 'Other' }
    if ($productLabel.ContainsKey($p)) { $p = $productLabel[$p] }
    if (-not $srcAgg.Contains($p)) { $srcAgg[$p] = [pscustomobject]@{ Source = $p; Alerts = [long]0; Rules = 0 } }
    $srcAgg[$p].Alerts += [long](_RendererNumber (_RProp $v 'Alerts' 0))
    $srcAgg[$p].Rules++
}
$alertSourceRows = @($srcAgg.Values | Sort-Object { -$_.Alerts } | ForEach-Object {
    [pscustomobject]@{ Source = $_.Source; Alerts = $_.Alerts; Rules = $_.Rules; Share = $(if ($alertVolumeTotal -gt 0) { "$([math]::Round(100.0 * $_.Alerts / $alertVolumeTotal, 1))%" } else { '0%' }) }
})
$incDaily   = Read-RawArray 'incidents-daily-metrics.json' | Select-Object -First 1

function Format-MinutesScalar {
    param($Value, $CountAcknowledged)
    # KQL returns the literal string "NaN" when an aggregate had no rows to
    # average over (e.g. avg(int(null)) across zero rows), and Save-Json
    # writes that through verbatim. Treat any non-numeric input as
    # unavailable so the report shows "n/a" instead of the noisy "NaN min".
    if ($null -eq $Value) { return 'n/a' }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s) -or $s -eq 'NaN' -or $s -eq 'null') { return 'n/a' }
    $d = 0.0
    if (-not [double]::TryParse($s, [ref]$d)) { return 'n/a' }
    return ("$([math]::Round($d, 1)) min")
}
$mttrLine = if ($incMttr -and $incMttr.ClosedCount) {
    $ackCount = $null
    if ($incMttr.PSObject.Properties.Name -contains 'AcknowledgedCount') {
        $ackCount = $incMttr.AcknowledgedCount
    }
    $mttaStr  = Format-MinutesScalar -Value $incMttr.MTTAMinutes -CountAcknowledged $ackCount
    $mttrStr  = Format-MinutesScalar -Value $incMttr.MTTRMinutes -CountAcknowledged $incMttr.ClosedCount
    $ackSuffix = if ($null -ne $ackCount) {
        "  ·  **Acknowledged:** $ackCount of $($incMttr.ClosedCount)"
    } else { '' }
    "**MTTA:** $mttaStr  ·  **MTTR:** $mttrStr  ·  **Closed:** $($incMttr.ClosedCount) (last {lookback-d})$ackSuffix"
} else { '_No closed incidents in the last {lookback}; MTTA/MTTR not available._' }

$dailyLine = if ($incDaily -and $null -ne $incDaily.AvgDailyUniqueIncidents) {
    "**Avg daily unique incidents:** $($incDaily.AvgDailyUniqueIncidents)  ·  **Peak daily new incidents:** $($incDaily.PeakDailyNewIncidents) (last {lookback-d})"
} else { '_No incident-flow metrics available._' }

# Closed-without-ack count for the state diagram note. The fixture's
# AcknowledgedCount field was added by the MTTA-NaN fix; older captures
# may not have it.
$closedCount = if ($incMttr) { [int]($incMttr.ClosedCount) } else { 0 }
$ackCountForState = 0
if ($incMttr -and ($incMttr.PSObject.Properties.Name -contains 'AcknowledgedCount')) {
    $ackCountForState = [int]$incMttr.AcknowledgedCount
}
$unackCount = $closedCount - $ackCountForState
$totalIncidents = if ($incSummary -and $incSummary.Count) { [int]$incSummary.Count } else { $closedCount }

# Closure verdicts (ByClassification arrived with the 2.2 collector; older
# captures have no bag and get no chart) and the per-rule effectiveness
# table shared with section 21.
$incClassBag = if ($incSummary -and $incSummary.PSObject.Properties['ByClassification']) { _RendererBag $incSummary.ByClassification } else { [ordered]@{} }
$incClassTotal = 0
foreach ($v in $incClassBag.Values) { $incClassTotal += [long]$v }
$incOutcomeBlock = if ($incClassTotal -gt 0) {
    $classRows = ($incClassBag.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | ForEach-Object { "    `"$($_.Key)`" : $($_.Value)" }) -join [Environment]::NewLine
@"

## Incident outcomes (closed, last {lookback-d})

``````mermaid
pie showData title Closed incidents by classification ({lookback-d})
$classRows
``````

Undetermined and Unclassified closures carry no verdict, so they feed neither the false-positive rate nor rule tuning; [SAC-INC-02] fires when they are the majority.
"@
} else { '' }
# A Sentinel rule's incidents are keyed on its rule id, so the table names
# the rule as the workspace does, not by the name its alerts carry (a rule
# can give its alerts their own names). An id with no rule in the inventory
# keeps the alert name.
$ruleNameById = @{}
foreach ($r in @($rules | Where-Object { $_ })) {
    $rid = ([string](_RProp $r 'name' '')).ToLowerInvariant()
    $rdn = [string](_RProp (_RProp $r 'properties') 'displayName' '')
    if ($rid -and $rdn) { $ruleNameById[$rid] = $rdn }
}
# Sentinel rules first, then other products' alerts by name; Source is the
# collector's column when present, else derived from the rule id.
$effectivenessRows = @($ruleEffectiveness | Sort-Object { -(_RendererNumber $_.Incidents) } | Sort-Object { if ($_.PSObject.Properties['AlertRuleId'] -and $_.AlertRuleId) { 0 } else { 1 } } -Stable | ForEach-Object {
    $src = if ($_.PSObject.Properties['Source'] -and $_.Source) { [string]$_.Source }
           elseif ($_.PSObject.Properties['AlertRuleId'] -and $_.AlertRuleId) { 'Analytics rule' }
           elseif ($_.PSObject.Properties['Product'] -and $_.Product) { [string]$_.Product }
           else { 'Other' }
    $rk = if ($_.PSObject.Properties['AlertRuleId'] -and $_.AlertRuleId) { (([string]$_.AlertRuleId).ToLowerInvariant() -split '/')[-1] } else { '' }
    [pscustomobject]@{
        Rule         = $(if ($rk -and $ruleNameById.ContainsKey($rk)) { $ruleNameById[$rk] } else { $_.RuleName })
        Source       = $src
        Incidents    = [int](_RendererNumber $_.Incidents)
        Closed       = [int](_RendererNumber $_.Closed)
        TP           = [int](_RendererNumber $_.TruePositive)
        FP           = [int](_RendererNumber $_.FalsePositive)
        BP           = [int](_RendererNumber $_.BenignPositive)
        Undetermined = [int](_RendererNumber $_.Undetermined)
        FPRate       = _RendererNumber $_.FPRate
    }
})

# The last 7 days, as the health check reports them: incidents updated in
# the window at their latest state, and the alert names behind them.
$incident7dBlock = if ($incSummary -and $incSummary.PSObject.Properties['Count7d']) {
    $mtta7 = if ($incMttr -and $incMttr.PSObject.Properties['MTTAMinutes7d']) { Format-MinutesScalar -Value $incMttr.MTTAMinutes7d } else { 'n/a' }
    $mttr7 = if ($incMttr -and $incMttr.PSObject.Properties['MTTRMinutes7d']) { Format-MinutesScalar -Value $incMttr.MTTRMinutes7d } else { 'n/a' }
    @"
| | |
|---|---:|
| Incidents | $([int](_RendererNumber $incSummary.Count7d)) |
| Closed | $([int](_RendererNumber (_RProp $incSummary 'Closed7d' 0))) |
| Closed as true positive | $([int](_RendererNumber (_RProp $incSummary 'TruePositive7d' 0))) |
| Closed as false positive | $([int](_RendererNumber (_RProp $incSummary 'FalsePositive7d' 0))) |
| Raised through Defender XDR (unified) | $([int](_RendererNumber (_RProp $incSummary 'Unified7d' 0))) |
| MTTA (incidents closed in the window) | $mtta7 |
| MTTR (incidents closed in the window) | $mttr7 |
"@
} else { '_Not captured in this snapshot._' }
$incProviderBag = if ($incSummary -and $incSummary.PSObject.Properties['ByProvider']) { _RendererBag $incSummary.ByProvider } else { $null }
$incProviderRows = if ($incProviderBag) {
    @($incProviderBag.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | ForEach-Object { [pscustomobject]@{ Provider = $_.Key; Incidents = $_.Value } })
} else { @() }
$alertVolumes = @(Read-RawArray 'analytics-rule-volumes.json' | Where-Object { $_ })
$alert7dCaptured = @($alertVolumes | Where-Object { $_.PSObject.Properties['Alerts7d'] }).Count -gt 0
$alertProvider7dRows = @($alertVolumes | Where-Object { $_.PSObject.Properties['Alerts7d'] -and [long]$_.Alerts7d -gt 0 } |
    Sort-Object @{ Expression = { [long]$_.Alerts7d }; Descending = $true }, AlertName |
    ForEach-Object { [pscustomobject]@{ Provider = [string](_RProp $_ 'ProviderName' ''); Product = $_.ProductName; Alert = $_.AlertName; Severity = $_.AlertSeverity; Alerts = [long]$_.Alerts7d } })

# The incident lifecycle as data for the SharePoint graphic (the chart web
# part's incident-lifecycle visual): the window's incidents at their
# current status, how the closed ones got there (acknowledged first, or
# closed straight from New), the response times, how they were classified
# and who closed them. It rides in the Mermaid block on a %% line, which
# Mermaid ignores and ConvertFrom-BlueprintMermaid reads; a figure the
# capture lacks is null and the graphic leaves it out.
function ConvertTo-LifecycleList {
    param([System.Collections.IDictionary]$Bag, [string[]]$Order, [hashtable]$Labels)
    if (-not $Bag -or -not $Bag.Count) { return ,@() }
    $keys = @($Bag.Keys | ForEach-Object { [string]$_ })
    $sorted = if ($Order) { @($Order | Where-Object { $keys -contains $_ }) + @($keys | Where-Object { $Order -notcontains $_ } | Sort-Object) }
              else { @($keys | Sort-Object @{ Expression = { [long]$Bag[$_] }; Descending = $true }, @{ Expression = { $_ } }) }
    return ,@($sorted | Where-Object { [long]$Bag[$_] -gt 0 } | ForEach-Object {
        [ordered]@{ label = $(if ($Labels -and $Labels.ContainsKey($_)) { $Labels[$_] } else { $_ }); count = [long]$Bag[$_] }
    })
}
$incStatusBag = if ($incSummary -and $incSummary.PSObject.Properties['ByStatus']) { _RendererBag $incSummary.ByStatus } else { $null }
$incAckKnown = $incMttr -and ($incMttr.PSObject.Properties.Name -contains 'AcknowledgedCount')
$incMinutes = { param($v) $s = [string]$v; $d = 0.0; if ($null -ne $v -and $s -ne 'NaN' -and [double]::TryParse($s, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { [math]::Round($d, 1) } else { $null } }
$lifecycleVisual = [ordered]@{
    days           = 30
    raised         = $totalIncidents
    new            = $(if ($incStatusBag) { [long](_RProp ([pscustomobject]$incStatusBag) 'New' 0) } else { $null })
    active         = $(if ($incStatusBag) { [long](_RProp ([pscustomobject]$incStatusBag) 'Active' 0) } else { $null })
    closed         = $(if ($incStatusBag) { [long](_RProp ([pscustomobject]$incStatusBag) 'Closed' 0) } elseif ($incMttr) { $closedCount } else { $null })
    acknowledged   = $(if ($incAckKnown) { $ackCountForState } else { $null })
    unacknowledged = $(if ($incAckKnown) { $unackCount } else { $null })
    mttaMinutes    = $(if ($incMttr) { & $incMinutes (_RProp $incMttr 'MTTAMinutes') } else { $null })
    mttrMinutes    = $(if ($incMttr) { & $incMinutes (_RProp $incMttr 'MTTRMinutes') } else { $null })
    unified        = $(if ($incSummary -and $incSummary.PSObject.Properties['Unified']) { [long](_RendererNumber $incSummary.Unified) } else { $null })
    openBySeverity = ConvertTo-LifecycleList -Bag $(if ($incSummary -and $incSummary.PSObject.Properties['OpenBySeverity']) { _RendererBag $incSummary.OpenBySeverity } else { $null }) -Order 'High', 'Medium', 'Low', 'Informational'
    classification = ConvertTo-LifecycleList -Bag $incClassBag -Order 'TruePositive', 'BenignPositive', 'FalsePositive', 'Undetermined', 'Unclassified' -Labels @{ TruePositive = 'True positive'; BenignPositive = 'Benign positive'; FalsePositive = 'False positive' }
    closedBy       = ConvertTo-LifecycleList -Bag $(if ($incSummary -and $incSummary.PSObject.Properties['ClosedBy']) { _RendererBag $incSummary.ClosedBy } else { $null }) -Labels @{ AutomationRule = 'Automation rule'; DefenderXdr = 'Defender XDR' }
    check          = [ordered]@{ id = 'SAC-INC-05'; fired = $script:FiredFindingIds.ContainsKey('SAC-INC-05') }
}
$lifecycleVisualLine = Format-VisualLine -Kind 'incident-lifecycle' -Data $lifecycleVisual

$incidentBody = @"
$(Format-Banner -Title "Incidents  (TOC 4.10)")

> Aggregate-only. The Blueprint never exports incident bodies, alert payloads or entity detail, only counts and derived SOC-efficiency metrics.

$mttrLine

$dailyLine

> Alert volumes are in [16-alerts.md](16-alerts.md), and alert volume and closure verdicts per rule in [21-rule-performance.md](21-rule-performance.md). When triaging a high MTTR, start with the rules driving raw alert load: high alert volume from a single rule usually inflates time-to-acknowledge for everything else in the queue.

## Incident lifecycle

``````mermaid
stateDiagram-v2
$lifecycleVisualLine
    [*] --> New : Alert fires
    New --> Active : Analyst opens
    New --> Closed : Auto-suppress<br/>(SAC-INC-05 fires here)
    Active --> InProgress : Investigation begins
    InProgress --> Active : Re-assigned
    InProgress --> Closed : Resolved
    Closed --> [*]

    state Closed {
        [*] --> TruePositive
        [*] --> FalsePositive
        [*] --> BenignPositive
        [*] --> Undetermined
    }

    note right of New
        $totalIncidents incidents in {lookback-d}
        $closedCount reached Closed
        $unackCount closed without acknowledgement
    end note
``````

## Analyst journey: a typical high-severity incident

``````mermaid
---
config:
  journey:
    diagramMarginX: 60
    diagramMarginY: 30
    leftMargin: 160
    width: 220
    height: 80
    taskFontSize: 12
---
journey
    title Analyst journey: a typical high-severity incident
    section Alert created
        Alert fires: 5: Sentinel
        Incident created: 5: Sentinel
    section Triage
        Notify SOC channel: 4: Teams
        Open incident: 4: Analyst
        Read entity timelines: 3: Analyst
        KQL hunt for context: 2: Analyst
    section Investigation
        Identify scope: 2: Analyst
        Run enrichment playbook: 4: Playbook
        Decide remediation: 3: Analyst, Lead
    section Resolution
        Apply remediation: 3: Analyst
        Document + close: 4: Analyst
``````

Dips at "KQL hunt for context" and "Identify scope" mark the SOC pain points. Workspaces firing [SAC-AUT-01] (no automation) see steeper dips because every step is manual.

## Incidents by rule (last {lookback-d})

Every rule title that produced an incident in the last {lookback}, busiest first. Alert volume per rule is in [21-rule-performance.md](21-rule-performance.md#by-alert-volume-last-{lookback-d}).

$(Format-Table -Items ($incByRule | ForEach-Object { [pscustomobject]@{ Rule = $_.Title; Incidents = $_.Incidents } }) -Columns 'Rule','Incidents')

$incOutcomeBlock

## Incident detail by provider / product / first rule (last {lookback-d})

Per-provider, per-product, per-first-rule alert counts joined to the incidents they belong to. The FirstRule ID resolves to its full name via the [20-analytics-rules.md](20-analytics-rules.md) table.

$(Format-Table -Items (Read-RawArray 'incidents-detail-by-provider.json' | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ Provider = $_.ProviderName; Product = $_.ProductName; FirstRule = $_.FirstRule; AlertCount = $_.AlertCount } }) -Columns 'Provider','Product','FirstRule','AlertCount')

## Incident metrics (last {recent-d})

Incidents updated in the last {recent}, each at its latest state. The {lookback} view is at the top of the page.

$incident7dBlock

## Incidents by provider (last {lookback-d})

Which service created the incident. ``Microsoft XDR`` (or ``Microsoft 365 Defender``) means the incident came through the unified Defender XDR queue rather than from a Sentinel rule.

$(Format-Table -Items $incProviderRows -Columns 'Provider','Incidents' -EmptyMessage $(if ($incSummary -and -not $incSummary.PSObject.Properties['ByProvider']) { '_Not captured in this snapshot._' } else { '_None._' }))

[Sentinel incidents (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/investigate-cases)
"@
Write-Section '15-incidents.md' $incidentBody

# Section 16: alerts, across every product that raises them.
$alertsBody = @"
$(Format-Banner -Title "Alerts")

> Aggregate-only, like the incidents page: alert names, products and counts from ``SecurityAlert``, never alert payloads or entities. Incidents are in [15-incidents.md](15-incidents.md); alert volume per rule with its closure verdicts is in [21-rule-performance.md](21-rule-performance.md).

## Alert volume by severity (last {lookback-d})

Alerts raised in the last {lookback} grouped by severity, from ``SecurityAlert`` across every product, not only Sentinel rules.

$(Format-Table -Items $alertSeverityRows -Columns 'Severity','Alerts','Share')

## Alerts by detection source (last {lookback-d})

Which security product raised the alert volume. Sentinel analytics rules appear as Microsoft Sentinel; the rest are first-party detections that run inside their product. ``Rules`` is the number of distinct detections per product.

$(Format-Table -Items $alertSourceRows -Columns 'Source','Alerts','Rules','Share')

## Alert volumes by provider (last {recent-d})

Every alert name that fired in the last {recent}, with the provider and product that raised it, busiest first.

$(Format-Table -Items $alertProvider7dRows -Columns 'Provider','Product','Alert','Severity','Alerts' -EmptyMessage $(if ($alert7dCaptured -or $alertVolumes.Count -eq 0) { '_No alerts in the last {recent}._' } else { '_Not captured in this snapshot._' }))

[Sentinel alerts and incidents (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/investigate-cases)
"@
Write-Section '16-alerts.md' $alertsBody

# Section 21 — Rules by alert volume (TOC 4.11.2)
$ruleVolumes = Read-RawArray 'analytics-rule-volumes.json'
$volChartBlock = if ($ruleVolumes.Count -gt 0) {
    $top10 = $ruleVolumes | Select-Object -First 10
    $volAxis = ($top10 | ForEach-Object {
        $n = $_.AlertName
        # Use first significant word, max 12 chars, no parens
        $clean = ($n -replace '\(.*?\)', '' -replace '\[.*?\]', '').Trim()
        $words = $clean -split '\s+'
        $label = if ($words.Count -gt 0) { $words[0] } else { 'rule' }
        if ($label.Length -gt 12) { $label = $label.Substring(0,12) }
        "`"$label`""
    }) -join ', '
    $volBars = ($top10 | ForEach-Object { [long]$_.Alerts }) -join ', '
    $volMax = [long]1
    foreach ($r in $top10) { if ([long]$r.Alerts -gt $volMax) { $volMax = [long]$r.Alerts } }
    @"

### Top 10 noisy rules by alert volume

``````mermaid
---
config:
  xyChart:
    width: 1400
    height: 480
---
xychart-beta
    title "Top 10 alerting rules: alert count (last {lookback-d})"
    x-axis [$volAxis]
$(Format-XyFullLabels @($top10 | ForEach-Object { $_.AlertName }))
    y-axis "Alerts" 0 --> $($volMax + ([math]::Ceiling($volMax * 0.1) + 1))
    bar [$volBars]
``````

The chart's axis uses short labels, and the table below has the full rule names. A single tall bar usually means a tuning candidate (over-broad threshold, missing suppression).
"@
} else { '' }

$volumeSection = @"

## By alert volume (last {lookback-d})

Every alert name raised in the last {lookback}, most alerts first, derived from ``SecurityAlert``. A rule firing thousands of alerts a day is usually either a misconfiguration (too-low threshold) or a high-fidelity signal; review and tune.
$volChartBlock

$(Format-Table -Items ($ruleVolumes | ForEach-Object { [pscustomobject]@{ Rule = $_.AlertName; Product = $_.ProductName; Severity = $_.AlertSeverity; Alerts = $_.Alerts } }) -Columns 'Rule','Product','Severity','Alerts')

## Rule effectiveness (last {lookback-d})

Incidents per detection with their closure verdicts: Sentinel analytics rules first, then alerts from other products keyed by alert name with the product as **Source**. **FP rate** is false positives over closed incidents, in percent. A high volume with a high false-positive rate is the first tuning candidate; a high volume closed mostly as true positive is a rule earning its keep.

$(Format-Table -Items $effectivenessRows -Columns 'Rule','Source','Incidents','Closed','TP','FP','BP','Undetermined','FPRate')

## Noisy rules (closed mostly as false positive)

Sentinel analytics rules with 20 or more incidents closed in the last {lookback} and more than 70% of them closed as false positive: the rules to tune first ([SAC-DET-06]). Alerts from other products are tuned in their own portal, so they are not listed.

$(Format-Table -Items @($effectivenessRows | Where-Object { $_.Source -eq 'Analytics rule' -and $_.Closed -ge 20 -and [double]$_.FPRate -gt 70 } | Sort-Object @{ Expression = { [double]$_.FPRate }; Descending = $true }, Rule) -Columns 'Rule','Incidents','Closed','FP','FPRate' -EmptyMessage $(if ($ruleEffectiveness.Count) { '_No analytics rule closed mostly as false positive._' } else { '_Not captured in this snapshot._' }))
"@

# Section 22 — Microsoft security rules (TOC 4.11.3)
$msRules = @($rules | Where-Object {
    $kind = $_.kind
    $tn = $_.properties.alertRuleTemplateName
    ($tn -and ($tn -match '^[a-f0-9-]{36}$')) -or ($kind -in @('Fusion','MicrosoftSecurityIncidentCreation','MLBehaviorAnalytics','ThreatIntelligence'))
})
# Microsoft rules by severity for the headline pie.
$msSevCounts = @{ 'High' = 0; 'Medium' = 0; 'Low' = 0; 'Informational' = 0 }
foreach ($r in $msRules) {
    $sev = if ($r.properties.severity) { [string]$r.properties.severity } else { 'Unknown' }
    if (-not $msSevCounts.ContainsKey($sev)) { $msSevCounts[$sev] = 0 }
    $msSevCounts[$sev]++
}
$msPieRows = $msSevCounts.GetEnumerator() | Where-Object { $_.Value -gt 0 } | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | ForEach-Object {
    "    `"$($_.Key)`" : $($_.Value)"
}
$msChartBlock = if ($msRules.Count -gt 0) {
    @"

### Microsoft rules by severity

``````mermaid
pie showData title Microsoft-managed rules by severity
$($msPieRows -join [Environment]::NewLine)
``````

$($msRules.Count) Microsoft-managed rule(s). High-severity bias is the norm, as these rules are pre-tuned by Microsoft.
"@
} else { '' }

$msRulesSection = @"

## Microsoft-managed rules

Rules backed by a Microsoft template, or built-in Microsoft-managed kinds (Fusion, MicrosoftSecurityIncidentCreation, MLBehaviorAnalytics, ThreatIntelligence). These are not user-editable; tuning is via enable/disable and the per-rule incident-grouping config.
$msChartBlock

$(Format-Table -Items ($msRules | ForEach-Object { [pscustomobject]@{ Kind = $_.kind; Name = $_.properties.displayName; Severity = $_.properties.severity; Enabled = if ($_.properties.enabled) {'Yes'} else {'No'} } }) -Columns 'Kind','Name','Severity','Enabled')
"@

# Section 23 — Modifications (TOC 4.11.4)
# Sort uses ISO-formatted strings — ISO 8601 sorts lexically in the same
# order as chronologically, so Format-DateUtc output preserves ordering.
$modifiedRows = $rules | ForEach-Object {
    $lm = $null
    if ($_.properties -and ($_.properties.PSObject.Properties.Name -contains 'lastModifiedUtc')) { $lm = $_.properties.lastModifiedUtc }
    [pscustomobject]@{
        Name = $_.properties.displayName
        Kind = $_.kind
        LastModified = Format-DateUtc $lm
        Enabled = if ($_.properties.enabled) {'Yes'} else {'No'}
    }
} | Where-Object { $_.LastModified } | Sort-Object -Property LastModified -Descending
# Modifications-per-month bar over the last 12 months.
$monthBuckets = [ordered]@{}
$now = (Get-Date).ToUniversalTime()
for ($i = 11; $i -ge 0; $i--) {
    $m = $now.AddMonths(-$i)
    $key = $m.ToString('yyyy-MM', [System.Globalization.CultureInfo]::InvariantCulture)
    $monthBuckets[$key] = 0
}
foreach ($r in $rules) {
    $lm = if ($r.properties -and ($r.properties.PSObject.Properties.Name -contains 'lastModifiedUtc')) { $r.properties.lastModifiedUtc } else { $null }
    if (-not $lm) { continue }
    $parsed = [datetime]::MinValue
    if ($lm -is [datetime]) { $parsed = $lm }
    elseif (-not [datetime]::TryParse([string]$lm, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { continue }
    $key = $parsed.ToUniversalTime().ToString('yyyy-MM', [System.Globalization.CultureInfo]::InvariantCulture)
    if ($monthBuckets.Contains($key)) { $monthBuckets[$key]++ }
}
$modAxis = ($monthBuckets.Keys | ForEach-Object { "`"$($_.Substring(5,2))`"" }) -join ', '
$modBars = ($monthBuckets.Values) -join ', '
$modMax = 1
foreach ($v in $monthBuckets.Values) { if ($v -gt $modMax) { $modMax = $v } }

$modificationsSection = @"

## Recent modifications

### Modifications per month (last 12 months)

``````mermaid
xychart-beta
    title "Rule modifications per month, last 12 months"
    x-axis [$modAxis]
    y-axis "Modifications" 0 --> $($modMax + 1)
    bar [$modBars]
``````

Each bar is one calendar month (MM). Tempo reveals release cadence: sustained months at zero suggest abandoned content; periodic spikes usually align with vendor content-pack updates.

Every rule, most recently modified first. Cross-reference with [Test-SentinelRuleDrift.ps1](https://github.com/noodlemctwoodle/Sentinel-As-Code/blob/main/Tools/Test-SentinelRuleDrift.ps1): a recent modification on a rule that has a Content Hub template or repo YAML source-of-truth indicates portal drift.

$(Format-Table -Items $modifiedRows -Columns 'Name','Kind','LastModified','Enabled')
"@

# Section 24 — By Content Solution (TOC 4.11.5)
$metadataAll = Read-RawArray 'metadata.json'
$ruleToSolution = @{}
foreach ($m in $metadataAll) {
    if ($m.properties.kind -eq 'AnalyticsRule' -and $m.properties.parentId) {
        $ruleId = ($m.properties.parentId -split '/')[-1]
        $ruleToSolution[$ruleId] = $m.properties.source.name
    }
}
$bySolution = $rules | ForEach-Object {
    $sol = if ($ruleToSolution.ContainsKey($_.name)) { $ruleToSolution[$_.name] } else { '(custom or unmapped)' }
    [pscustomobject]@{
        Solution = $sol
        Rule     = $_.properties.displayName
        Enabled  = if ($_.properties.enabled) {'Yes'} else {'No'}
        Severity = $_.properties.severity
    }
} | Sort-Object Solution, Rule
# Top solutions by rule count (top 8 + Other) for the headline pie.
$solCounts = @{}
foreach ($r in $bySolution) {
    $s = if ($r.Solution) { [string]$r.Solution } else { 'Unknown' }
    if (-not $solCounts.ContainsKey($s)) { $solCounts[$s] = 0 }
    $solCounts[$s]++
}
$topSols = $solCounts.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | Select-Object -First 8
$otherSolCount = 0
$counted = 0
foreach ($e in $solCounts.GetEnumerator()) { $counted += $e.Value }
$top8Sum = ($topSols | ForEach-Object { $_.Value } | Measure-Object -Sum).Sum
$otherSolCount = $counted - $top8Sum

$solPieRows = $topSols | ForEach-Object { "    `"$($_.Key)`" : $($_.Value)" }
if ($otherSolCount -gt 0) { $solPieRows += "    `"Other`" : $otherSolCount" }

$solutionSection = @"

## By Content Hub solution

### Top contributing solutions

``````mermaid
pie showData title Analytics rules by Content Hub solution (top 8)
$($solPieRows -join [Environment]::NewLine)
``````

$($solCounts.Count) distinct solution(s) contributing $counted total rule(s). A heavy long-tail "(custom or unmapped)" slice usually means repo-deployed content not registered against any Content Hub solution.

Rules grouped by the Content Hub solution that ships them, derived from the metadata link table. '(custom or unmapped)' covers rules that have no metadata association, typically repo-deployed custom rules.

$(Format-Table -Items $bySolution -Columns 'Solution','Rule','Enabled','Severity')
"@

# Stale rules and template drift for section 22, moved from the rule
# inventory on section 20.
$staleSection = @"

## Stale rules (enabled, last modified over a year ago)

Rules in this table are still firing but haven't been reviewed in over twelve months. Stale thresholds, deprecated KQL operators, and dropped data sources are all common causes. Each row is a candidate for explicit re-review or retirement.

$(Format-Table -Items $mouldyRows -Columns 'Name','Kind','Severity','LastModified')

## Rules behind their latest template version

Rules where the deployed ``templateVersion`` is older than the version available in the Content Hub catalogue. Update via the rule's "Update from template" action in the portal, or re-deploy from the matching repo YAML.

$(Format-Table -Items $mismatchRows -Columns 'Name','Kind','CurrentVersion','LatestVersion')
"@

# Rule complexity: a heuristic over each Scheduled or NRT rule's query, so
# the longest, most joined queries (the ones that time out or quietly
# return nothing after a schema change) are easy to find. Idea from the
# health check contributed by thinkndle; the scoring here is this project's.
$complexityRows = @($(foreach ($r in $rules) {
    if (-not $r -or $r.kind -notin @('Scheduled', 'NRT')) { continue }
    $props = _RProp $r 'properties'
    $q = [string](_RProp $props 'query' '')
    if ([string]::IsNullOrWhiteSpace($q)) { continue }
    $lets   = ([regex]::Matches($q, '(?im)^\s*let\s')).Count
    $joins  = ([regex]::Matches($q, '(?i)\bjoin\b')).Count
    $unions = ([regex]::Matches($q, '(?i)\bunion\b')).Count
    $ents   = @(_RProp $props 'entityMappings' @()).Count
    $ti     = [bool]($q -match '(?i)ThreatIntel')
    $incOn  = [bool](_RProp (_RProp $props 'incidentConfiguration') 'createIncident' $true)
    $score  = [math]::Min(10, [math]::Round($q.Length / 400.0) + $lets + 2 * $joins + $unions + $(if ($ti) { 1 } else { 0 }) + $(if ($ents -eq 0) { 1 } else { 0 }))
    [pscustomobject]@{
        Rule       = [string](_RProp $props 'displayName' $r.name)
        Kind       = $r.kind
        Complexity = [int]$score
        Chars      = $q.Length
        Lets       = $lets
        Joins      = $joins
        Unions     = $unions
        Entities   = $ents
        TI         = if ($ti) { 'Yes' } else { '' }
        Incident   = if ($incOn) { 'Yes' } else { 'No' }
    }
}) | Sort-Object -Property @{ Expression = 'Complexity'; Descending = $true }, @{ Expression = 'Chars'; Descending = $true })
$complexitySection = @"

## Rule complexity

A heuristic per Scheduled or NRT rule with a query: one point per 400 characters, one per ``let``, two per ``join``, one per ``union``, one when the query reads a threat-intelligence table and one when the rule maps no entities, capped at 10. A score of 8 or more marks a query to run by hand against its lookback before trusting it; it is the first place to look when a rule times out or starts returning nothing after a schema change.

$(Format-Table -Items $complexityRows -Columns 'Rule','Kind','Complexity','Chars','Lets','Joins','Unions','Entities','TI','Incident')
"@

# Rule run failures from SentinelHealth (rule-health.json). Absent file:
# the collector did not run this capture; empty file: no failures.
$ruleHealthCaptured = Test-Path -LiteralPath (Join-Path $rawRoot 'rule-health.json')
$ruleHealthRows = @(Read-RawArray 'rule-health.json' | Where-Object { $_ } | ForEach-Object {
    [pscustomobject]@{ Rule = $_.RuleName; Status = $_.Status; Failures = $_.Failures; 'Last failure' = Format-DateUtc (_RProp $_ 'LastFailure'); Reason = [string](_RProp $_ 'Reason' '') }
} | Sort-Object { _RendererNumber $_.Failures } -Descending)
$ruleHealthSection = @"

## Rule run failures (last {lookback-d})

Analytics rules whose scheduled runs failed, from ``SentinelHealth``, with the failure count, the last failure and the reason Sentinel recorded. A failing rule is a detection that stopped without an alert; the usual causes are a query past the timeout, a table or column that no longer exists, or a KQL function the rule depends on that was removed. [SAC-DET-14] fires while any rule is failing.

$(if (-not $ruleHealthCaptured) { '_Not captured in this run (``rule-health.json`` is absent); re-run the collector to populate it._' } elseif ($ruleHealthRows.Count -eq 0) { '_No analytics rule run failed in the last {lookback}._' } else { Format-Table -Items $ruleHealthRows -Columns 'Rule','Status','Failures','Last failure','Reason' })
"@

# Defender XDR custom detections from the Graph capture: the other detection
# logic that reads this data, listed with the tables each one queries.
$customDetectionRows = @($customDetectionRefs | Where-Object { $_ } | ForEach-Object {
    [pscustomobject]@{
        Name         = [string](_RProp $_ 'RuleName' '')
        Enabled      = $(if ((_RProp $_ 'Enabled' $false) -eq $true) { 'Yes' } else { 'No' })
        Severity     = [string](_RProp $_ 'Severity' '')
        Period       = [string](_RProp $_ 'Period' '')
        Tables       = (@(_RProp $_ 'Tables' @()) -join ', ')
        LastModified = Format-DateUtc (_RProp $_ 'LastModified')
    }
} | Sort-Object -Property @{ Expression = { $_.Enabled -eq 'No' } }, Name)
$customDetectionSection = @"

## Defender XDR custom detections

Custom detection rules defined in the Defender portal (Microsoft Graph ``security/rules/detectionRules``). They run inside Defender XDR over the same advanced-hunting data the workspace receives, so they count as detection coverage on the tables they query, on this page, on the table-coverage view and in the estate flow. Period ``0`` is near-real-time.

$(if (-not $customDetectionsCaptured) { '_Not captured in this run: the Graph call was not made or was refused. The identity needs the ``CustomDetection.Read.All`` application permission (delegated access through Azure PowerShell does not carry it); until then coverage counts Sentinel rules only._' } elseif ($customDetectionRows.Count -eq 0) { '_No custom detection rules are defined in Defender XDR for this tenant._' } else { Format-Table -Items $customDetectionRows -Columns 'Name','Enabled','Severity','Period','Tables','LastModified' })
"@

# One page for the rule estate: the core view built in the section-20 block
# above, then the alert-volume, Microsoft-managed, modifications and
# solution subsections (formerly 21 to 24).
$analyticsLinks = @"

[Built-in detections (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/detect-threats-built-in) · [Detect threats from template](https://learn.microsoft.com/azure/sentinel/detect-threats-from-template) · [Alert and incident tuning](https://learn.microsoft.com/azure/sentinel/false-positives)
"@
# Each part begins with a newline and ends without one; joining with a
# newline keeps a blank line between a table and the next heading.
Write-Section '20-analytics-rules.md' (@($rulesBody.TrimEnd(), $msRulesSection, $modificationsSection, $solutionSection, $customDetectionSection, $analyticsLinks) -join [Environment]::NewLine)

# Section 21: how the rules perform, alert volume and closure verdicts.
Write-Section '21-rule-performance.md' (@(
    "$(Format-Banner -Title "Rule Performance")`n`nHow much each detection fires and how its incidents are closed. The rule inventory is in [20-analytics-rules.md](20-analytics-rules.md); alerts by severity, product and provider are in [16-alerts.md](16-alerts.md).",
    $volumeSection,
    $analyticsLinks) -join [Environment]::NewLine)

# Section 22: rule health and quality. Rules that fail to run, rules hard to
# trust, and the anti-patterns the health check lists: no entity mappings,
# alerts that never become incidents, rules nobody has touched in a year.
$scheduledEnabled22 = @($rules | Where-Object { $_ -and $_.kind -in @('Scheduled', 'NRT') -and (_RProp (_RProp $_ 'properties') 'enabled' $false) })
$noEntityRows = @($scheduledEnabled22 | Where-Object { @(_RProp (_RProp $_ 'properties') 'entityMappings' @() | Where-Object { $_ }).Count -eq 0 } | ForEach-Object {
    [pscustomobject]@{ Rule = [string](_RProp $_.properties 'displayName' $_.name); Kind = $_.kind; Severity = [string](_RProp $_.properties 'severity' '') }
} | Sort-Object Rule)
$alertOnlyRows = @($scheduledEnabled22 | Where-Object {
    $ic = _RProp (_RProp $_ 'properties') 'incidentConfiguration'
    $ic -and $ic.PSObject.Properties['createIncident'] -and -not [bool]$ic.createIncident
} | ForEach-Object {
    [pscustomobject]@{ Rule = [string](_RProp $_.properties 'displayName' $_.name); Kind = $_.kind; Severity = [string](_RProp $_.properties 'severity' '') }
} | Sort-Object Rule)
$antiPatternSection = @"

## Rules without entity mappings

Enabled Scheduled and NRT rules that map no entities. Their incidents carry no account, host or IP to pivot on, so they cannot join the investigation graph, entity pages or UEBA, and automation that acts on entities has nothing to act on ([SAC-DET-03]).

$(Format-Table -Items $noEntityRows -Columns 'Rule','Kind','Severity' -EmptyMessage $(if ($scheduledEnabled22.Count) { '_Every enabled Scheduled and NRT rule maps at least one entity._' } else { '_No enabled Scheduled or NRT rules._' }))

## Rules that raise alerts without incidents

Enabled Scheduled and NRT rules with incident creation turned off. Their alerts land in ``SecurityAlert`` but never reach the incident queue, so nobody triages them unless something else picks them up ([SAC-MON-01]).

$(Format-Table -Items $alertOnlyRows -Columns 'Rule','Kind','Severity' -EmptyMessage '_Every enabled Scheduled and NRT rule creates incidents._')
"@
Write-Section '22-rule-health-quality.md' (@(
    "$(Format-Banner -Title "Rule Health and Quality")`n`nWhether the analytics rules run, and whether they are built to be trusted and triaged. The rule inventory is in [20-analytics-rules.md](20-analytics-rules.md); how often each rule fires is in [21-rule-performance.md](21-rule-performance.md).",
    $ruleHealthSection,
    $antiPatternSection,
    $staleSection,
    $complexitySection,
    $analyticsLinks) -join [Environment]::NewLine)

# Section 26 — UEBA (TOC 4.16)
# Two signals are surfaced:
# 1. Configuration: presence of the /settings/Ueba resource. Absence does NOT
#    imply UEBA is disabled — the portal toggle writes nothing here.
# 2. Data presence: row counts in BehaviorAnalytics, IdentityInfo,
#    UserPeerAnalytics over 12d, from `_raw/ueba-data-presence.json`. Any
#    non-zero count is the authoritative "UEBA is producing data" signal.
$settingsRaw = Read-Raw 'settings.json'
$uebaSetting = if ($null -ne $settingsRaw) { $settingsRaw.Ueba } else { $null }
$uebaSources = if ($uebaSetting -and $uebaSetting.properties) { @($uebaSetting.properties.dataSources) } else { @() }
$uebaConfigLabel = if ($uebaSetting) {
    'Yes (settings resource present)'
} else {
    'Settings resource not written. UEBA may still be enabled through the portal toggle, and the configuration API has not been used to set explicit data sources on this workspace'
}
$uebaPresence = Read-RawArray 'ueba-data-presence.json'
$uebaPresenceRows = $uebaPresence | ForEach-Object {
    [pscustomobject]@{ Table = $_.TableName; Rows7d = _RProp $_ 'Count7d' ''; Rows12d = $_.Count; Rows14d = _RProp $_ 'Count14d' '' }
}
# Entity analytics: the identity providers synchronised into IdentityInfo
# (Microsoft Entra ID, Active Directory), from the settings resource, and the
# IdentityInfo rows that show the sync is running.
$entitySetting = if ($null -ne $settingsRaw) { _RProp $settingsRaw 'EntityAnalytics' } else { $null }
$entityProviders = @(_RProp (_RProp $entitySetting 'properties') 'entityProviders' @())
$identityRow = @($uebaPresence | Where-Object { $_ -and [string]$_.TableName -eq 'IdentityInfo' }) | Select-Object -First 1
$identityRows14 = if ($identityRow) { _RendererNumber (_RProp $identityRow 'Count14d' (_RProp $identityRow 'Count' 0)) } else { 0 }
$entityEnabled = $entityProviders.Count -gt 0 -or $identityRows14 -gt 0
$entityBlock = @"
| | |
|---|---|
| Entity providers (configured) | $(if ($entityProviders.Count -gt 0) { $entityProviders -join ', ' } else { '_(none configured via the settings resource)_' }) |
| IdentityInfo rows ({lookback-d}) | $identityRows14 |
| Entity analytics | $(if ($entityEnabled) { 'Enabled' } elseif ($uebaPresence.Count -eq 0) { 'Unknown (data-presence capture not available)' } else { 'Not enabled ([SAC-COV-08])' }) |
"@
$uebaTotalRows = ($uebaPresenceRows | Measure-Object -Property Rows12d -Sum).Sum
$uebaActiveLabel = if ($uebaTotalRows -and $uebaTotalRows -gt 0) {
    "Yes, $uebaTotalRows rows across $(@($uebaPresenceRows | Where-Object { $_.Rows12d -gt 0 }).Count) UEBA table(s) over the last {lookback}"
} elseif ($uebaPresence.Count -eq 0) {
    '_(data-presence capture not available, re-run the exporter to refresh)_'
} else {
    'No, none of BehaviorAnalytics, IdentityInfo, UserPeerAnalytics received rows in the last {lookback}'
}
# Pie of rows per UEBA table when there's something to chart.
$uebaPiePresenceBlock = if ($uebaPresenceRows.Count -gt 0 -and $uebaTotalRows -gt 0) {
    $uebaPieRows = $uebaPresenceRows | Where-Object { $_.Rows12d -gt 0 } | ForEach-Object {
        "    `"$($_.Table)`" : $([long]$_.Rows12d)"
    }
    @"

## UEBA table activity (last {lookback-d})

``````mermaid
pie showData title UEBA rows by table (last {lookback})
$($uebaPieRows -join [Environment]::NewLine)
``````

A workspace producing data in BehaviorAnalytics + IdentityInfo + UserPeerAnalytics has the full UEBA pipeline active. A single-table dominance suggests one anchor source feeding the rest.
"@
} else { '' }

$uebaPresenceBlock = if ($uebaPresenceRows.Count -gt 0) {
    @"

## Data-presence inference (last {lookback})

Rows per UEBA table over the last {recent} and the last {lookback}. The {recent-d} column is blank in snapshots taken before it was added.

$(Format-Table -Items $uebaPresenceRows -Columns 'Table','Rows7d','Rows12d')
"@
} else { '' }
Write-Section '26-ueba.md' (@"
$(Format-Banner -Title "User and Entity Behaviour Analytics  (TOC 4.16)")

UEBA enriches incidents with anomaly scores and entity-level timelines. It is enabled at the workspace level via the ``Microsoft.SecurityInsights/settings/Ueba`` resource. The configuration row reflects whether the settings resource has been written; the data-presence row reflects whether UEBA is actually producing rows.

| | |
|---|---|
| Configuration | $uebaConfigLabel |
| Data sources (configured) | $(if ($uebaSources.Count -gt 0) { ($uebaSources -join ', ') } else { '_(none configured via the settings resource)_' }) |
| Producing data | $uebaActiveLabel |
$uebaPiePresenceBlock$uebaPresenceBlock

## Entity analytics

Entity analytics synchronises user and group details from the identity providers into ``IdentityInfo``, which enriches every incident with who the account is and what it belongs to. It is configured separately from UEBA.

$entityBlock

[Enable UEBA in Microsoft Sentinel (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/enable-entity-behavior-analytics)
"@)

# Section 27 — Threat Intelligence (TOC 4.17)
# Indicators by observable type (IP, domain, URL, file hash, email).
$tiByTypeRows = @(Read-RawArray 'threat-intel-by-type.json' | Where-Object { $_ } | ForEach-Object {
    [pscustomobject]@{ Type = $_.Type; Count = $_.Count; Indicators = _RProp $_ 'Indicators' '' }
} | Sort-Object { _RendererNumber $_.Count } -Descending)
$tiByTypePie = if ($tiByTypeRows.Count -ge 2) { @"
``````mermaid
pie showData title Indicators by type (last {lookback-d})
$(($tiByTypeRows | ForEach-Object { "    `"$($_.Type)`" : $(_RendererNumber $_.Count)" }) -join [Environment]::NewLine)
``````
"@ } else { '' }
# Two capture sources are tried in turn:
# 1. `threat-intel-metrics.json` — the Sentinel TI metrics REST endpoint.
#    Independent of the workspace KQL path so it survives KQL-side failures
#    (missing Az.OperationalInsights module, permission gaps, table absence).
# 2. `threat-intel-counts.json` — the KQL summary against ThreatIntelligenceIndicator.
#    Used as a fallback when the metrics endpoint produced no data.
#
# Metrics-API response shape (one record per workspace):
#   properties.threatTypeMetrics[]   { metricName, metricValue }  — by threat type
#   properties.patternTypeMetrics[]  { metricName, metricValue }  — by STIX pattern type
#   properties.sourceMetrics[]       { metricName, metricValue }  — by ingestion source
# An earlier version of the renderer read `properties.metrics[]` with
# `threatType` / `threatTypeCount` fields — those field names appear nowhere
# in the real API surface and resulted in zero rows being rendered.
$tiMetrics = Read-RawArray 'threat-intel-metrics.json'
$tiCounts  = Read-RawArray 'threat-intel-counts.json'
$tiSourceRows = @()
$tiTypeRows   = @()
if ($tiMetrics.Count -gt 0) {
    foreach ($m in $tiMetrics) {
        if ($m.PSObject.Properties.Name -notcontains 'properties' -or -not $m.properties) { continue }
        if ($m.properties.PSObject.Properties.Name -contains 'sourceMetrics' -and $m.properties.sourceMetrics) {
            foreach ($s in $m.properties.sourceMetrics) {
                $tiSourceRows += [pscustomobject]@{
                    SourceSystem   = $s.metricName
                    IndicatorCount = $s.metricValue
                    LastIngested   = ''
                }
            }
        }
        if ($m.properties.PSObject.Properties.Name -contains 'threatTypeMetrics' -and $m.properties.threatTypeMetrics) {
            foreach ($t in $m.properties.threatTypeMetrics) {
                $tiTypeRows += [pscustomobject]@{
                    ThreatType     = $t.metricName
                    IndicatorCount = $t.metricValue
                }
            }
        }
    }
    # Sort both tables by count desc so the loudest entry surfaces first.
    $tiSourceRows = @($tiSourceRows) | Sort-Object -Property IndicatorCount -Descending
    $tiTypeRows   = @($tiTypeRows)   | Sort-Object -Property IndicatorCount -Descending
    $tiRows = $tiSourceRows
    $tiSourceLabel = 'TI metrics API (`threatIntelligence/main/metrics`)'
} else {
    $tiRows = $tiCounts | ForEach-Object {
        [pscustomobject]@{ SourceSystem = $_.SourceSystem; IndicatorCount = $_.Count; LastIngested = $_.Last }
    } | Sort-Object -Property IndicatorCount -Descending
    $tiSourceLabel = 'workspace KQL summary'
}
$tiTotal = ($tiRows | Measure-Object -Property IndicatorCount -Sum).Sum
$tiHeadline = if ($tiTotal -and $tiTotal -gt 0) {
    "**Total active indicators:** $tiTotal  ·  **Distinct breakdown rows:** $(@($tiRows).Count)  ·  **Data source:** $tiSourceLabel"
} else {
    "_No threat intelligence indicators surfaced via either capture path._"
}
# Threat-type breakdown only renders when the metrics API path actually
# returned a populated array — under the KQL fallback there is no
# equivalent breakdown so the section is suppressed entirely.
$tiTypeBlock = if ($tiTypeRows.Count -gt 0 -and ($tiTypeRows | Measure-Object -Property IndicatorCount -Sum).Sum -gt 0) {
    @"

## Indicator breakdown by threat type

$(Format-Table -Items $tiTypeRows -Columns 'ThreatType','IndicatorCount')
"@
} else { '' }
# Pie of TI sources: the six largest, the rest as one Other slice. The
# indicator table on this page lists every source.
$tiPieBlock = if ($tiRows -and ($tiRows | Measure-Object -Property IndicatorCount -Sum).Sum -gt 0) {
    $tiBySource = [ordered]@{}
    foreach ($row in @($tiRows)) { $k = [string]$row.SourceSystem; $tiBySource[$k] = $(if ($tiBySource.Contains($k)) { $tiBySource[$k] } else { 0 }) + [long]$row.IndicatorCount }
    $tiPieRows = Format-PieSlices -Counts $tiBySource -Limit 6
    @"

## Indicator distribution by source

``````mermaid
pie showData title TI indicators by source
$($tiPieRows -join [Environment]::NewLine)
``````
"@
} else { '' }

# STIX objects beyond indicators, and the feeds that bring indicators in.
$tiObjects = Read-RawArray 'threat-intel-objects.json'
$tiObjectsBlock = if ($tiObjects.Count -gt 0) {
@"

## Indicators by type (last {lookback-d})

Observable types across the indicators ingested in the last {lookback}, from the current ``ThreatIntelIndicators`` schema (``ObservableKey``) or, where only the retired table has data, ``ThreatIntelligenceIndicator``. A feed that is all IP addresses covers network detections and nothing else; URL, domain and file-hash coverage is what email and endpoint detections match on.

$tiByTypePie

$(Format-Table -Items $tiByTypeRows -Columns 'Type','Count','Indicators')

## STIX objects (last {lookback-d})

Objects in ``ThreatIntelObjects`` by STIX type. Indicators alone give matches; threat actors, attack patterns and relationships give those matches their context.

$(Format-Table -Items ($tiObjects | ForEach-Object { [pscustomobject]@{ StixType = $_.StixType; Count = $_.Count } }) -Columns 'StixType','Count')
"@
} else { '' }
$tiFeedKinds = @('MicrosoftThreatIntelligence', 'PremiumMicrosoftDefenderForThreatIntelligence', 'ThreatIntelligenceTaxii', 'ThreatIntelligence', 'ThreatIntelligenceUploadIndicatorsAPI')
$tiFeedRows = @($connectors | Where-Object { $_.kind -in $tiFeedKinds } | ForEach-Object { [pscustomobject]@{ Kind = $_.kind; Name = $_.name } })

# Which TI tables carry data: the current ThreatIntelIndicators and
# ThreatIntelObjects, and the retired ThreatIntelligenceIndicator. A table
# missing from the capture is not in the workspace at all.
$tiTableRaw = @(Read-RawArray 'threat-intel-tables.json' | Where-Object { $_ })
$tiTableRows = @(foreach ($name in 'ThreatIntelIndicators', 'ThreatIntelObjects', 'ThreatIntelligenceIndicator') {
    $row = $tiTableRaw | Where-Object { [string]$_.Table -eq $name } | Select-Object -First 1
    $n30 = if ($row) { [long](_RProp $row 'Records30d' 0) } else { 0 }
    [pscustomobject]@{
        Table      = $(if ($name -eq 'ThreatIntelligenceIndicator') { "$name (retired)" } else { $name })
        Records30d = $(if ($row) { $n30 } else { '' })
        Records7d  = $(if ($row) { [long](_RProp $row 'Records7d' 0) } else { '' })
        FirstSeen  = $(if ($row) { Format-DateUtc (_RProp $row 'FirstSeen') } else { '' })
        LastSeen   = $(if ($row) { Format-DateUtc (_RProp $row 'LastSeen') } else { '' })
        Status     = $(if (-not $row) { 'Not in workspace' } elseif ($n30 -gt 0) { 'Ingesting' } else { 'No data in {lookback}' })
    }
})
$tiCurrent = [long](@($tiTableRaw | Where-Object { [string]$_.Table -eq 'ThreatIntelIndicators' } | ForEach-Object { _RProp $_ 'Records30d' 0 }) | Measure-Object -Sum).Sum
$tiLegacy = [long](@($tiTableRaw | Where-Object { [string]$_.Table -eq 'ThreatIntelligenceIndicator' } | ForEach-Object { _RProp $_ 'Records30d' 0 }) | Measure-Object -Sum).Sum
$tiMigration = if (-not (Test-Path (Join-Path $rawRoot 'threat-intel-tables.json'))) { '_Not captured in this snapshot._' }
    elseif ($tiCurrent -gt 0 -and $tiLegacy -gt 0) { '**Both tables carry data.** `ThreatIntelIndicators` is current; confirm nothing still writes to or reads the retired table ([SAC-TI-01], [SAC-TI-02]).' }
    elseif ($tiCurrent -gt 0) { '**Current.** Threat intelligence is flowing into `ThreatIntelIndicators`.' }
    elseif ($tiLegacy -gt 0) { '**Retired table only.** Indicators land in `ThreatIntelligenceIndicator` but not `ThreatIntelIndicators`; check the TI connector configuration ([SAC-TI-01]).' }
    else { '**No threat intelligence** in either table over the last {lookback}.' }

$tiHealth = Read-RawArray 'threat-intel-health.json' | Select-Object -First 1
$tiHealthBlock = if ($tiHealth) {
    @"
| | |
|---|---:|
| Distinct indicators (latest state) | $([long](_RProp $tiHealth 'Total' 0)) |
| Active | $([long](_RProp $tiHealth 'Active' 0)) |
| Deleted | $([long](_RProp $tiHealth 'Deleted' 0)) |
| Revoked | $([long](_RProp $tiHealth 'Revoked' 0)) |
| Still within their validity | $([long](_RProp $tiHealth 'StillValid' 0)) |
"@
} else { Get-EmptyMessage 'threat-intel-health.json' '_No indicators in `ThreatIntelIndicators` over the last {lookback}._' }

$tiKqlSourceRows = @($tiCounts | Where-Object { $_ } | ForEach-Object {
    [pscustomobject]@{ SourceSystem = $_.SourceSystem; Records = $_.Count; Indicators = _RProp $_ 'Indicators' ''; LastSeen = Format-DateUtc $_.Last }
} | Sort-Object @{ Expression = { [long]$_.Records }; Descending = $true }, SourceSystem)

$taxiiRows = @(Read-RawArray 'taxii-clients.json' | Where-Object { $_ } | ForEach-Object {
    $tp = _RProp $_ 'properties'
    [pscustomobject]@{
        Name        = [string](_RProp $tp 'friendlyName' $_.name)
        Collection  = [string](_RProp $tp 'collectionId' '')
        Polling     = [string](_RProp $tp 'pollingFrequency' '')
        Server      = [string](_RProp $tp 'taxiiServer' '')
        Description = [string](_RProp $tp 'description' '')
    }
})

Write-Section '27-threat-intelligence.md' (@"
$(Format-Banner -Title "Threat Intelligence  (TOC 4.17)")

Indicator counts and most-recent ingestion timestamp by source, last {lookback}. Indicator detail is intentionally NOT exported to keep the report aggregate-only.

$tiHeadline
$tiPieBlock

$(Format-Table -Items $tiRows -Columns 'SourceSystem','IndicatorCount','LastIngested')

## Table migration status

$tiMigration

$(Format-Table -Items $tiTableRows -Columns 'Table','Records30d','Records7d','FirstSeen','LastSeen','Status')

## Indicator health (last {lookback-d})

Each indicator in ``ThreatIntelIndicators`` at its latest state. Deleted and revoked indicators no longer match; an indicator past its ``ValidUntil`` date is kept for history but should not drive new alerts.

$tiHealthBlock

## Indicators by source (last {lookback-d})

Records and distinct indicators per source system, from the indicator tables themselves (current and retired).

$(Format-Table -Items $tiKqlSourceRows -Columns 'SourceSystem','Records','Indicators','LastSeen')
$tiTypeBlock
$tiObjectsBlock

## Feeds

Where indicators come from. One feed is a single point of failure for every TI detection; [SAC-TI-05] fires when there is at most one.

### Threat intelligence connectors

$(Format-Table -Items $tiFeedRows -Columns 'Kind','Name')

### TAXII clients

TAXII 2.x collections the workspace polls, from the threat intelligence TAXII client list. Not every service returns this list; the connectors above remain the reliable feed signal.

$(Format-Table -Items $taxiiRows -Columns 'Name','Collection','Polling','Server','Description' -EmptyMessage (Get-EmptyMessage 'taxii-clients.json' '_No TAXII clients returned._'))

[Microsoft Sentinel Threat Intelligence (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/understand-threat-intelligence)
"@)

# Section 28 — Detection opportunities: tables with data that no enabled
# rule reads, and the undeployed templates that would cover them. The
# detection-headroom view from the health-check script contributed to the
# project, computed from the collector's table references.
$applicableTemplates = @($templateTableRefs | Where-Object { $_.Deprecated -ne $true -and -not (Test-TemplateRetired -Map $templateSolutionMap -TemplateId ([string]$_.TemplateId)) })
$undeployedTemplates = @($applicableTemplates | Where-Object { $_.AlreadyDeployed -ne $true })
$enabledTableSet = @{}
foreach ($ref in $ruleTableRefs) {
    if ($ref.Enabled -ne $true) { continue }
    foreach ($t in @($ref.Tables)) { if ($t) { $enabledTableSet[[string]$t] = $true } }
}
foreach ($t in $customDetectionTableSet.Keys) { $enabledTableSet[$t] = $true }
$dataTableSet = @{}
foreach ($t in $tablesWithData) { if ($t.DataType -and (_RendererNumber $t.BillableLast30d) -gt 0) { $dataTableSet[[string]$t.DataType] = $true } }
$sevRank = @{ High = 0; Medium = 1; Low = 2; Informational = 3 }
# Sentinel's own operational tables are outputs, not detection sources.
$operationalOnlyTables = @('SecurityIncident', 'SecurityAlert', 'Usage', 'Operation', 'LAQueryLogs', 'SentinelHealth', 'SentinelAudit', 'AzureMetrics')
$uncoveredTables = @($tablesWithData | Where-Object {
    $_.DataType -and (_RendererNumber $_.BillableLast30d) -gt 0 -and
    -not $enabledTableSet.ContainsKey([string]$_.DataType) -and
    ([string]$_.DataType) -notin $operationalOnlyTables
} | Sort-Object { _RendererNumber $_.BillableLast30d } -Descending)
# The Content Hub solution each template comes from, and whether it is
# installed, from the packages' own content lists (Get-TemplateSolution).
# Templates that read a table with data but only a deprecated solution ships:
# left out above, listed on their own with the solution replacing it.
$retiredReady = @($templateTableRefs | Where-Object {
    $_.Deprecated -ne $true -and $_.AlreadyDeployed -ne $true -and
    (Test-TemplateRetired -Map $templateSolutionMap -TemplateId ([string]$_.TemplateId)) -and
    @(@($_.Tables) | Where-Object { $dataTableSet.ContainsKey([string]$_) }).Count -gt 0
} | Sort-Object DisplayName | ForEach-Object {
    $sol = Get-TemplateSolution -Map $templateSolutionMap -TemplateId ([string]$_.TemplateId)
    [pscustomobject]@{
        Template              = $_.DisplayName
        'Deprecated solution' = $sol.Solution
        'Replaced by'         = $(if ($sol.ReplacedBy) { $sol.ReplacedBy } else { '' })
        Tables                = (@($_.Tables) -join ', ')
    }
})
$retiredBlock = if ($retiredReady.Count -gt 0) {
    $replaced = @($retiredReady | Where-Object { $_.'Replaced by' }).Count
    @"
## Templates from deprecated solutions

**$($retiredReady.Count)** template(s) read a table with data but are left out of the lists above: the only Content Hub solution that ships them is deprecated, so Microsoft no longer maintains them$(if ($replaced) { ", and $replaced name the solution that replaces it: install that and enable its templates instead" }). An installed deprecated solution is flagged by [SAC-DET-13].

$(Format-Table -Items $retiredReady -Columns 'Template','Deprecated solution','Replaced by','Tables')
"@
} else { '' }
$opportunityRows = @($uncoveredTables | ForEach-Object {
    $name = [string]$_.DataType
    $cands = @($undeployedTemplates | Where-Object { @($_.Tables) -contains $name } | Sort-Object { $sv = [string]$_.Severity; if ($sevRank.ContainsKey($sv)) { $sevRank[$sv] } else { 9 } }, DisplayName)
    [pscustomobject]@{
        Table                       = $name
        'GB ({lookback-d})'                  = [math]::Round((_RendererNumber $_.BillableLast30d), 2)
        Templates                   = $cands.Count
        'From solutions'            = (Format-TemplateSolutionSummary -Templates $cands -Map $templateSolutionMap)
        TemplateCount               = $cands.Count
        Gb30d                       = [math]::Round((_RendererNumber $_.BillableLast30d), 2)
    }
})
$installedSolutionNames = @(Read-RawArray 'content-packages.json' | Where-Object { $_ } | ForEach-Object { [string](_RProp (_RProp $_ 'properties') 'displayName' '') } | Where-Object { $_ })
$noTemplateRows = @($opportunityRows | Where-Object { $_.TemplateCount -eq 0 } | ForEach-Object {
    [pscustomobject]@{
        Table      = $_.Table
        'GB ({lookback-d})' = $_.Gb30d
        Solutions  = $(if ($connectorCatalogue) { Get-TableSolutionLabel -Catalogue $connectorCatalogue -Table ([string]$_.Table) -InstalledSolutions $installedSolutionNames } else { '' })
    }
})
$readyTemplates = @($undeployedTemplates | Where-Object {
    $tbls = @($_.Tables)
    @($tbls | Where-Object { $dataTableSet.ContainsKey([string]$_) }).Count -gt 0
} | Sort-Object { $sv = [string]$_.Severity; if ($sevRank.ContainsKey($sv)) { $sevRank[$sv] } else { 9 } }, DisplayName | ForEach-Object {
    $sol = Get-TemplateSolution -Map $templateSolutionMap -TemplateId ([string]$_.TemplateId)
    [pscustomobject]@{
        Template             = $_.DisplayName
        Solution             = $sol.Solution
        'Solution installed' = $(if ($sol.Installed -eq $true) { 'Yes' } elseif ($sol.Installed -eq $false) { 'No' } else { '' })
        Severity             = $_.Severity
        Kind                 = $_.Kind
        Tactics              = (@($_.Tactics) -join ', ')
        Tables               = (@($_.Tables) -join ', ')
    }
})
$readyInstalled = @($readyTemplates | Where-Object { $_.'Solution installed' -eq 'Yes' }).Count
$readyNotInstalled = @($readyTemplates | Where-Object { $_.'Solution installed' -eq 'No' }).Count
$readyBuiltIn = @($readyTemplates | Where-Object { $_.'Solution installed' -eq '' }).Count
# The headroom as proportions for the SharePoint graphic: how much of the
# template catalogue is deployed, and of what is ready to enable, how much
# comes from a solution already installed.
$headroomVisualLine = Format-VisualLine -Kind 'meters' -Data ([ordered]@{ meters = @(
    [ordered]@{ title = 'Applicable templates'; caption = 'Rule templates in the catalogue, deprecated ones left out'; total = $applicableTemplates.Count; parts = @(
        [ordered]@{ label = 'Deployed'; value = ($applicableTemplates.Count - $undeployedTemplates.Count); tone = 'ok' }
        [ordered]@{ label = 'Not yet deployed'; value = $undeployedTemplates.Count; tone = 'violet' }
    ) }
    [ordered]@{ title = 'Ready to enable'; caption = 'Not yet deployed, and their tables have data'; total = $readyTemplates.Count; parts = @(
        [ordered]@{ label = 'Solution installed'; value = $readyInstalled; tone = 'ok' }
        [ordered]@{ label = 'Solution not installed'; value = $readyNotInstalled; tone = 'warn' }
        [ordered]@{ label = 'Built-in'; value = $readyBuiltIn; tone = 'info' }
    ) }
); figures = @(
    [ordered]@{ label = 'Enabled analytics rules'; value = $enabledRules.Count; caption = 'Of every kind, on this workspace' }
    [ordered]@{ label = 'Tables with data and no detection'; value = $opportunityRows.Count; caption = 'Read by no enabled rule or custom detection, last {lookback}' }
) })
$headroomChart = if ($applicableTemplates.Count -gt 0 -or $enabledRules.Count -gt 0) {
@"

``````mermaid
---
config:
  xyChart:
    width: 900
    height: 380
---
xychart-beta
$headroomVisualLine
    title "Detection headroom"
    x-axis ["Applicable templates", "Enabled rules", "Not yet deployed"]
    y-axis "Count" 0 --> $([math]::Max($applicableTemplates.Count, $enabledRules.Count) + 2)
    bar [$($applicableTemplates.Count), $($enabledRules.Count), $($undeployedTemplates.Count)]
``````
"@
} else { '' }
$opportunityBody = if ($ruleTableRefs.Count -eq 0 -and $templateTableRefs.Count -eq 0) {
@"
$(Format-Banner -Title "Detection Opportunities")

_Table-to-rule mapping was not computed in this run (``rule-table-references.json`` and ``template-table-references.json`` are absent), so there is nothing to compare. The collector writes both; they are missing from an inventory taken by an older collector or when that capture failed._
"@
} else {
@"
$(Format-Banner -Title "Detection Opportunities")

Which ingested tables no enabled analytics rule reads, and which rule templates would cover them. The template list is the workspace's own alert-rule template catalogue, so a suggestion here can be enabled from Content Hub without a new data source. Deprecated templates and templates already deployed are never suggested.
$headroomChart

<!-- bp:shown-in-graphic -->

**$($applicableTemplates.Count)** applicable template(s)  ·  **$($enabledRules.Count)** enabled rule(s)  ·  **$($undeployedTemplates.Count)** template(s) not yet deployed  ·  **$($opportunityRows.Count)** table(s) with data and no detection

## Tables with data but no detection (last {lookback-d})

"Detection" here means an enabled Sentinel analytics rule, or an enabled Defender XDR custom detection, whose query reads the table. Alerts raised inside Defender XDR, Entra ID Protection, Defender for Identity or Defender for Cloud do not read workspace tables, so a table can be covered by a first-party product and still appear below; see the alerts by detection source in [16-alerts.md](16-alerts.md) before treating a row as unprotected.

``Templates`` counts the undeployed templates that read the table, and ``From solutions`` the Content Hub solutions they come from, marking those installed; Built-in templates ship with Sentinel rather than in a solution. Every template is listed, with its solution, under **Undeployed templates ready to enable** below: filter that list by a table's name to see its templates.

$(Format-Table -Items $opportunityRows -Columns 'Table','GB ({lookback-d})','Templates','From solutions')

## Tables with no template available

Tables above with no undeployed, non-deprecated template that reads them. Covering one of these means writing a custom rule, or a Defender XDR custom detection, rather than enabling a template. ``Solutions`` names the Content Hub solutions that ship the table, from the connector catalogue, marking the ones installed: installing one usually brings rule templates for it. A blank means no Content Hub solution ships the table, as for most custom tables.

$(Format-Table -Items $noTemplateRows -Columns 'Table','GB ({lookback-d})','Solutions' -EmptyMessage '_Every table above has at least one template available._')

[SAC-MON-05] lists the same tables above 5 GB per 30 days. A table kept for investigation only belongs on a cheaper tier; see [81-table-plans-retention.md](81-table-plans-retention.md).

## Undeployed templates ready to enable

Templates that are not deployed, not deprecated (nor shipped only by a deprecated solution), and read at least one table that has data, highest severity first, with the Content Hub solution each comes from. **$readyInstalled** come from solutions already installed and can be enabled as they are; **$readyNotInstalled** are in solutions not installed, which Sentinel still offers as gallery templates (installing the solution keeps them current); **$readyBuiltIn** are built-in templates no solution ships.

$(Format-Table -Items $readyTemplates -Columns 'Template','Solution','Solution installed','Severity','Kind','Tactics','Tables')

$retiredBlock

[SOC optimization (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/soc-optimization/soc-optimization-access) · [Detect threats from template](https://learn.microsoft.com/azure/sentinel/detect-threats-from-template)
"@
}
Write-Section '28-detection-opportunities.md' $opportunityBody

# Section 36 — Data export (TOC 4.3.3)
$dataExports = Read-RawArray 'data-exports.json'
$linkedServices = Read-RawArray 'linked-services.json'
$linkedRows = @($linkedServices | ForEach-Object {
    $lp = if ($_.PSObject.Properties['properties'] -and $_.properties) { $_.properties } else { $null }
    [pscustomobject]@{
        Name                  = $_.name
        ResourceId            = if ($lp -and $lp.PSObject.Properties['resourceId']) { $lp.resourceId } else { '' }
        WriteAccessResourceId = if ($lp -and $lp.PSObject.Properties['writeAccessResourceId']) { $lp.writeAccessResourceId } else { '' }
    }
})
$exportRows = $dataExports | ForEach-Object {
    $dest = [string]$_.properties.destination.resourceId
    [pscustomobject]@{
        Name            = $_.name
        DestinationType = if ($dest -match '/storageAccounts/') { 'Storage account (Blob)' } elseif ($dest -match '/namespaces/') { 'Event Hub' } else { [string](_RProp $_.properties.destination 'type' '') }
        Destination     = $dest
        Tables          = ($_.properties.tableNames -join ', ')
        Enabled         = $_.properties.enable
    }
}
$linkedStorageRows = @(Read-RawArray 'linked-storage-accounts.json' | Where-Object { $_ } | ForEach-Object {
    $lp = _RProp $_ 'properties'
    [pscustomobject]@{
        DataSource      = [string](_RProp $lp 'dataSourceType' $_.name)
        StorageAccounts = (@(_RProp $lp 'storageAccountIds' @()) | ForEach-Object { ([string]$_ -split '/')[-1] }) -join ', '
    }
})
$adxRows = @($linkedRows | Where-Object { $_.ResourceId -match '/providers/Microsoft\.Kusto/' } | ForEach-Object {
    [pscustomobject]@{ Name = $_.Name; Cluster = ($_.ResourceId -split '/')[-1]; ResourceId = $_.ResourceId }
})
Write-Section '36-data-export.md' (@"
$(Format-Banner -Title "Data Export  (TOC 4.3.3)")

## Continuous data exports

Continuous export of selected tables to Storage Accounts or Event Hubs. Empty list = no data export configured.

$(Format-Table -Items $exportRows -Columns 'Name','DestinationType','Destination','Tables','Enabled')

## Linked storage accounts

Customer-owned storage the workspace writes to, by data source type: custom and IIS logs, saved query results, alerts and ingestion. Empty when the workspace uses Microsoft-managed storage only.

$(Format-Table -Items $linkedStorageRows -Columns 'DataSource','StorageAccounts' -EmptyMessage (Get-EmptyMessage 'linked-storage-accounts.json'))

## ADX clusters linked to the workspace

Azure Data Explorer clusters linked through a workspace linked service, typically to keep data for longer outside the workspace.

$(Format-Table -Items $adxRows -Columns 'Name','Cluster','ResourceId')

## Linked services

Workspace linked services: the automation account, the cluster, or the storage accounts used for customer-managed keys and private alert and query storage.

$(Format-Table -Items $linkedRows -Columns 'Name','ResourceId','WriteAccessResourceId')

[Log Analytics data export (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/logs/logs-data-export) · [Linked storage accounts](https://learn.microsoft.com/azure/azure-monitor/logs/private-storage)
"@)

# Section 37 — Search and restore (TOC 4.3.4)
# A search job leaves a _SRCH table and a restore a _RST table in the
# workspace's table list. The collector saves them as search-jobs.json and
# restore-logs.json; a snapshot collected before it did reads them from
# workspace-tables.json instead.
$searchJobs = Read-RawArray 'search-jobs.json'
$restoreJobs = Read-RawArray 'restore-logs.json'
if (-not (Test-Path (Join-Path $rawRoot 'search-jobs.json')) -and -not (Test-Path (Join-Path $rawRoot 'restore-logs.json'))) {
    $found = Get-SearchRestoreTable -Tables @(Read-RawArray 'workspace-tables.json')
    $searchJobs = @($found.SearchJobs)
    $restoreJobs = @($found.Restores)
}
$srProp = {
    param($Object, [string]$Name)
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) { $Object.$Name } else { $null }
}
$srWindow = {
    param($From, $To)
    $f = Format-DateUtc $From; $t = Format-DateUtc $To
    if ($f -or $t) { "$f to $t" } else { '' }
}
$searchRows = @($searchJobs | ForEach-Object {
        $p = $_.properties; $s = & $srProp $p 'searchResults'
        [pscustomobject]@{
            'Table'          = [string]$_.name
            'Source table'   = [string](& $srProp $s 'sourceTable')
            'Search window'  = & $srWindow (& $srProp $s 'startSearchTime') (& $srProp $s 'endSearchTime')
            'Created (UTC)'  = Format-DateUtc (& $srProp $p 'createDate')
            'Retention'      = $(if ($null -ne (& $srProp $p 'totalRetentionInDays')) { "$(& $srProp $p 'totalRetentionInDays') days" } else { '' })
            'Query'          = $(if (& $srProp $s 'query') { '`' + ([string](& $srProp $s 'query')).Trim() + '`' } else { '' })
        }
    })
$restoreRows = @($restoreJobs | ForEach-Object {
        $p = $_.properties; $r = & $srProp $p 'restoredLogs'
        [pscustomobject]@{
            'Table'           = [string]$_.name
            'Source table'    = [string](& $srProp $r 'sourceTable')
            'Restored window' = & $srWindow (& $srProp $r 'startRestoreTime') (& $srProp $r 'endRestoreTime')
            'Created (UTC)'   = Format-DateUtc (& $srProp $p 'createDate')
        }
    })
Write-Section '37-search-restore.md' (@"
$(Format-Banner -Title "Search and Restore Tables  (TOC 4.3.4)")

Search jobs and restores bring data back from long-term retention into tables you can query: a search job writes its matches to a table ending in ``_SRCH``, a restore a time range of a table to one ending in ``_RST``. Each table stays until someone deletes it, so this is every search and restore whose table is still in the workspace: **$(@($searchRows).Count)** search job$(if (@($searchRows).Count -ne 1) { 's' }) and **$(@($restoreRows).Count)** restore$(if (@($restoreRows).Count -ne 1) { 's' }).

## Search jobs

$(Format-Table -Items $searchRows -Columns 'Table','Source table','Search window','Created (UTC)','Retention','Query' -EmptyMessage '_No search job tables in the workspace._')

## Restores

$(Format-Table -Items $restoreRows -Columns 'Table','Source table','Restored window','Created (UTC)' -EmptyMessage '_No restored tables in the workspace._')

[Search jobs in Azure Monitor Logs](https://learn.microsoft.com/azure/azure-monitor/logs/search-jobs) · [Restore logs](https://learn.microsoft.com/azure/azure-monitor/logs/restore)
"@)

# Section 38 — Summary rules (TOC 4.3.5)
# Schema note: the capture comes from `.../workspaces/<ws>/summaryLogs` (under
# the OperationalInsights provider, not Sentinel). Each item exposes
# `properties.ruleType`, `properties.ruleDefinition.query`,
# `properties.ruleDefinition.binSize`, `properties.ruleDefinition.timeSelector`,
# `properties.ruleDefinition.destinationTable`, `properties.isActive`,
# `properties.statusCode`. The previous renderer included a `BinDelay` column
# that doesn't exist in the API response (always-empty). `isActive` and
# `statusCode` ARE present and signal whether the rule is actually running —
# the first rule on stl-sec-siem-law has isActive=false + status=DataPlaneError,
# evidence of a broken rule that the old shape never surfaced. Field names
# round-trip through ConvertFrom-Json as camelCase; PowerShell's PSObject
# property access is case-insensitive so the old PascalCase access "worked"
# accidentally for the fields that happened to exist.
$summaryRules = Read-RawArray 'summary-rules.json'
$summaryRows = $summaryRules | ForEach-Object {
    $props = $_.properties
    $isActive = if ($props.PSObject.Properties.Name -contains 'isActive') { $props.isActive } else { $null }
    $status   = if ($props.PSObject.Properties.Name -contains 'statusCode') { [string]$props.statusCode } else { '' }
    [pscustomobject]@{
        Name             = $_.name
        RuleType         = $props.ruleType
        DestinationTable = $props.ruleDefinition.destinationTable
        BinSize          = $props.ruleDefinition.binSize
        TimeSelector     = $props.ruleDefinition.timeSelector
        Active           = if ($null -eq $isActive) { '?' } elseif ($isActive) { 'Yes' } else { 'No' }
        Status           = if ($status) { $status } else { 'Ok' }
    }
}
$brokenSummary = @($summaryRows | Where-Object { $_.Active -eq 'No' -or $_.Status -ne 'Ok' })
$summaryWarning = if ($brokenSummary.Count -gt 0) {
    "`n<!-- bp:tone critical -->`n`n> **$($brokenSummary.Count) summary rule(s) are inactive or in error.** Inspect the `Status` column: `DataPlaneError` typically means the underlying source table is missing or the query failed at last execution.`n"
} else { '' }
# Active vs Errored pie (only when there's something to chart).
$summaryActiveCount = @($summaryRows | Where-Object { $_.Active -eq 'Yes' -and $_.Status -eq 'Ok' }).Count
$summaryBrokenCount = @($summaryRows | Where-Object { $_.Active -ne 'Yes' -or $_.Status -ne 'Ok' }).Count
$summaryChartBlock = if ($summaryRows.Count -gt 0) {
    @"

## Health

``````mermaid
pie showData title Summary rule health
    "Active & Ok" : $summaryActiveCount
    "Inactive or errored" : $summaryBrokenCount
``````
"@
} else { '' }

Write-Section '38-summary-rules.md' (@"
$(Format-Banner -Title "Summary Rules  (TOC 4.3.5)")

Summary rules pre-aggregate high-volume tables on a schedule into a derived table. They cut query cost on noisy data.
$summaryWarning$summaryChartBlock

$(Format-Table -Items $summaryRows -Columns 'Name','RuleType','DestinationTable','BinSize','TimeSelector','Active','Status')

[Summary rules (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/summary-rules)
"@)

# Section 87 — Azure Monitor Agents (TOC 4.5)
$amaAgents = Read-RawArray 'ama-agents.json'
$agentRows = $amaAgents | ForEach-Object {
    [pscustomobject]@{
        Computer  = $_.Computer
        OS        = $_.OS
        Version   = $_.Version
        Resource  = $_.Resource
        LastSeen  = Format-DateUtc $_.LastHeartbeat
    }
}

# AMA vs MMA migration status by machine type.
$migration = Read-RawArray 'ama-mma-migration.json'
$migrationRows = $migration | ForEach-Object {
    [pscustomobject]@{
        MachineType     = $_.MachineType
        MachineCount    = $_.MachineCount
        MMACount        = $_.MMACount
        AMACount        = $_.AMACount
        MigrationStatus = $_.MigrationStatus
    }
}
# Chart inputs. When the total agent count is < 3 the renderer skips the
# chart entirely — 1-vs-0 splits are visually meaningless. Otherwise emit
# a grouped bar with AMA and MMA per machine type.
$totalAgents = 0
foreach ($r in $migrationRows) { $totalAgents += [int]$r.MachineCount }
$agentChartBlock = if ($totalAgents -ge 3 -and $migrationRows.Count -gt 0) {
    $mtAxis = ($migrationRows | ForEach-Object { "`"$($_.MachineType)`"" }) -join ', '
    $amaArr = ($migrationRows | ForEach-Object { [int]$_.AMACount }) -join ', '
    $mmaArr = ($migrationRows | ForEach-Object { [int]$_.MMACount }) -join ', '
    $yMax = 1
    foreach ($r in $migrationRows) {
        $t = [int]$r.AMACount + [int]$r.MMACount
        if ($t -gt $yMax) { $yMax = $t }
    }
    @"

``````mermaid
xychart-beta
    title "Agent fleet: AMA vs MMA per machine type"
    x-axis [$mtAxis]
    y-axis "Machines" 0 --> $($yMax + 1)
    bar "AMA" [$amaArr]
    bar "MMA" [$mmaArr]
``````

Two bars per machine type: AMA first, MMA second. A workspace mid-migration shows MMA bars sitting alongside AMA; a fully-migrated workspace has zero MMA bars across the board.
"@
} else {
    "`n> **Agent migration:** $totalAgents agent(s) heartbeating; chart suppressed because the count is too small for a meaningful visual. The migration-status table below carries the per-machine detail."
}

$heartbeatMixRows = @(Read-RawArray 'agent-heartbeat-mix.json' | Where-Object { $_ } | ForEach-Object {
    [pscustomobject]@{
        OSType    = $_.OSType
        Agent     = $(switch ([string]$_.Category) { 'Direct Agent' { 'Direct Agent (MMA, legacy)' } 'SCOM Agent' { 'SCOM Agent (legacy)' } default { $_ } })
        Version   = $_.Version
        OSVersion = $_.OSVersion
        Computers = $_.Computers
        LastSeen  = Format-DateUtc $_.LastSeen
    }
})

Write-Section '87-azure-monitor-agents.md' (@"
$(Format-Banner -Title "Azure Monitor Agents  (TOC 4.5)")

Agents heartbeating into the workspace over the last {lookback}, derived from the ``Heartbeat`` table. Each row is a distinct ``SourceComputerId``.
$agentChartBlock

$(Format-Table -Items $agentRows -Columns 'Computer','OS','Version','Resource','LastSeen')

## AMA vs MMA migration status

Per-machine-type breakdown of agent migration progress. ``Direct Agent`` counts the legacy MMA; ``Azure Monitor Agent`` counts the modern AMA. Migration state is **Completed** when only AMA records exist for a category, **In Progress** when both exist, and **Not Started** otherwise.

$(Format-Table -Items $migrationRows -Columns 'MachineType','MachineCount','MMACount','AMACount','MigrationStatus')

## Agent heartbeat mix

Machines by operating system, agent and agent version over the last {lookback}. A ``Direct Agent`` or ``SCOM Agent`` row is the legacy Log Analytics agent, retired on 31 August 2024 ([SAC-PLT-03]); the version column shows how far behind each fleet is.

$(Format-Table -Items $heartbeatMixRows -Columns 'OSType','Agent','Version','OSVersion','Computers','LastSeen' -EmptyMessage (Get-EmptyMessage 'agent-heartbeat-mix.json' '_No heartbeats in the last {lookback}._'))

[Migrate from Log Analytics agent to Azure Monitor agent (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-migration)
[Azure Monitor Agent overview (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/agents/agents-overview)
"@)

# ---------------------------------------------------------------------------
# Section 88 — Microsoft Sentinel Data Lake
# ---------------------------------------------------------------------------
# Lake-tier tables surfaced from $workspaceTables (those on plan='DataLake').
# Migration candidates surfaced from $cost.AllTablesByCost — high-volume
# tables on the Analytics plan are typical Lake-migration targets for
# cost optimisation. The enrollment signals were computed in section 83's
# block ($hasDataLake / $unifiedBilling / $sentinelDataLake / $plansInUse)
# so this block consumes them rather than recomputing.

$dlTables = @($workspaceTables | Where-Object { $_.properties.plan -eq 'DataLake' })
$dlTableRows = $dlTables | ForEach-Object {
    [pscustomobject]@{
        Table            = $_.name
        RetentionDays    = $_.properties.retentionInDays
        TotalRetention   = $_.properties.totalRetentionInDays
    }
}

# Tier-distribution stats. When Lake is enrolled every Analytics-plan
# table is auto-mirrored to the Lake at the same retention. A table
# that has totalRetentionInDays > retentionInDays is also storing
# additional time in the Lake beyond the Analytics period. Tables on
# plan = 'DataLake' route exclusively to the Lake (no Analytics tier).
# Catalogue-only tables (zero ingest in the workspace) are excluded
# from the tier-distribution chart because they don't contribute to
# the Lake state.
# Shared with the SharePoint build (Private/Get-TableTierProfile.ps1) so
# the page's pie and the dashboard's lake panel count the same tables the
# same way.
$tierProfile   = Get-TableTierProfile -Tables $operationalTables -LakeEnrolled $hasDataLake
$tierStats     = $tierProfile.Tiers
$retentionRows = $tierProfile.RetentionRows

# Asset-data system tables that Sentinel Data Lake auto-ingests on
# tenant onboarding. Detecting these by name confirms the Lake's
# Microsoft Entra / Microsoft 365 / Azure Resource Graph asset
# pipelines are actually populating the workspace.
$assetTableNames = @(
    @{ Pattern = '^IdentityInfo$';                 Family = 'Microsoft Entra (identity)' },
    @{ Pattern = '^EntityGraph';                   Family = 'Microsoft Sentinel graph (entities)' },
    @{ Pattern = '^Asset';                         Family = 'Azure Resource Graph (assets)' },
    @{ Pattern = '^Office(SharePoint|Exchange|Teams)';  Family = 'Microsoft 365 (activity)' },
    @{ Pattern = '^Behavior(Analytics)?$';         Family = 'Microsoft Sentinel UEBA (asset enrichment)' }
)
$assetDataRows = New-Object System.Collections.Generic.List[object]
foreach ($t in $workspaceTables) {
    foreach ($m in $assetTableNames) {
        if ($t.name -match $m.Pattern) {
            $hasData = $populatedTableNames.ContainsKey($t.name)
            $assetDataRows.Add([pscustomobject]@{
                Table       = $t.name
                Family      = $m.Family
                IngestState = if ($hasData) { 'Receiving data' } else { 'Defined, no data' }
                Retention   = $t.properties.retentionInDays
            })
            break
        }
    }
}

# Lake billing meters reference. Static per Microsoft Sentinel
# pricing docs — surfaces all five Lake-specific cost surfaces so
# reviewers know what to expect on the bill when Lake is in use.
$lakeBillingMeters = @(
    [pscustomobject]@{ Meter = 'Data lake ingestion';      ChargedPer = 'GB';            AppliesTo = 'Data ingested into tables with retention set to Lake-only. Mirrored-to-Lake ingest is not charged.' }
    [pscustomobject]@{ Meter = 'Data processing';          ChargedPer = 'GB';            AppliesTo = 'Transformations (redaction, splitting, filtering, normalization) on Lake-only ingest. Not charged for mirrored ingest.' }
    [pscustomobject]@{ Meter = 'Data lake storage';        ChargedPer = 'GB · month';    AppliesTo = 'Data remaining in Lake AFTER the analytics-tier retention period ends. Compression 6:1 applied before billing.' }
    [pscustomobject]@{ Meter = 'Data lake query';          ChargedPer = 'GB scanned';    AppliesTo = 'KQL queries and KQL jobs over Lake-tier data. Charged per uncompressed GB scanned.' }
    [pscustomobject]@{ Meter = 'Advanced data insights';   ChargedPer = 'compute hour';  AppliesTo = 'Jupyter notebook sessions, scheduled notebook jobs, custom graph build/query. Per vCore-hour (pools of 12, 32, or 80 vCores).' }
)

# Lake-derived capabilities — features that unlock automatically when
# the tenant onboards to Lake. Helps the reader connect "Lake is
# enrolled" to the operational surfaces they'd see in Defender portal.
$lakeCapabilities = @(
    [pscustomobject]@{ Capability = 'KQL exploration over Lake';          Surface = 'Defender portal · Investigate · KQL editor';   Billing = 'Data lake query (GB scanned)' }
    [pscustomobject]@{ Capability = 'KQL jobs (promote Lake → Analytics)'; Surface = 'Defender portal · Microsoft Sentinel · Jobs'; Billing = 'Data lake query (job execution)' }
    [pscustomobject]@{ Capability = 'Jupyter notebooks';                   Surface = 'Defender portal · Microsoft Sentinel · Notebooks · VS Code extension'; Billing = 'Advanced data insights (compute hour)' }
    [pscustomobject]@{ Capability = 'Microsoft Sentinel graph (embedded)'; Surface = 'Defender portal hunting graph · Blast radius'; Billing = 'No additional charge for embedded graphs' }
    [pscustomobject]@{ Capability = 'Custom graphs';                       Surface = 'Notebooks · Graph Query APIs · MCP graph tools'; Billing = 'Advanced data insights (compute hour, graph build/query)' }
    [pscustomobject]@{ Capability = 'MCP server (data exploration)';       Surface = 'Sentinel MCP server (AI agents)';              Billing = 'No charge for the server; tools invoke Lake-query meter' }
    [pscustomobject]@{ Capability = 'MCP entity analyzer';                 Surface = 'Sentinel MCP server';                           Billing = 'Security Compute Units (SCU) + Lake-query meter' }
    [pscustomobject]@{ Capability = 'Auto-ingested asset data';            Surface = 'System tables (Entra, M365, Azure Resource Graph)'; Billing = 'Ingestion + storage charged like any Lake table' }
    [pscustomobject]@{ Capability = '12-year affordable retention';         Surface = 'Manage data tiers in Defender portal';          Billing = 'Lake storage (per GB-month, 6:1 compression)' }
)

# Top-by-Lake-only-retention chart inputs (top 10 tables paying for
# extended Lake retention beyond Analytics). xychart-beta-friendly
# axis labels truncated to 14 chars.
$topRetention = @($retentionRows | Sort-Object LakeOnlyDays -Descending | Select-Object -First 10)
$retAxis  = ($topRetention | ForEach-Object {
    $n = $_.Table
    $s = if ($n.Length -gt 14) { $n.Substring(0,14) } else { $n }
    "`"$s`""
}) -join ', '
$retLakeBars = ($topRetention | ForEach-Object { $_.LakeOnlyDays }) -join ', '
$retAnaBars  = ($topRetention | ForEach-Object { $_.AnalyticsDays }) -join ', '
$retYmax = 1
foreach ($r in $topRetention) { $sum = $r.AnalyticsDays + $r.LakeOnlyDays; if ($sum -gt $retYmax) { $retYmax = $sum } }

# Lake-side ingest + cost split from $cost.ByPlan. Defensive lookups because
# older cost captures may not include DataLake.
$lakeGb = 0.0
$lakeCost = 0.0
$analyticsGb = 0.0
$analyticsCost = 0.0
if ($cost -and $cost.ByPlan) {
    if ($cost.ByPlan.PSObject.Properties.Name -contains 'DataLake') {
        $lakeGb   = [double]$cost.ByPlan.DataLake.Gb30d
        $lakeCost = [double]$cost.ByPlan.DataLake.MonthlyCost
    }
    if ($cost.ByPlan.PSObject.Properties.Name -contains 'Analytics') {
        $analyticsGb   = [double]$cost.ByPlan.Analytics.Gb30d
        $analyticsCost = [double]$cost.ByPlan.Analytics.MonthlyCost
    }
}

# Migration candidates: Analytics-plan tables with ≥0.5 GB/30d are typical
# Lake-tier candidates, particularly verbose Defender XDR advanced hunting
# tables (Device*, Email*) and verbose security logs that don't drive
# real-time detection. Every qualifying table is listed, costliest first.
$dlCandidateRows = @()
if ($cost -and $cost.PSObject.Properties.Name -contains 'AllTablesByCost' -and $cost.AllTablesByCost) {
    $dlCandidateRows = @($cost.AllTablesByCost |
        Where-Object { $_.Plan -eq 'Analytics' -and ([double]$_.Gb30d * 30.0 / (Get-BpWindow).Days) -ge 0.5 } |
        ForEach-Object {
            [pscustomobject]@{
                Table         = $_.Table
                Gb30d         = $_.Gb30d
                MonthlyCost   = $_.MonthlyCost
                Recommendation = 'Consider DataLake plan if rule queries are infrequent'
            }
        })
}

# Headline narrative — one of four states based on the captured signals.
$lakeHeadline = if ($hasDataLake -and $dlTables.Count -gt 0) {
    "**Sentinel Data Lake is enrolled and active.** $($dlTables.Count) table(s) route to the Lake at the DataLake-rate ingestion meter (~$([math]::Round($lakeGb, 2)) GB in {lookback-d}, est. `$$([math]::Round($lakeCost, 2)) / month). Analytics-plan tables continue to bill at the higher Sentinel-rate meter."
} elseif ($hasDataLake -and $dlTables.Count -eq 0) {
    "**Sentinel Data Lake is enrolled on this workspace** (``features.unifiedSentinelBillingOnly = true``), but no tables currently route to the Lake. All ingest is on the Analytics plan billed at the full Sentinel-rate meter. See *Migration candidates* below for verbose tables that could move to the Lake to reduce monthly cost, since the Lake-rate per-GB ingestion meter is typically a fraction of the Sentinel-rate."
} elseif (-not $hasDataLake -and $analyticsGb -gt 30) {
    "**Sentinel Data Lake is not enrolled.** This workspace ingests $([math]::Round($analyticsGb, 1)) GB in {lookback-d} on the Analytics plan at the full Sentinel-rate meter. For high-volume workspaces, onboarding to the unified Sentinel/Defender billing model unlocks the DataLake plan, which routes verbose, low-query tables (Defender XDR advanced hunting, raw firewall, EDR telemetry) to a cheaper ingestion tier with longer affordable retention."
} else {
    "**Sentinel Data Lake is not enrolled.** This workspace is on the legacy per-GB billing model with no Lake-tier ingest. Lake becomes cost-relevant once steady-state ingest exceeds a few hundred GB/month, particularly for verbose Defender XDR tables; below that the per-GB Analytics rate is competitive."
}

# Enrollment-signal table — primary signal is the
# Microsoft.SentinelPlatformServices resource; the workspace billing
# flag and table-plan signals are supporting checks.
$lakeResource = @($sentinelDataLake) | Select-Object -First 1
$lakeSignals = @(
    [pscustomobject]@{
        Signal      = 'Microsoft.SentinelPlatformServices/sentinelPlatformServices'
        Value       = if ($lakeResource) { "$($lakeResource.name) ($($lakeResource.location))" } else { '(not found)' }
        Interpretation = if ($lakeResource) { "Lake provisioned at tenant scope, region '$($lakeResource.location)', billing subscription '$($lakeResource.subscriptionId)' / RG '$($lakeResource.resourceGroup)'" } else { 'No Sentinel Data Lake resource found in the visible subscriptions, so the tenant is not onboarded to Lake' }
    },
    [pscustomobject]@{
        Signal      = 'workspace.properties.features.unifiedSentinelBillingOnly'
        Value       = if ($unifiedBilling) { 'true' } else { 'false / absent' }
        Interpretation = if ($unifiedBilling) { 'Workspace on unified Sentinel/Defender billing, eligible for Lake' } else { 'Workspace on legacy per-GB billing, not on the unified model' }
    },
    [pscustomobject]@{
        Signal      = "Tables on plan='DataLake'"
        Value       = "$($dlTables.Count) table(s)"
        Interpretation = if ($dlTables.Count -gt 0) { 'Data actively routed to Lake-only tier' } else { 'No tables route to Lake-only tier (mirrored data still flows when Lake is enrolled)' }
    }
)

# Lake resource detail block, only rendered when the platform-services
# resource exists. Surfaces the audit trail (createdBy/At) so reviewers
# can answer "when was this onboarded and by whom" from the doc.
$lakeResourceBlock = if ($lakeResource) {
    $createdAt = if ($lakeResource.systemData.createdAt) { Format-DateUtc $lakeResource.systemData.createdAt } else { '_(unknown)_' }
    $modifiedAt = if ($lakeResource.systemData.lastModifiedAt) { Format-DateUtc $lakeResource.systemData.lastModifiedAt } else { '_(unknown)_' }
    @"

## Lake resource detail

| Property | Value |
|---|---|
| Resource ID | ``$($lakeResource.id)`` |
| Resource name | ``$($lakeResource.name)`` |
| Region | ``$($lakeResource.location)`` |
| Subscription | ``$($lakeResource.subscriptionId)`` |
| Resource group | ``$($lakeResource.resourceGroup)`` |
| Provisioning state | ``$($lakeResource.properties.provisioningState)`` |
| System-assigned MI principal | ``$($lakeResource.identity.principalId)`` |
| Onboarded by | ``$($lakeResource.systemData.createdBy)`` |
| Onboarded at | $createdAt |
| Last modified | $modifiedAt |

The Sentinel Data Lake is a tenant-wide capability but it's provisioned as a single resource pinned to one subscription / resource group / region. Workspaces in **other regions** still mirror to the Lake. See [Onboard to Microsoft Sentinel data lake (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-onboarding) for the cross-region behaviour.
"@
} else { '' }

# Tier-distribution pie chart inputs.
$tierPieRows = @()
if ($tierStats.AnalyticsOnly    -gt 0) { $tierPieRows += "    `"Analytics only`" : $($tierStats.AnalyticsOnly)" }
if ($tierStats.MirroredOnly     -gt 0) { $tierPieRows += "    `"Analytics + Lake mirror`" : $($tierStats.MirroredOnly)" }
if ($tierStats.MirroredExtended -gt 0) { $tierPieRows += "    `"Analytics + Lake extended`" : $($tierStats.MirroredExtended)" }
if ($tierStats.LakeOnly         -gt 0) { $tierPieRows += "    `"Lake only`" : $($tierStats.LakeOnly)" }

$tierChartBlock = if ($tierPieRows.Count -ge 2) { @"

## Tier distribution

Pie of every operational table (a table that has received data in the last {lookback}, plus all CustomLog tables) by tier configuration. *Analytics + Lake mirror* is the default state on a Lake-enrolled tenant: every Analytics-plan table is auto-mirrored to the Lake at the same retention at no extra cost. *Analytics + Lake extended* means the table also stores beyond the Analytics retention in the Lake (Lake-storage meter applies). *Lake only* means the table bypasses the Analytics tier entirely (Lake-ingestion meter applies; no real-time analytics or detection rules).

``````mermaid
pie showData title Operational tables by tier configuration
$($tierPieRows -join [Environment]::NewLine)
``````
"@ } else { '' }

# Retention split bar chart — only render when at least one table has
# extended retention (otherwise the chart would be empty).
# Every table whose retention rolls into the lake, with its volume and the
# rules reading it, and whether each one is still being fed.
$retentionAllRows = @($retentionRows | ForEach-Object {
    $name = [string]$_.Table
    $use = @($tablesWithData | Where-Object { $_ -and (_RProp $_ 'DataType') -eq $name }) | Select-Object -First 1
    [pscustomobject]@{
        Table = $name; Plan = $_.Plan; AnalyticsDays = $_.AnalyticsDays; LakeOnlyDays = $_.LakeOnlyDays; TotalDays = $_.TotalDays
        Gb90d = $(if ($use) { [math]::Round((_RendererNumber (_RProp $use 'BillableLast90d' 0)), 2) } else { 0 })
        Rules = $(if ($rulesPerTable.ContainsKey($name)) { $rulesPerTable[$name] } else { 0 })
    }
} | Sort-Object @{ Expression = 'LakeOnlyDays'; Descending = $true }, Table)
$nowUtc88 = (Get-Date).ToUniversalTime()
$lakeValidationRows = @($retentionRows | ForEach-Object {
    $name = [string]$_.Table
    $use = @($tablesWithData | Where-Object { $_ -and (_RProp $_ 'DataType') -eq $name }) | Select-Object -First 1
    $last = if ($use) { _RProp $use 'LastIngested' } else { $null }
    $lastDt = $null
    if ($last) { $parsed = [datetime]::MinValue; if ([datetime]::TryParse([string]$last, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$parsed)) { $lastDt = $parsed } }
    $days = if ($lastDt) { [math]::Round(($nowUtc88 - $lastDt).TotalDays, 1) } else { $null }
    [pscustomobject]@{
        Table = $name; Plan = $_.Plan; LakeOnlyDays = $_.LakeOnlyDays
        Gb90d = $(if ($use) { [math]::Round((_RendererNumber (_RProp $use 'BillableLast90d' 0)), 2) } else { 0 })
        LastIngested = Format-DateUtc $last
        DaysSince = $(if ($null -ne $days) { $days } else { 'n/a' })
        Validation = $(if ($null -eq $days) { 'Check: no data in {lookback}' } elseif ($days -gt 7) { "Check: last record $days days ago" } else { 'OK: ingesting' })
    }
} | Sort-Object @{ Expression = { $_.Validation -like 'OK*' } }, @{ Expression = 'Gb90d'; Descending = $true })

$retentionChartBlock = if ($topRetention.Count -gt 0) { @"

## Retention that rolls into the lake

Tables paying for retention beyond the Analytics-tier interactive period. Each bar is the table's *Lake-only* retention days for the ten longest: the portion of total retention that bills against the Lake-storage meter (per GB · month, with 6:1 compression). The table below lists every one. Tables with the same Analytics retention as total retention don't appear here because they sit entirely within the Analytics retention window and incur no Lake-storage charge.

``````mermaid
---
config:
  xyChart:
    width: 1400
    height: 480
---
xychart-beta
    title "Lake-only retention days (beyond Analytics period)"
    x-axis [$retAxis]
$(Format-XyFullLabels @($topRetention | ForEach-Object { $_.Table }))
    y-axis "Days" 0 --> $($retYmax + 30)
    bar [$retLakeBars]
``````

$(Format-Table -Items $retentionAllRows -Columns 'Table','Plan','AnalyticsDays','LakeOnlyDays','TotalDays','Gb90d','Rules')

## Ingestion validation

Is each table with long-term retention still being fed? Last ingestion comes from the ``Usage`` table over {lookback}. A table kept for years that stopped receiving data is paying to retain history nobody is adding to, and its detections have gone quiet.

$(Format-Table -Items $lakeValidationRows -Columns 'Table','Plan','LakeOnlyDays','Gb90d','LastIngested','DaysSince','Validation')
"@ } else { '' }

# Lake architecture flowchart — static visual showing the three tiers
# and the ingestion / mirror / promote / query paths. Always rendered
# when Lake is enrolled because it's instructional rather than
# data-driven.
# The lake's tiers as data for the SharePoint graphic, by table count.
$lakeVisualLine = Format-VisualLine -Kind 'lake' -Data ([ordered]@{
    analyticsOnly  = [int]$tierStats.AnalyticsOnly
    mirrored       = [int]$tierStats.MirroredOnly
    extended       = [int]$tierStats.MirroredExtended
    lakeOnly       = [int]$tierStats.LakeOnly
    retentionYears = 12
    uses           = @(
        [ordered]@{ name = 'KQL jobs'; detail = 'Promote summarised data back to the Analytics tier for detection' }
        [ordered]@{ name = 'KQL exploration'; detail = 'Query the lake in the Defender portal' }
        [ordered]@{ name = 'Notebooks'; detail = 'Jupyter notebooks in VS Code' }
        [ordered]@{ name = 'Sentinel graph'; detail = 'Blast radius and hunting' }
        [ordered]@{ name = 'MCP tools'; detail = 'Entity analysis and triage' }
    )
})
$lakeArchitectureBlock = if ($hasDataLake) { @"

## Lake architecture

How data flows once the tenant is onboarded to the Lake. Source → Analytics tier → automatic mirror to Lake → optional KQL job to promote summarised data back to Analytics for detection. Notebooks and graph operate against the Lake tier directly. Lake-only tables skip the Analytics tier entirely.

``````mermaid
flowchart LR
$lakeVisualLine
    SRC[Data sources] --> ANA[(Analytics tier<br/>real-time KQL, rules)]
    SRC --> LO[(Lake-only tables<br/>verbose / low-query)]
    ANA -. auto-mirror .-> LAKE
    LO --> LAKE[(Sentinel Data Lake<br/>12-year affordable retention<br/>Parquet, 6:1 compression)]
    LAKE --> JOB[KQL jobs<br/>promote → Analytics]
    JOB --> ANA
    LAKE --> KQL[KQL exploration<br/>Defender portal]
    LAKE --> NB[Jupyter notebooks<br/>VS Code]
    LAKE --> GR[Sentinel graph<br/>blast radius, hunting]
    LAKE --> MCP[MCP tools<br/>entity analyzer, triage]

    classDef ana fill:#5b3a1a,stroke:#a73,color:#fed
    classDef lake fill:#1a3b5b,stroke:#37a,color:#dfd
    classDef tool fill:#1a3b1a,stroke:#3a3,color:#dfd
    class ANA,LO ana
    class LAKE lake
    class JOB,KQL,NB,GR,MCP tool
``````
"@ } else { '' }

# Lake-tier tables block — only when there are explicit Lake-only
# tables on the workspace.
$lakeTablesBlock = if ($dlTableRows.Count -gt 0) { @"

## Lake-only tables

Tables explicitly configured to bypass the Analytics tier and route exclusively to the Lake. These tables bill against the **Data lake ingestion** + **Data processing** meters at a lower per-GB rate than Analytics, but **analytics rules cannot query them in real time**. Use the *Manage table* page in the Defender portal to switch a table's tier.

$(Format-Table -Items $dlTableRows -Columns 'Table','RetentionDays','TotalRetention')
"@ } else { @"

## Lake-only tables

_No tables currently route to the Lake-only tier on this workspace._ When Lake is enrolled, the default behaviour is to mirror all Analytics-tier tables to the Lake at the same retention (see the tier distribution above). *Lake-only* requires explicitly switching a table's tier in **Defender portal → Microsoft Sentinel → Data management → Tables**.
"@ }

# Usage evidence for the tables that keep data in the lake beyond analytics
# retention: enabled rules reading the table, summary rules whose query
# names it, search or restore output tables derived from it, and audited
# queries from table-query-usage.json when the collector captured it.
$summaryRuleQueries = @($summaryRules | Where-Object { $_ } | ForEach-Object { [string](_RProp (_RProp $_ 'properties') 'query' '') })
$derivedSources = @{}
foreach ($t in $workspaceTables) {
    $n = [string](_RProp $t 'name' '')
    if ($n -match '^(.+?)_(SRCH|RST|KQL_CL)$') { $derivedSources[$matches[1]] = $true }
}
$tableQueryUsage = @{}
foreach ($row in @(Read-RawArray 'table-query-usage.json' | Where-Object { $_ })) { $tn = [string](_RProp $row 'Table' ''); if ($tn) { $tableQueryUsage[$tn] = $row } }
$queryUsageCaptured = Test-Path -LiteralPath (Join-Path $rawRoot 'table-query-usage.json')
$lakeUsageRows = @($retentionRows | ForEach-Object {
    $name = [string]$_.Table
    $use = @($tablesWithData | Where-Object { $_ -and (_RProp $_ 'DataType') -eq $name }) | Select-Object -First 1
    $n = if ($rulesPerTable.ContainsKey($name)) { $rulesPerTable[$name] } else { 0 }
    $inSummary = [bool]($summaryRuleQueries | Where-Object { $_ -match ('\b' + [regex]::Escape($name) + '\b') } | Select-Object -First 1)
    $inDerived = $derivedSources.ContainsKey($name)
    $q = if ($tableQueryUsage.ContainsKey($name)) { $tableQueryUsage[$name] } else { $null }
    $queries = if ($q) { [int](_RendererNumber (_RProp $q 'Queries' 0)) } else { 0 }
    $used = ($n -gt 0) -or $inSummary -or $inDerived -or ($queries -gt 0)
    [pscustomobject]@{
        Table = $name; Tier = $(if ($_.Plan -eq 'DataLake') { 'Lake only' } else { 'Analytics + Lake extended' }); LakeOnlyDays = $_.LakeOnlyDays
        Gb90d = $(if ($use) { [math]::Round((_RendererNumber (_RProp $use 'BillableLast90d' 0)), 2) } else { 0 })
        Rules = $n; SummaryRule = $(if ($inSummary) { 'Yes' } else { 'No' }); SearchRestore = $(if ($inDerived) { 'Yes' } else { 'No' })
        AuditedQueries = $(if ($queryUsageCaptured) { $queries } else { 'not captured' })
        Verdict = $(if ($used) { 'In use' } else { 'No usage evidence' })
    }
} | Sort-Object -Property @{ Expression = { $_.Verdict -eq 'In use' } }, @{ Expression = 'Gb90d'; Descending = $true })
$noExtensionRows = @($operationalTables | Where-Object {
    $_ -and (_RProp (_RProp $_ 'properties') 'plan') -eq 'Analytics' -and (Get-TableTier -Table $_ -LakeEnrolled $hasDataLake) -eq 'MirroredOnly'
} | ForEach-Object {
    $name = [string]$_.name
    $use = @($tablesWithData | Where-Object { $_ -and (_RProp $_ 'DataType') -eq $name }) | Select-Object -First 1
    $gb = if ($use) { [math]::Round((_RendererNumber (_RProp $use 'BillableLast90d' 0)), 2) } else { 0 }
    if ($gb -le 0) { return }
    [pscustomobject]@{ Table = $name; AnalyticsDays = _RProp (_RProp $_ 'properties') 'retentionInDays' ''; TotalDays = _RProp (_RProp $_ 'properties') 'totalRetentionInDays' ''; Gb90d = $gb; Rules = $(if ($rulesPerTable.ContainsKey($name)) { $rulesPerTable[$name] } else { 0 }) }
} | Sort-Object -Property Gb90d -Descending)
$lakeUsageBlock = if (-not $hasDataLake) { '' } else { @"

## Lake usage evidence

For every table that keeps data in the lake beyond its analytics retention (or routes to the lake only): is anything reading it? The signals are enabled analytics rules that reference the table, summary rules whose query names it, search or restore output tables derived from it, and audited queries from ``LAQueryLogs`` over the last {lookback} where the collector captured them. A table with no evidence is not wrong, but its extended retention is a cost nobody has justified yet.

$(if ($lakeUsageRows.Count -gt 0) { Format-Table -Items $lakeUsageRows -Columns 'Table','Tier','LakeOnlyDays','Gb90d','Rules','SummaryRule','SearchRestore','AuditedQueries','Verdict' } else { '_No table keeps data in the lake beyond its analytics retention, so there is nothing to assess._' })

## Analytics tables without extended lake retention

Tables receiving data whose total retention equals their analytics retention: on an enrolled workspace they are mirrored to the lake for the same period and nothing is kept once analytics retention expires. Confirm that matches the evidence-retention policy, especially for the tables rules depend on.

$(Format-Table -Items $noExtensionRows -Columns 'Table','AnalyticsDays','TotalDays','Gb90d','Rules')
"@ }

# Asset-data block — present when at least one asset-family table is
# detected. Helps confirm the Lake's auto-onboarded system tables
# (Entra, M365, Azure Resource Graph) are flowing.
$assetDataBlock = if ($assetDataRows.Count -gt 0) { @"

## Auto-ingested asset data

Sentinel Data Lake automatically creates and ingests asset-data tables on tenant onboarding (Microsoft Entra identity records, Microsoft 365 activity, Azure Resource Graph asset snapshots, plus UEBA enrichment). These tables appear in the Lake exploration UI as *System tables*. Receiving-data status confirms each pipeline is active.

$(Format-Table -Items $assetDataRows -Columns 'Table','Family','IngestState','Retention')
"@ } else { '' }

$lakeBody = @"
$(Format-Banner -Title "Microsoft Sentinel Data Lake")

$lakeHeadline

## Enrollment signals

The blueprint's primary signal is the **Microsoft.SentinelPlatformServices/sentinelPlatformServices** resource, captured through Resource Graph across every visible subscription. Presence of this resource means the tenant is onboarded to Sentinel Data Lake; absence means the tenant is not. The other two rows are supporting checks: the workspace-level billing flag and the table-plan routing state.

$(Format-Table -Items $lakeSignals -Columns 'Signal','Value','Interpretation')
$lakeResourceBlock
$lakeArchitectureBlock
$tierChartBlock

Retention per table, including the retention that rolls into the lake and whether each such table is still being fed, is in [89-retention.md](89-retention.md).
$lakeTablesBlock
$lakeUsageBlock
$assetDataBlock

## Cost split: Analytics vs Lake (last {lookback-d})

| Plan | Ingest (GB) | Estimated monthly cost |
|---|---:|---:|
| Analytics | $([math]::Round($analyticsGb, 2)) | `$$([math]::Round($analyticsCost, 2)) |
| DataLake  | $([math]::Round($lakeGb, 2)) | `$$([math]::Round($lakeCost, 2)) |

## Lake billing meters

When Lake is enrolled, five new meters can appear on the bill. The table below documents what each one charges for so a billing surprise can be traced to its source.

$(Format-Table -Items $lakeBillingMeters -Columns 'Meter','ChargedPer','AppliesTo')

> Notes
>
> - **Mirrored data is free**: mirroring an Analytics-plan table to the Lake at the same retention incurs no Lake-storage charge. Extended Lake-only retention beyond the Analytics period is where Lake-storage starts billing.
> - **Compression is 6:1**: Lake-storage bills the compressed footprint. 600 GB of raw logs is billed as 100 GB of compressed Lake storage.
> - **Long-term retention, search-jobs, and auxiliary-logs meters fold into the Lake meters** once the workspace is onboarded (see the onboarding doc for the exact mapping).

## Lake-derived capabilities

Features that unlock when the tenant is onboarded to the Lake. Each surface points at where it lives in the portal plus which Lake meter it bills against.

$(Format-Table -Items $lakeCapabilities -Columns 'Capability','Surface','Billing')

## Migration candidates

Top Analytics-plan tables (0.5 GB or more per 30 days) that are typical Lake-tier candidates: high ingest volume, low real-time-query frequency. Defender XDR advanced hunting surfaces (Device*, Email*, Url*) and raw EDR/firewall telemetry are the usual wins. Confirm a table's analytics-rule references first before migrating: a rule whose query joins against the candidate table will start failing if the table is moved without re-pointing the query.

$(if ($dlCandidateRows.Count -gt 0) { Format-Table -Items $dlCandidateRows -Columns 'Table','Gb30d','MonthlyCost','Recommendation' } else { '_No Analytics-plan tables above the 0.5 GB per 30 days threshold, so Lake migration is not currently cost-justified on this workspace._' })

## When to enroll

- **Sustained ingest > 500 GB/month** of verbose / low-query telemetry (Defender XDR raw events, firewall syslog, EDR process telemetry).
- **Long-tail investigations need affordable retention**: Lake supports up to 12 years at storage rates with 6:1 compression, vs Analytics' high per-GB interactive retention rate.
- **Already onboarded to the Defender unified SecOps portal**: Lake is the implicit storage tier for unified-portal workflows (graph, MCP, notebooks).
- **Compliance retention requirements**: regulatory retention obligations (SOX, GDPR audit, PCI-DSS) often demand multi-year retention that's prohibitively expensive on Analytics-tier storage.

## When to stay on the legacy model

- **Ingest < ~100 GB/month**: Analytics-plan per-GB rate is competitive at low volumes and avoids the operational complexity of plan-routing.
- **Every table queries in near-real-time**: the Lake's higher query latency makes it a poor fit for detection-rule-heavy workloads.
- **CMK encryption is required**: Sentinel Data Lake does **not** support Customer-Managed Keys; workspaces using CMK cannot use Lake experiences.
- **Compliance / contract requires PerGB2018 billing**: some enterprise agreements lock to legacy meters that don't include the Lake meter set.

[Microsoft Sentinel Data Lake overview (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-overview)
[Onboard to Microsoft Sentinel data lake (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-onboarding)
[Data lake tier billing (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/billing#data-lake-tier)
[Manage data tiers and retention (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/manage-data-overview)
[KQL and the Microsoft Sentinel data lake (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/kql-overview)
[KQL jobs (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/kql-jobs)
[Jupyter notebooks in the Sentinel data lake (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/notebooks-overview)
[Sentinel graph (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-graph-overview)
"@
Write-Section '88-sentinel-data-lake.md' $lakeBody

# Section 89: retention. The workspace-level checks and per-table overrides
# (formerly on section 81) and the retention that rolls into the lake
# (formerly on section 88), in one place.
$retentionLakeBlock = if ($retentionChartBlock) { $retentionChartBlock } else { @"

## Retention that rolls into the lake

_No table keeps data beyond its analytics retention, so nothing rolls into the lake or into long-term retention._
"@ }
$retentionBody = @"
$(Format-Banner -Title "Data Retention")

How long each table keeps its data and whether the workspace is set up to keep it cheaply. Analytics retention is the period a table stays fully queryable; total retention adds long-term retention beyond it, which bills against the data lake storage meter once the tenant is on the data lake. Table plans are in [81-table-plans-retention.md](81-table-plans-retention.md) and the data lake in [88-sentinel-data-lake.md](88-sentinel-data-lake.md).

## Retention recommendations

The three workspace-level retention checks, each shown whether or not it needs action.

$( $defaultRet = [int](_RProp $workspace.properties 'retentionInDays' 0)
   $cheaperTier = @($tableRows | Where-Object { [string]$_.Plan -in @('Basic', 'Auxiliary', 'DataLake') })
   $overrides = @($tableRows | Where-Object { [string]$_.Interactive -and ([int]$_.Interactive) -ne $defaultRet })
   $retRecs = @(
       [pscustomobject]@{
           Check = 'Default retention covers the free 90 days'
           Status = $(if ($defaultRet -lt 90) { 'Action needed' } else { 'OK' })
           Detail = "Workspace default is $defaultRet days."
           Recommendation = 'Raise the default to at least 90 days: the first 90 days of retention are included with Microsoft Sentinel ([SAC-LOG-07]).'
       }
       [pscustomobject]@{
           Check = 'Long retention uses a cheaper tier'
           Status = $(if ($defaultRet -gt 90 -and $cheaperTier.Count -eq 0) { 'Action needed' } else { 'OK' })
           Detail = "Default $defaultRet days; $($cheaperTier.Count) table(s) on the Basic, Auxiliary or data lake plan."
           Recommendation = 'Move high-volume tables that few rules read to the data lake tier, which bills well below the Analytics rate and keeps data for up to 12 years.'
       }
       [pscustomobject]@{
           Check = 'Long retention is set per table'
           Status = $(if ($defaultRet -gt 180 -and $overrides.Count -eq 0) { 'Action needed' } else { 'OK' })
           Detail = "Default $defaultRet days; $($overrides.Count) table(s) override it."
           Recommendation = 'Keep the default short and extend retention only on the tables that need it, rather than holding every table for the longest period any one of them needs.'
       }
   )
   Format-Table -Items $retRecs -Columns 'Check','Status','Detail','Recommendation' )

## Tables with non-default retention

Tables where the Interactive or Total retention setting differs from the workspace default ($($workspace.properties.retentionInDays) days) AND that have received billable data in the last {lookback}. A workspace with hundreds of rows here is usually leaking budget on long-retention tables that should be on the cheaper Archive plan.

$( $nonDefaultRows = @($tableRows | Where-Object {
        ($_.Interactive -ne $workspace.properties.retentionInDays -or $_.Total -ne $workspace.properties.retentionInDays) -and ($_.Gb90d -gt 0)
    } | Sort-Object -Property Gb90d -Descending)
   Format-Table -Items $nonDefaultRows -Columns 'Name','Plan','Interactive','Total','Archive','Gb90d' )
$retentionLakeBlock

[Data retention (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/logs/data-retention-configure) · [Manage data tiers and retention in Sentinel](https://learn.microsoft.com/azure/sentinel/manage-data-overview)
"@
Write-Section '89-retention.md' $retentionBody

# Section 96 — User-facing Microsoft references (TOC 6.x)
Write-Section '96-references-microsoft.md' (@"
$(Format-Banner -Title "Microsoft References")

Microsoft Learn pages for the topics this report covers, grouped by topic, the best-practice pages its findings link to among them. The Blueprint's own API versions, services, modules and queries are on [99-references.md](99-references.md).

## Microsoft Sentinel

| Page | Use it for |
| --- | --- |
| [Microsoft Sentinel documentation](https://learn.microsoft.com/azure/sentinel/) | The starting point for every Sentinel topic |
| [Best practices](https://learn.microsoft.com/azure/sentinel/best-practices) | Microsoft's recommendations for running Sentinel, which the findings measure against |
| [Deployment guide](https://learn.microsoft.com/azure/sentinel/deploy-overview) | Planning and rolling out a workspace, step by step |
| [Skill-up resources](https://learn.microsoft.com/azure/sentinel/skill-up-resources) | Training paths for analysts and engineers |
| [Move to the Defender portal](https://learn.microsoft.com/azure/sentinel/move-to-defender) | The move to the unified portal, as Sentinel in the Azure portal retires on 31 March 2027 |
| [Manage data overview](https://learn.microsoft.com/azure/sentinel/manage-data-overview) | How Sentinel stores, tiers and keeps data |

## Workspace design and resilience

| Page | Use it for |
| --- | --- |
| [Workspace design](https://learn.microsoft.com/azure/azure-monitor/logs/workspace-design) | Choosing how many workspaces, where, and for whom |
| [Sample workspace designs](https://learn.microsoft.com/azure/sentinel/sample-workspace-designs) | Worked designs for common organisations |
| [Workspace replication](https://learn.microsoft.com/azure/azure-monitor/logs/workspace-replication) | Keeping ingestion and queries running through a regional outage |
| [Dedicated clusters](https://learn.microsoft.com/azure/azure-monitor/logs/logs-dedicated-clusters) | When a dedicated cluster pays off, and what it adds |
| [Customer-managed keys](https://learn.microsoft.com/azure/azure-monitor/logs/customer-managed-keys) | Encrypting workspace data with your own key |
| [Azure Monitor Private Link Scope (AMPLS)](https://learn.microsoft.com/azure/azure-monitor/logs/private-link-security) | Keeping ingestion and queries on private networks |

## Data connectors and coverage

| Page | Use it for |
| --- | --- |
| [Data connectors reference](https://learn.microsoft.com/azure/sentinel/data-connectors-reference) | Every connector, what it collects and what it needs |
| [Prioritise data connectors](https://learn.microsoft.com/azure/sentinel/prioritize-data-connectors) | Which sources to connect first |
| [Tables and connectors map](https://learn.microsoft.com/azure/sentinel/sentinel-tables-connectors-reference) | Which connector fills which table |
| [Monitor connector health](https://learn.microsoft.com/azure/sentinel/monitor-data-connectors-health) | Health monitoring for connectors with SentinelHealth |
| [Codeless Connector Framework](https://learn.microsoft.com/azure/sentinel/create-codeless-connector) | Building a connector without code |
| [MITRE ATT&CK coverage](https://learn.microsoft.com/azure/sentinel/mitre-coverage) | Viewing detection coverage against MITRE ATT&CK |

## Content and automation

| Page | Use it for |
| --- | --- |
| [Content Hub solutions](https://learn.microsoft.com/azure/sentinel/sentinel-solutions) | Installing and keeping solutions current |
| [Repositories (CI/CD)](https://learn.microsoft.com/azure/sentinel/ci-cd) | Deploying content from source control |
| [Custom content in CI/CD](https://learn.microsoft.com/azure/sentinel/ci-cd-custom-content) | Customising repository deployments |
| [Automate responses with playbooks](https://learn.microsoft.com/azure/sentinel/automation/automate-responses-with-playbooks) | Playbooks and how automation rules call them |
| [Logic Apps documentation](https://learn.microsoft.com/azure/logic-apps/) | The platform playbooks run on |

## Log Analytics, tables and retention

| Page | Use it for |
| --- | --- |
| [Log Analytics overview](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview) | Querying workspace data in the portal |
| [KQL quick reference](https://learn.microsoft.com/azure/data-explorer/kql-quick-reference) | The query language at a glance |
| [Get started with log queries](https://learn.microsoft.com/azure/azure-monitor/logs/get-started-queries) | A first KQL tutorial |
| [Table plans](https://learn.microsoft.com/azure/azure-monitor/logs/logs-table-plans) | Analytics, Basic and Auxiliary plans, and what each allows |
| [Configure Basic logs](https://learn.microsoft.com/azure/azure-monitor/logs/basic-logs-configure) | Moving a table to the Basic plan |
| [Retention and archive](https://learn.microsoft.com/azure/azure-monitor/logs/data-retention-archive) | Interactive and total retention per table |
| [Manage table tiers and retention](https://learn.microsoft.com/azure/sentinel/manage-table-tiers-retention) | Sentinel's view of tiers and retention, the data lake included |
| [Microsoft Sentinel data lake](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-overview) | Long-term, low-cost storage that stays queryable |
| [Data collection rules](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview) | How data is collected, transformed and routed |
| [Data export](https://learn.microsoft.com/azure/azure-monitor/logs/logs-data-export) | Continuous export to storage or Event Hubs |

## Cost

| Page | Use it for |
| --- | --- |
| [Plan costs and understand billing](https://learn.microsoft.com/azure/sentinel/billing) | How Sentinel and Log Analytics charge |
| [Reduce costs](https://learn.microsoft.com/azure/sentinel/billing-reduce-costs) | Commitment tiers, table plans and filtering |
| [Monitor costs](https://learn.microsoft.com/azure/sentinel/billing-monitor-costs) | Tracking spend and ingestion over time |
| [Azure Monitor cost best practices](https://learn.microsoft.com/azure/azure-monitor/fundamentals/best-practices-cost) | Cost recommendations across Azure Monitor |
| [Cost of logs](https://learn.microsoft.com/azure/azure-monitor/logs/cost-logs) | Pricing for ingestion, retention and queries |
| [Daily cap](https://learn.microsoft.com/azure/azure-monitor/logs/daily-cap) | Capping daily ingestion, and what it stops |
| [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices) | The price list the cost estimate reads |

## Health and troubleshooting

| Page | Use it for |
| --- | --- |
| [Health, audit and monitoring](https://learn.microsoft.com/azure/sentinel/health-audit) | SentinelHealth and SentinelAudit, and what they record |
| [Log data ingestion time](https://learn.microsoft.com/azure/azure-monitor/logs/data-ingestion-time) | Why data arrives late, and how to measure it |

## Access and the wider platform

| Page | Use it for |
| --- | --- |
| [Roles and permissions](https://learn.microsoft.com/azure/sentinel/roles) | Sentinel's built-in roles and what each can do |
| [Microsoft Defender XDR documentation](https://learn.microsoft.com/defender-xdr/) | The unified security platform Sentinel joins |
"@)

# ---------------------------------------------------------------------------
# Section: 99 — references
# ---------------------------------------------------------------------------
$refSrc = Join-Path $PSScriptRoot 'Private/Resources/Blueprint-References.md'
if (Test-Path $refSrc) {
    if ($script:WriteMarkdown) {
        Copy-Item -Path $refSrc -Destination (Join-Path $OutputRoot '99-references.md') -Force
        Write-Information "  ↳ copied 99-references.md"
    }
    if ($script:WriteJson) { Write-SectionModel -FileName '99-references.md' -Markdown (Get-Content -LiteralPath $refSrc -Raw) }
}

# ---------------------------------------------------------------------------
# Index
# ---------------------------------------------------------------------------
$indexBody = @"
# ${WorkspaceName}: Sentinel Documentation Index

Generated $(Format-DateUtc $run.StartedAtUtc) UTC by iSOC Blueprint v$($run.BlueprintVersion).

Sections are numbered to match the formal Sentinel Configuration TOC where applicable. Customer-narrative sections (architectural diagrams, SOC operational processes, the licensing inventory) are intentionally not generated, so supply those separately.

| Section | TOC | Description |
|---|---|---|
| [00-overview.md](00-overview.md) | - | Headline counts, top findings, cost summary |
| [01-live-snapshot.md](01-live-snapshot.md) | 1 | Workspace at a glance, regenerated every pipeline run |
| [02-deprecated-legacy-features.md](02-deprecated-legacy-features.md) | - | Retirement deadlines and the legacy features still in use |
| [10-data-connectors.md](10-data-connectors.md) | 4.7 | Classic + CCF connectors |
| [11-sentinel-health.md](11-sentinel-health.md) | 4.8 | SentinelHealth events, last {lookback} |
| [12-soc-optimization.md](12-soc-optimization.md) | 4.9 | SOC Optimization recommendations |
| [13-data-source-hygiene.md](13-data-source-hygiene.md) | - | CEF/Syslog hygiene, agent dual-collection, top noisy events |
| [14-coverage-breakdowns.md](14-coverage-breakdowns.md) | - | AzureActivity / AzureDiagnostics / XDR coverage by source |
| [15-incidents.md](15-incidents.md) | 4.10 | Incident MTTA/MTTR, outcomes, incidents by rule and by provider |
| [16-alerts.md](16-alerts.md) | 4.10 | Alert volume by severity, detection source and provider |
| [20-analytics-rules.md](20-analytics-rules.md) | 4.11 | All detection rules by kind, Microsoft-managed rules, recent modifications, Content Hub solution, Defender XDR custom detections |
| [21-rule-performance.md](21-rule-performance.md) | 4.11.2 | Alert volume per rule, rule effectiveness, noisy rules |
| [22-rule-health-quality.md](22-rule-health-quality.md) | - | Rule run failures, entity-mapping and incident-creation anti-patterns, stale rules, template drift, complexity |
| [25-mitre-coverage.md](25-mitre-coverage.md) | 3.2 | Tactic + technique + sub-technique coverage |
| [26-ueba.md](26-ueba.md) | 4.16 | UEBA configuration |
| [27-threat-intelligence.md](27-threat-intelligence.md) | 4.17 | Indicator counts by source, STIX objects, feeds |
| [28-detection-opportunities.md](28-detection-opportunities.md) | - | Tables with data but no detection, templates ready to enable |
| [30-hunting-queries.md](30-hunting-queries.md) | 4.15 | Hunting queries |
| [35-parsers-functions.md](35-parsers-functions.md) | - | Parsers and functions |
| [36-data-export.md](36-data-export.md) | 4.3.3 | Data export configuration |
| [37-search-restore.md](37-search-restore.md) | 4.3.4 | Search jobs / restore logs |
| [38-summary-rules.md](38-summary-rules.md) | 4.3.5 | Summary rules |
| [40-workbooks.md](40-workbooks.md) | 4.14 | Saved workbooks + templates |
| [50-watchlists.md](50-watchlists.md) | 4.12 | Watchlists |
| [60-automation-rules-playbooks.md](60-automation-rules-playbooks.md) | 4.13 | Automation rules + playbooks + MI grants |
| [70-content-hub.md](70-content-hub.md) | 4.6 | Solutions installed + repositories |
| [80-workspace.md](80-workspace.md) | 4.2 | SKU, retention, networking, feature flags |
| [81-table-plans-retention.md](81-table-plans-retention.md) | 4.3.1 | Per-table plan, activity, detection coverage |
| [82-dedicated-cluster.md](82-dedicated-cluster.md) | 4.2.2 | Dedicated cluster, CMK, AZ |
| [83-data-collection.md](83-data-collection.md) | - | DCRs and DCEs |
| [84-cost-estimate.md](84-cost-estimate.md) | - | Estimated monthly cost |
| [85-rbac.md](85-rbac.md) | 4.4 | Role assignments |
| [86-subscription-context.md](86-subscription-context.md) | 4.1 | Subscription, tenant, RPs, locks, policy |
| [87-azure-monitor-agents.md](87-azure-monitor-agents.md) | 4.5 | AMA agents heartbeating into the workspace |
| [88-sentinel-data-lake.md](88-sentinel-data-lake.md) | - | Sentinel Data Lake enrollment, Lake-tier tables, migration candidates |
| [89-retention.md](89-retention.md) | 4.3.2 | Retention checks, per-table overrides, retention that rolls into the lake, ingestion validation |
| [90-gap-analysis.md](90-gap-analysis.md) | - | Findings against MS Learn best practices |
| [91-maturity-assessment.md](91-maturity-assessment.md) | - | Maturity by area, roadmap, quick wins, NIST CSF rollup |
| [96-references-microsoft.md](96-references-microsoft.md) | 6 | Microsoft Learn pages by topic, best practices included |
| [99-references.md](99-references.md) | - | Blueprint's own API versions and modules |
"@
Write-Section 'index.md' $indexBody

if ($script:WriteJson) {
    # sections/index.json: every section in reading order.
    $ordered = @($script:SectionIndex | Sort-Object @{ Expression = { if ($null -eq $_.order) { [int]::MaxValue } else { $_.order } } }, @{ Expression = { $_.id } })
    [ordered]@{ schemaVersion = 1; meta = $script:SectionMeta; sections = $ordered } |
        ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $script:SectionsRoot 'index.json') -Encoding utf8
}

Write-Information "Renderer complete, output: $OutputRoot"
