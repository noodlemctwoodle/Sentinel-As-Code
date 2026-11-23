#Requires -Version 7.6

<#
.SYNOPSIS
    Write one report section as Markdown and as the section model.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Output/Write-BlueprintSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-BlueprintSection {
    <#
    .SYNOPSIS
        Write one report section as Markdown and as the section model.

    .DESCRIPTION
        The body has its window placeholders resolved (Resolve-BlueprintWindowText),
        gets the page description from $script:SectionDescriptions under the title
        and workspace line, and has finding ids outside code fences linked to the
        gap analysis page. Reference links are moved to the foot
        (Move-BlueprintReferenceLink) except on index.md. The Markdown is written
        under $script:OutputRoot when $script:WriteMarkdown is set, and the section
        model is written through Write-BlueprintSectionModel when $script:WriteJson
        is set.

    .PARAMETER FileName
        The page file name, such as 90-gap-analysis.md. It decides the description
        and which finding ids are linked.

    .PARAMETER Body
        The page Markdown.
    #>
    [CmdletBinding()]
    param([string]$FileName, [string]$Body)
    $target = Join-Path $script:OutputRoot $FileName
    $body = $Body.TrimEnd() + [Environment]::NewLine
    # The window the KQL captures read, named where a page says {lookback}
    # ("30 days"), {lookback-d} ("30d"), {recent} or {recent-d}.
    $body = Resolve-BlueprintWindowText $body
    # The page's description goes under the title and its workspace line.
    if ($script:SectionDescriptions.ContainsKey($FileName)) {
        $desc = Resolve-BlueprintWindowText $script:SectionDescriptions[$FileName]
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
    if ($FileName -ne 'index.md') { $body = Move-BlueprintReferenceLink $body }
    if ($script:WriteMarkdown) {
        Set-Content -Path $target -Value $body -Encoding UTF8
        if ($FileName -ne 'index.md') { $script:PagesWritten++ }
        Write-Verbose "rendered $FileName"
    }
    if ($script:WriteJson) { Write-BlueprintSectionModel -FileName $FileName -Markdown $body }
}
