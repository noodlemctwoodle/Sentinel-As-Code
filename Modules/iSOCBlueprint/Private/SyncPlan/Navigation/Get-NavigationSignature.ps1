#Requires -Version 7.6

<#
.SYNOPSIS
    Flatten a navigation tree into a comparable string.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SyncPlan/Navigation/Get-NavigationSignature.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, SharePoint sync planning
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-NavigationSignature {
    <#
    .SYNOPSIS
        Flatten a navigation tree into a comparable string.

    .DESCRIPTION
        Used on both the planned tree and the tree read back from the site,
        so the publisher only rebuilds navigation when it differs. URLs are
        compared case-insensitively and without a trailing slash.

    .PARAMETER Nodes
        Array of @{ title; url; children }.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Nodes)

    $parts = foreach ($n in $Nodes) {
        $u = if ($n.url) { ([string]$n.url).TrimEnd('/').ToLowerInvariant() } else { '' }
        $kids = if ($n.children) { Get-NavigationSignature -Nodes @($n.children) } else { '' }
        "$($n.title)|$u[$kids]"
    }
    return ($parts -join ';')
}
