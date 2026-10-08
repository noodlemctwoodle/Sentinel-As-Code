#Requires -Version 7.2

<#
.SYNOPSIS
    Pure planning functions for the SharePoint site publisher: decide what
    to create, update, resolve or remove before anything touches SharePoint.

.DESCRIPTION
    The publisher reads the current state of the site (pages, findings list
    items, navigation, asset files), passes it here with the freshly built
    bundle, and gets back a plan. Keeping the decisions out of the PnP code
    means they are unit-tested without a SharePoint connection, and -WhatIf
    can print exactly what a run would do.

    Get-PageSyncPlan       pages to create, update, skip or delete
    Get-FindingSyncPlan    findings list items to add, update, reopen,
                           resolve or retire
    Get-NavigationPlan     the top navigation tree and a signature to tell
                           whether it changed
    Get-AssetPrunePlan     asset files no longer referenced

.NOTES
    File:         Tools/Documenter/SharePoint/Private/Get-SacSyncPlan.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-08
    Version:      0.1.0
    Last Updated: 2026-10-08
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-PageSyncPlan {
    <#
    .SYNOPSIS
        Decide which generated section pages to create, update, skip or
        delete.

    .PARAMETER Desired
        The pages in this bundle: objects with Name (page name without
        .aspx) and Hash (content hash).

    .PARAMETER ExistingNames
        Names (without .aspx) of the generated pages already in Site Pages.
        Only pages the generator owns (the 'sac-' prefix) should be passed.

    .PARAMETER PublishedHashes
        Hashtable of page name to the content hash recorded by the last
        successful publish. A page with no recorded hash is always updated.

    .OUTPUTS
        [pscustomobject[]] Name and Action (Create, Update, Skip, Delete).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Desired,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ExistingNames,
        [Parameter(Mandatory)] [hashtable] $PublishedHashes
    )

    $existing = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $ExistingNames) { [void]$existing.Add($n) }
    $wanted = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    $plan = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($d in $Desired) {
        [void]$wanted.Add($d.Name)
        $action = if (-not $existing.Contains($d.Name)) { 'Create' }
                  elseif ($PublishedHashes.ContainsKey($d.Name) -and $PublishedHashes[$d.Name] -eq $d.Hash) { 'Skip' }
                  else { 'Update' }
        $plan.Add([pscustomobject]@{ Name = $d.Name; Action = $action })
    }
    foreach ($n in ($ExistingNames | Sort-Object)) {
        if (-not $wanted.Contains($n)) { $plan.Add([pscustomobject]@{ Name = $n; Action = 'Delete' }) }
    }
    return $plan.ToArray()
}

function Get-FindingSyncPlan {
    <#
    .SYNOPSIS
        Decide how the findings list changes for this run, keeping a history
        of findings that stop firing.

    .DESCRIPTION
        A finding that fires is added (new), updated (already open) or
        reopened (previously resolved or retired). An open finding that did
        not fire is only resolved when the gap engine says its check ran and
        passed; a check that errored leaves the finding open, because the
        engine could not tell either way. A finding whose rule is no longer
        in the rule set is retired.

        When the snapshot has no per-check outcomes (artefacts from before
        gap-checks.json existed), an open finding that did not fire is
        resolved. When the snapshot has no gap analysis at all, nothing is
        resolved: an absent analysis is not evidence that anything was
        fixed.

    .PARAMETER Current
        The findings that fired in this run: objects with id, title,
        severity, category, evidence, remediation, learn.

    .PARAMETER Existing
        Items already in the list: objects with ItemId, FindingId and Status.

    .PARAMETER Checks
        Per-check outcomes from gap-checks.json (objects with Id and
        Outcome: Fired, Passed, Errored, Undefined), or $null when the
        snapshot predates that file.

    .PARAMETER AnalysisAvailable
        $false when the snapshot has no gap-analysis.json.

    .PARAMETER NowUtc
        Timestamp written to FirstSeen / LastSeen / ResolvedOn.

    .OUTPUTS
        [pscustomobject[]] Action (Add, Update, Reopen, Resolve, Retire),
        FindingId, ItemId ($null for Add) and Values (hashtable of list
        field values to write).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Current,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Existing,
        [AllowNull()] [object[]] $Checks,
        [Parameter(Mandatory)] [bool] $AnalysisAvailable,
        [Parameter(Mandatory)] [datetime] $NowUtc
    )

    $sevRank = @{ 'Critical' = 0; 'Error' = 1; 'High' = 1; 'Warning' = 2; 'Medium' = 2; 'Info' = 3; 'Informational' = 3; 'Low' = 3 }
    $now = $NowUtc.ToUniversalTime()

    $existingById = @{}
    foreach ($e in $Existing) { if ($e.FindingId) { $existingById[[string]$e.FindingId] = $e } }

    $checksById = $null
    if ($null -ne $Checks) {
        $checksById = @{}
        foreach ($c in $Checks) { if ($c.Id) { $checksById[[string]$c.Id] = [string]$c.Outcome } }
    }

    $plan = [System.Collections.Generic.List[pscustomobject]]::new()
    $fired = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($f in $Current) {
        $id = [string]$f.id
        if (-not $id) { continue }
        [void]$fired.Add($id)
        $severity = [string]$f.severity
        $values = @{
            Title        = [string]$f.title
            FindingId    = $id
            Severity     = $severity
            SeverityRank = $(if ($sevRank.ContainsKey($severity)) { $sevRank[$severity] } else { 4 })
            Category     = [string]$f.category
            Evidence     = [string]$f.evidence
            Remediation  = [string]$f.remediation
            Learn        = $(if ($f.learn) { "$($f.learn), Microsoft Learn" } else { $null })
            Status       = 'Open'
            LastSeen     = $now
        }

        if (-not $existingById.ContainsKey($id)) {
            $values.FirstSeen = $now
            $values.ResolvedOn = $null
            $plan.Add([pscustomobject]@{ Action = 'Add'; FindingId = $id; ItemId = $null; Values = $values })
        }
        elseif ([string]$existingById[$id].Status -ne 'Open') {
            $values.ResolvedOn = $null
            $plan.Add([pscustomobject]@{ Action = 'Reopen'; FindingId = $id; ItemId = $existingById[$id].ItemId; Values = $values })
        }
        else {
            $plan.Add([pscustomobject]@{ Action = 'Update'; FindingId = $id; ItemId = $existingById[$id].ItemId; Values = $values })
        }
    }

    if (-not $AnalysisAvailable) { return $plan.ToArray() }

    foreach ($id in ($existingById.Keys | Sort-Object)) {
        if ($fired.Contains($id)) { continue }
        $item = $existingById[$id]
        if ([string]$item.Status -ne 'Open') { continue }

        $action = $null
        if ($null -eq $checksById) {
            $action = 'Resolve'
        }
        elseif (-not $checksById.ContainsKey($id)) {
            $action = 'Retire'
        }
        elseif ($checksById[$id] -eq 'Passed') {
            $action = 'Resolve'
        }
        # Errored / Undefined: the engine could not evaluate the check, so
        # the finding stays open.

        if ($action) {
            $status = if ($action -eq 'Retire') { 'Retired' } else { 'Resolved' }
            $plan.Add([pscustomobject]@{
                    Action    = $action
                    FindingId = $id
                    ItemId    = $item.ItemId
                    Values    = @{ Status = $status; ResolvedOn = $now }
                })
        }
    }

    return $plan.ToArray()
}

function Get-NavigationPlan {
    <#
    .SYNOPSIS
        Build the top navigation tree for the site.

    .DESCRIPTION
        One node for the dashboard, one heading per section family (in the
        family display order, only families with at least one page that
        exists), each with its section pages as children, and a node for the
        findings list. URLs use the '~site/' prefix the publisher resolves.

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
        if ($children.Count -eq 0) { continue }
        $nodes.Add([ordered]@{ title = $family; url = $null; children = $children })
    }

    $nodes.Add([ordered]@{ title = 'Findings'; url = "~site/$FindingsListUrl/AllItems.aspx"; children = @() })

    return [pscustomobject]@{
        Nodes     = $nodes.ToArray()
        Signature = Get-NavigationSignature -Nodes $nodes.ToArray()
    }
}

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

function Get-AssetPrunePlan {
    <#
    .SYNOPSIS
        Return the asset files on the site that this bundle no longer uses.

    .PARAMETER DesiredFiles
        File names this bundle uploads into the folder.

    .PARAMETER ExistingFiles
        File names currently in the folder on the site.

    .OUTPUTS
        [string[]] Names to remove.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $DesiredFiles,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ExistingFiles
    )

    $wanted = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in $DesiredFiles) { [void]$wanted.Add($f) }
    return @($ExistingFiles | Where-Object { -not $wanted.Contains($_) } | Sort-Object)
}
