#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 37-search-restore.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/SearchRestore/Write-BlueprintSearchRestoreSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintSearchRestoreSection {
    <#
    .SYNOPSIS
        Build the figures for and write 37-search-restore.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $f = $Context.f
    $m = $Context.m
    $n = $Context.n
    $name = $Context.name
    $p = $Context.p
    $r = $Context.r
    $rawRoot = $Context.rawRoot
    $s = $Context.s
    $t = $Context.t

    # Section 37 — Search and restore (TOC 4.3.4)
    # A search job leaves a _SRCH table and a restore a _RST table in the
    # workspace's table list. The collector saves them as search-jobs.json and
    # restore-logs.json; a snapshot collected before it did reads them from
    # workspace-tables.json instead.
    $searchJobs = Read-BlueprintRawArray 'search-jobs.json'
    $restoreJobs = Read-BlueprintRawArray 'restore-logs.json'
    if (-not (Test-Path (Join-Path $rawRoot 'search-jobs.json')) -and -not (Test-Path (Join-Path $rawRoot 'restore-logs.json'))) {
        $found = Get-SearchRestoreTable -Tables @(Read-BlueprintRawArray 'workspace-tables.json')
        $searchJobs = @($found.SearchJobs)
        $restoreJobs = @($found.Restores)
    }
    $srProp = {
        param($Object, [string]$Name)
        if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) { $Object.$Name } else { $null }
    }
    $srWindow = {
        param($From, $To)
        $f = Format-DateUtc $From; $t = Format-DateUtc $To
        if ($f -or $t) { "$f to $t UTC" } else { '' }
    }
    $searchRows = @($searchJobs | ForEach-Object {
            $p = $_.properties; $s = & $srProp $p 'searchResults'
            [pscustomobject]@{
                'Table'         = [string]$_.name
                'Source table'  = [string](& $srProp $s 'sourceTable')
                'Search window' = & $srWindow (& $srProp $s 'startSearchTime') (& $srProp $s 'endSearchTime')
                'Created (UTC)' = Format-DateUtc (& $srProp $p 'createDate')
                'Retention'     = $(if ($null -ne (& $srProp $p 'totalRetentionInDays')) { (Format-BlueprintPlural (& $srProp $p 'totalRetentionInDays') 'day') } else { '' })
                'Query'         = $(if (& $srProp $s 'query') { '`' + ([string](& $srProp $s 'query')).Trim() + '`' } else { '' })
            }
        })
    $restoreRows = @($restoreJobs | ForEach-Object {
            $p = $_.properties; $r = & $srProp $p 'restoredLogs'
            [pscustomobject]@{
                'Table'           = [string]$_.name
                'Source table'    = [string](& $srProp $r 'sourceTable')
                'Restored window' = & $srWindow (& $srProp $r 'startRestoreTime') (& $srProp $r 'endRestoreTime')
                'Created (UTC)'   = Format-DateUtc (& $srProp $p 'createDate')
            }
        })
    Write-BlueprintSection '37-search-restore.md' (@"
$(Format-Banner -Title 'Search and Restore Tables  (TOC 4.3.4)')

Search jobs and restores bring data back from long-term retention into tables you can query: a search job writes its matches to a table ending in ``_SRCH``, a restore a time range of a table to one ending in ``_RST``. Each table stays until someone deletes it, so this is every search and restore whose table is still in the workspace: **$(Format-BlueprintPlural @($searchRows).Count 'search job')** and **$(Format-BlueprintPlural @($restoreRows).Count 'restore')**.

## Search jobs

$(Format-BlueprintTable -Items $searchRows -Columns 'Table','Source table','Search window','Created (UTC)','Retention','Query' -EmptyMessage '_No search job tables in the workspace._')

## Restores

$(Format-BlueprintTable -Items $restoreRows -Columns 'Table','Source table','Restored window','Created (UTC)' -EmptyMessage '_No restored tables in the workspace._')

[Search jobs in Azure Monitor Logs](https://learn.microsoft.com/azure/azure-monitor/logs/search-jobs) · [Restore logs](https://learn.microsoft.com/azure/azure-monitor/logs/restore)
"@)

    # Left in the render context for later sections.
    if (Get-Variable -Name 'found' -Scope 0 -ErrorAction Ignore) { $Context.found = $found }
}
