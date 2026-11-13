#Requires -Version 7.6

<#
.SYNOPSIS
    Get-BpLinkTarget

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/Get-BpLinkTarget.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-BpLinkTarget {
    <#
    .SYNOPSIS
        Say what a link points at: kind section (section, anchor), finding
        (id), anchor (anchor, same page), external, or repo (path).
    #>
    param([string] $Href)
    if ($Href -match '^(?:90-gap-analysis\.md)?#(?<id>sac-[a-z]{2,4}-\d{2})$') { return [ordered]@{ kind = 'finding'; id = $Matches['id'].ToUpperInvariant() } }
    if ($Href -match '^(?:https?|mailto):') { return [ordered]@{ kind = 'external' } }
    if ($Href -match '^#(?<a>.+)$') { return [ordered]@{ kind = 'anchor'; anchor = $Matches['a'] } }
    if ($Href -match '^(?:\./)?(?<s>\d{2}-[a-z0-9-]+|index)\.md(?:#(?<a>.+))?$') {
        return [ordered]@{ kind = 'section'; section = $Matches['s']; anchor = $(if ($Matches['a']) { $Matches['a'] } else { $null }) }
    }
    return [ordered]@{ kind = 'repo'; path = $Href }
}
