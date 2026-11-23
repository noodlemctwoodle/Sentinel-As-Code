#Requires -Version 7.6

<#
.SYNOPSIS
    Build the top navigation tree for the site.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SyncPlan/Navigation/Get-NavigationPlan.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint sync planning
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-NavigationPlan {
    <#
    .SYNOPSIS
        Build the top navigation tree for the site.

    .DESCRIPTION
        One node for the dashboard, one heading per section family (in the
        family display order, only families with at least one page that
        exists), each with its section pages as children. The findings list
        sits under the Assessment family, beside the gap analysis and the
        maturity assessment, or as its own node when no Assessment page
        exists. URLs use the '~site/' prefix the publisher resolves.

    .PARAMETER Sections
        Section descriptors from site.json: objects with page, title,
        family, num.

    .PARAMETER ExistingPages
        Page names (without .aspx) that exist on the site after the page
        sync. Sections whose page is missing are left out, so navigation
        never points at a page that failed to publish.

    .PARAMETER FamilyOrder
        Family names in display order.

    .PARAMETER DashboardPage
        Dashboard page name without .aspx.

    .PARAMETER FindingsListUrl
        Site-relative URL of the findings list.

    .OUTPUTS
        [pscustomobject] Nodes (array of @{ title; url; children }) and
        Signature (string) for change detection.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Sections,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ExistingPages,
        [Parameter(Mandatory)] [string[]] $FamilyOrder,
        [Parameter(Mandatory)] [string] $DashboardPage,
        [Parameter(Mandatory)] [string] $FindingsListUrl
    )

    $exists = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $ExistingPages) { [void]$exists.Add($p) }

    $nodes = [System.Collections.Generic.List[object]]::new()
    $nodes.Add([ordered]@{ title = 'Dashboard'; url = "~site/SitePages/$DashboardPage.aspx"; children = @() })

    foreach ($family in $FamilyOrder) {
        $children = @($Sections |
                Where-Object { $_.family -eq $family -and $exists.Contains([string]$_.page) } |
                Sort-Object { [int]$_.num } |
                ForEach-Object { [ordered]@{ title = [string]$_.title; url = "~site/SitePages/$($_.page).aspx"; children = @() } })
        if ($family -eq 'Assessment' -and $children.Count -gt 0) {
            $children += [ordered]@{ title = 'Findings list'; url = "~site/$FindingsListUrl/AllItems.aspx"; children = @() }
        }
        if ($children.Count -eq 0) { continue }
        $nodes.Add([ordered]@{ title = $family; url = $null; children = $children })
    }

    if (-not @($nodes | Where-Object { $_.title -eq 'Assessment' }).Count) {
        $nodes.Add([ordered]@{ title = 'Findings'; url = "~site/$FindingsListUrl/AllItems.aspx"; children = @() })
    }

    return [pscustomobject]@{
        Nodes     = $nodes.ToArray()
        Signature = Get-NavigationSignature -Nodes $nodes.ToArray()
    }
}
