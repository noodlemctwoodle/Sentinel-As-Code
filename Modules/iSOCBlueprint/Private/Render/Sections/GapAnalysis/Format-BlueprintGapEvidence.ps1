#Requires -Version 7.6

<#
.SYNOPSIS
    Format a finding's evidence for its remediation card.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/GapAnalysis/Format-BlueprintGapEvidence.ps1
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

function Format-BlueprintGapEvidence {
    <#
    .SYNOPSIS
        Format a finding's evidence for its remediation card.

    .DESCRIPTION
        Evidence text from gap rules can be very long, with semicolon-separated
        lists (hundreds of disabled rule names, say), which is unreadable in a
        narrow table cell. The detail-card form splits a long semicolon list into
        bullet items and renders short evidence inline. Empty evidence gives
        _(none)_. A lone ? entry (from a snapshot taken before the gap checks named
        unnamed principals) is replaced by words. Evidence of 200 characters or more
        with at least three semicolons is expanded into a bulleted list, one item
        per semicolon-separated part, with any lead-in up to the first colon (when
        within the first 200 characters) kept ahead of the list.

    .PARAMETER Evidence
        The evidence text of a finding.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
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

$(($items | ForEach-Object { "  - $(ConvertTo-BlueprintListItem $_)" }) -join [Environment]::NewLine)
"@
    }
    # No leading colon — bullet the whole list.
    $items = $Evidence -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    return ($items | ForEach-Object { "  - $(ConvertTo-BlueprintListItem $_)" }) -join [Environment]::NewLine
}
