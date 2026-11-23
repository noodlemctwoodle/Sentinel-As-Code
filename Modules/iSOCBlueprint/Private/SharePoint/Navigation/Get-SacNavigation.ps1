#Requires -Version 7.6

<#
.SYNOPSIS
    Read the site's quick-launch navigation.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Navigation/Get-SacNavigation.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SacNavigation {
    <#
    .SYNOPSIS
        Read the site's top navigation as a planner-shaped tree.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)] [string] $WebServerRelativeUrl)
    # Not -Tree: that writes a printed text tree, not nodes. The top-level
    # nodes come back without their children; Get-PnPNavigationNode -Id loads
    # one node with its children. The plan is two levels deep, so the
    # children's own (unloaded) Children are never read.
    $top = @(Get-PnPNavigationNode -Location TopNavigationBar -ErrorAction SilentlyContinue)
    if ($top.Count -eq 0) { return , @() }
    $shaped = foreach ($t in $top) {
        $node = Get-PnPNavigationNode -Id $t.Id -ErrorAction Stop
        [pscustomobject]@{
            Title    = [string]$node.Title
            Url      = [string]$node.Url
            Children = @(@($node.Children) | Where-Object { $null -ne $_ } | ForEach-Object {
                    [pscustomobject]@{ Title = [string]$_.Title; Url = [string]$_.Url; Children = @() }
                })
        }
    }
    $tree = ConvertTo-SacNavigationTree -Nodes @($shaped) -WebServerRelativeUrl $WebServerRelativeUrl
    return , $tree
}
