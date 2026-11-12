#Requires -Version 7.6

<#
.SYNOPSIS
    Format a finding's Learn link for its remediation card.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/GapAnalysis/Format-BlueprintGapLearnLink.ps1
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

function Format-BlueprintGapLearnLink {
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
