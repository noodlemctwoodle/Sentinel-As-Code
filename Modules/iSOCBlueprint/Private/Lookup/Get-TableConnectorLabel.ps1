#Requires -Version 7.6

<#
.SYNOPSIS
    Name the connector the catalogue credits with a table

.DESCRIPTION
    Split from Get-ConnectorCatalogue.ps1 so each file holds one function.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Get-TableConnectorLabel.ps1
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

function Get-TableConnectorLabel {
    <#
    .SYNOPSIS
        Name the connector the catalogue credits with a table.

    .DESCRIPTION
        A row that already names its connector (a classic connector's data
        type) is credited to that connector when the catalogue lists the
        table for it. Otherwise the connectors that list the table are
        named when there are at most three, each marked "(connected)" when
        it is connected to the workspace, and a table more connectors list
        is called shared. Connected connectors are not preferred beyond
        that, because a connector's list can include tables its solution
        only reads. A table the catalogue does not know returns ''.

    .PARAMETER Catalogue
        The output of Import-ConnectorCatalogue.

    .PARAMETER Table
        A table name.

    .PARAMETER ConnectedIds
        Catalogue ids of the workspace's connectors (Get-WorkspaceConnectorId).

    .PARAMETER ConnectorId
        The catalogue id of the connector the row came from, when known.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Catalogue,
        [Parameter(Mandatory)] [string] $Table,
        [AllowEmptyCollection()] [string[]] $ConnectedIds = @(),
        [string] $ConnectorId = ''
    )

    if ($ConnectorId -and $Catalogue.ById.ContainsKey($ConnectorId)) {
        $own = $Catalogue.ById[$ConnectorId]
        if (@($own.tables) -contains $Table) { return [string]$own.title }
    }
    if (-not $Catalogue.ByTable.ContainsKey($Table)) { return '' }
    $list = @($Catalogue.ByTable[$Table])
    if ($list.Count -le 3) {
        # Two catalogue entries can share a title (a connector and its newer
        # codeless version), so each label appears once.
        return (@($list | ForEach-Object {
                    if ($ConnectedIds -contains [string]$_.id) { "$($_.title) (connected)" } else { [string]$_.title }
                } | Sort-Object -Unique) -join '; ')
    }
    return "Shared by $($list.Count) connectors"
}
