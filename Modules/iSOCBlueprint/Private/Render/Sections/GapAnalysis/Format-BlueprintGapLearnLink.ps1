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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-BlueprintGapLearnLink {
    <#
    .SYNOPSIS
        Format a finding's Learn link for its remediation card.

    .DESCRIPTION
        Returns _(no reference)_ when there is no URL. Otherwise a Markdown link
        whose text is the last path segment of the URL with hyphens as spaces, in
        title case, followed by (Microsoft Learn). The text is Microsoft Learn when
        the path has no segment or the URL does not parse.

    .PARAMETER Url
        The Learn page URL.

    .OUTPUTS
        [string] of Markdown.
    #>
    [OutputType([string])]
    [CmdletBinding()]
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
