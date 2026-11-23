#Requires -Version 7.6

<#
.SYNOPSIS
    One row per connector in the workspace, matched against the catalogue

.DESCRIPTION
    Split from Get-ConnectorCatalogue.ps1 so each file holds one function.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Get-ConnectorCatalogueStatus.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-ConnectorCatalogueStatus {
    <#
    .SYNOPSIS
        One row per connector in the workspace, matched against the
        catalogue: the tables it writes that received data in 7 days, the
        ones that did not, and a status.

    .PARAMETER Catalogue
        The output of Import-ConnectorCatalogue.

    .PARAMETER Connectors
        The workspace's data connector resources (data-connectors-classic.json).

    .PARAMETER Activity
        The output of Get-TableActivity.

    .OUTPUTS
        [pscustomobject] Connector, Id, Solution, Deprecated, Tables,
        WithData, Quiet, Status. Status is 'Receiving data', 'Silent' (no
        table it writes received data), 'No tables in the catalogue' or
        'Not in the catalogue'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Catalogue,
        [AllowNull()] [AllowEmptyCollection()] [object[]] $Connectors,
        [Parameter(Mandatory)] [hashtable] $Activity
    )

    foreach ($c in @($Connectors)) {
        if ($null -eq $c) { continue }
        $id = Get-WorkspaceConnectorId -Connector $c
        if (-not $id) { continue }
        $entry = if ($Catalogue.ById.ContainsKey($id)) { $Catalogue.ById[$id] } else { $null }
        $tables = @(if ($entry) { @($entry.tables) | Where-Object { $_ } | ForEach-Object { [string]$_ } })
        $withData = @($tables | Where-Object { $Activity.ContainsKey($_) -and $Activity[$_] -gt 0 })
        $quiet = @($tables | Where-Object { $withData -notcontains $_ })
        $status = if (-not $entry) {
            'Not in the catalogue'
        } elseif ($tables.Count -eq 0) { 'No tables in the catalogue' } elseif ($withData.Count) { 'Receiving data' } else { 'Silent' }
        [pscustomobject]@{
            Connector  = $(if ($entry) { [string]$entry.title } else { $id })
            Id         = $id
            Solution   = $(if ($entry) { [string]$entry.solution } else { '' })
            Deprecated = [bool]($entry -and $entry.deprecated)
            Tables     = $tables
            WithData   = $withData
            Quiet      = $quiet
            Status     = $status
        }
    }
}
