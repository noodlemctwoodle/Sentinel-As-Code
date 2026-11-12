#Requires -Version 7.6

<#
.SYNOPSIS
    Rebuild the site's quick-launch navigation.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Navigation/Set-SacNavigation.ps1
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

function Set-SacNavigation {
    <#
    .SYNOPSIS
        Replace the site's whole top navigation with the planned tree. The
        generator owns the top navigation.

    .PARAMETER Nodes
        Planned nodes from Get-NavigationPlan.

    .PARAMETER WebServerRelativeUrl
        The web's server-relative URL, to resolve '~site/' links.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [object[]] $Nodes,
        [Parameter(Mandatory)] [string] $WebServerRelativeUrl
    )
    if (-not $PSCmdlet.ShouldProcess('TopNavigationBar', "Replace with $($Nodes.Count) top-level nodes")) { return }

    # Node by node: -Location and -All are in different parameter sets, and
    # -All on its own clears whichever location the enum defaults to. Removing
    # a top-level node removes its children with it.
    foreach ($old in @(Get-PnPNavigationNode -Location TopNavigationBar -ErrorAction SilentlyContinue)) {
        Remove-PnPNavigationNode -Identity $old.Id -Force | Out-Null
    }
    foreach ($n in $Nodes) {
        $url = if ($n.url) { Resolve-SacSiteUrl -Text $n.url -WebServerRelativeUrl $WebServerRelativeUrl } else { $script:SacLinklessHeaderUrl }
        $parent = Add-PnPNavigationNode -Location TopNavigationBar -Title $n.title -Url $url
        foreach ($c in @($n.children)) {
            if (-not $c) { continue }
            $childUrl = Resolve-SacSiteUrl -Text $c.url -WebServerRelativeUrl $WebServerRelativeUrl
            Add-PnPNavigationNode -Location TopNavigationBar -Title $c.title -Url $childUrl -Parent $parent.Id | Out-Null
        }
    }
}
