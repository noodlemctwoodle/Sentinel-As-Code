#Requires -Version 7.6

<#
.SYNOPSIS
    Resolve-WhatsNewLink

.NOTES
    File:         Modules/iSOCBlueprint/Private/WhatsNew/Helpers/Resolve-WhatsNewLink.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, What's new reading
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Resolve-WhatsNewLink {
    <#
    .SYNOPSIS
        A link on a Learn page as an absolute URL: site-relative paths on
        learn.microsoft.com, bare paths beside the page.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Href, [string] $PageUrl)
    $h = $Href.Trim()
    if ($h -match '^https?://') { return $h }
    if ($h.StartsWith('/')) { return 'https://learn.microsoft.com' + $h }
    if ($h.StartsWith('#')) { return $PageUrl + $h }
    $base = $PageUrl.Substring(0, $PageUrl.LastIndexOf('/') + 1)
    return $base + $h
}
