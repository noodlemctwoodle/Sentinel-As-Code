#Requires -Version 7.6

<#
.SYNOPSIS
    Move a page's reference links to its foot.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Output/Move-BlueprintReferenceLinks.ps1
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

function Move-BlueprintReferenceLinks {
    <#
    .SYNOPSIS
        Move a page's reference links to its foot.

    .DESCRIPTION
        A page's reference links all sit at its foot, so a reader knows where to
        look. A block of text outside a code fence that holds nothing but links to
        http or https pages (alone, in a bullet list, or led by words such as "See
        also" or "References") is removed from where it stands. The links are
        gathered into a "## References" list at the foot, one entry per distinct URL
        in the order the page first gives it; an entry that came from under a
        finding heading is prefixed with the finding id. Links inside a sentence or
        a table stay where they are, as do blocks that start as a table, block quote
        or HTML. The page is returned unchanged when no block qualifies.

    .PARAMETER Markdown
        The page Markdown.

    .OUTPUTS
        [string] of Markdown.
    #>
    [CmdletBinding()]
    param([string]$Markdown)
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
            $items = if (@($block | Where-Object { $_ -notmatch '^\s*[-*]\s' }).Count -eq 0) {
                @($block | ForEach-Object { $_ -replace '^\s*[-*]\s+', '' })
            } else { @($block -join ' ') }
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
