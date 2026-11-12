#Requires -Version 7.6

<#
.SYNOPSIS
    Work out what a What's new item touches in this workspace.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/WhatsNew/Get-WhatsNewRelations.ps1
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
