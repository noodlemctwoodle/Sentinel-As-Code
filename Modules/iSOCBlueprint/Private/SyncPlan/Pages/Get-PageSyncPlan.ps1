#Requires -Version 7.6

<#
.SYNOPSIS
    Decide which generated section pages to create, update, skip or delete.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SyncPlan/Pages/Get-PageSyncPlan.ps1
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
