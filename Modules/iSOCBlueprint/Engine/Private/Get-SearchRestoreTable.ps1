#Requires -Version 7.2

<#
.SYNOPSIS
    Pick the search job result tables and the restored tables out of a
    Log Analytics workspace's table list.

.DESCRIPTION
    A search job writes its results to a new table whose name ends in _SRCH
    (schema.tableType SearchResults, with a searchResults block naming the
    source table, query and time range). A restore brings archived data back
    into a table ending in _RST (schema.tableType RestoredLogs, with a
    restoredLogs block). Both stay in the workspace's tables API until
    someone deletes them, so the table list the collector already saves
    (workspace-tables.json) is the record of searches and restores.

    The collector writes search-jobs.json and restore-logs.json from this;
    the maturity model (SAC-INV-02) and the Report's search and restore page
    fall back to it for snapshots collected before it did.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Get-SearchRestoreTable.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SearchRestoreTable {
    <#
    .SYNOPSIS
        The search job and restore tables in a workspace's table list.

    .PARAMETER Tables
        Table objects as the tables API returns them (name, properties).

    .OUTPUTS
        [pscustomobject] SearchJobs and Restores, each an array of the
        matching table objects, sorted by name.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([AllowNull()] [AllowEmptyCollection()] [object[]] $Tables)

    $has = {
        param($Object, [string]$Name)
        $null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name -and $null -ne $Object.$Name
    }
    $search = [System.Collections.Generic.List[object]]::new()
    $restore = [System.Collections.Generic.List[object]]::new()
    foreach ($t in @($Tables)) {
        if (-not $t -or -not $t.name) { continue }
        $p = $t.properties
        $type = if ((& $has $p 'schema') -and (& $has $p.schema 'tableType')) { [string]$p.schema.tableType } else { '' }
        $name = [string]$t.name
        if ($type -eq 'SearchResults' -or (& $has $p 'searchResults') -or $name -like '*_SRCH') { $search.Add($t) }
        elseif ($type -eq 'RestoredLogs' -or (& $has $p 'restoredLogs') -or $name -like '*_RST') { $restore.Add($t) }
    }
    [pscustomobject]@{
        SearchJobs = @($search | Sort-Object { [string]$_.name })
        Restores   = @($restore | Sort-Object { [string]$_.name })
    }
}
