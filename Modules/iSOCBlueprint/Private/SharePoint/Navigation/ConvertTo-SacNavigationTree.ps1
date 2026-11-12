#Requires -Version 7.6

<#
.SYNOPSIS
    Turn the site descriptor's sections into a navigation tree.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Navigation/ConvertTo-SacNavigationTree.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function ConvertTo-SacNavigationTree {
    <#
    .SYNOPSIS
        Turn navigation nodes read from SharePoint into the planner's
        @{ title; url; children } shape, with URLs in '~site/' form.

    .PARAMETER Nodes
        Objects with Title, Url and Children (as Get-PnPNavigationNode
        -Tree returns them).

    .PARAMETER WebServerRelativeUrl
        The web's server-relative URL, used to rewrite URLs back to the
        '~site/' prefix so they compare with the plan.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Nodes,
        [Parameter(Mandatory)] [string] $WebServerRelativeUrl
    )

    $base = $WebServerRelativeUrl.TrimEnd('/')
    $out = foreach ($n in $Nodes) {
        $url = [string]$n.Url
        if ($url -eq $script:SacLinklessHeaderUrl -or $url -eq $script:SacLinklessHeaderUrl.TrimEnd('/')) { $url = $null }
        elseif ($url) {
            # Absolute URLs come back for some nodes; reduce to server-relative.
            if ($url -match '^https?://[^/]+(?<path>/.*)$') { $url = $Matches['path'] }
            if ($url.StartsWith("$base/", [StringComparison]::OrdinalIgnoreCase)) { $url = '~site/' + $url.Substring($base.Length + 1) }
        }
        $kids = @()
        # No @() around the call: the function returns its array as a single
        # object, and wrapping it would nest the array one level deeper.
        if ($n.Children) { $kids = ConvertTo-SacNavigationTree -Nodes @($n.Children) -WebServerRelativeUrl $WebServerRelativeUrl }
        [ordered]@{ title = [string]$n.Title; url = $url; children = $kids }
    }
    return , @($out)
}
