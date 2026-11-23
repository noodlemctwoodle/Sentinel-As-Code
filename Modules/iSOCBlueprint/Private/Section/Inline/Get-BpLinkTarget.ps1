#Requires -Version 7.6

<#
.SYNOPSIS
    Say what a link points at

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/Get-BpLinkTarget.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-BpLinkTarget {
    <#
    .SYNOPSIS
        Say what a link points at.

    .DESCRIPTION
        Returns an ordered dictionary whose kind says what the link is:
        finding for '#sac-xxx-nn', optionally after 90-gap-analysis.md, with id
        set to the upper-case finding id; external for an http, https or mailto
        link; anchor for '#name', with anchor set to the name; section for
        '<nn>-<name>.md' or 'index.md', optionally with a leading './' and a
        '#name' part, with section set to the file name without '.md' and
        anchor set to the '#name' part or $null; and repo for anything else,
        with path set to the link as written.

    .PARAMETER Href
        The link's destination as written in the Markdown.

    .OUTPUTS
        An ordered dictionary with kind and the entries that kind names.
    #>
    [CmdletBinding()]
    param([string] $Href)
    if ($Href -match '^(?:90-gap-analysis\.md)?#(?<id>sac-[a-z]{2,4}-\d{2})$') { return [ordered]@{ kind = 'finding'; id = $Matches['id'].ToUpperInvariant() } }
    if ($Href -match '^(?:https?|mailto):') { return [ordered]@{ kind = 'external' } }
    if ($Href -match '^#(?<a>.+)$') { return [ordered]@{ kind = 'anchor'; anchor = $Matches['a'] } }
    if ($Href -match '^(?:\./)?(?<s>\d{2}-[a-z0-9-]+|index)\.md(?:#(?<a>.+))?$') {
        return [ordered]@{ kind = 'section'; section = $Matches['s']; anchor = $(if ($Matches['a']) { $Matches['a'] } else { $null }) }
    }
    return [ordered]@{ kind = 'repo'; path = $Href }
}
