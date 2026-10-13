#Requires -Version 7.2

<#
.SYNOPSIS
    Read the data connector catalogue and match a workspace's connectors
    and tables against it.

.DESCRIPTION
    Resources/connector-catalogue.json lists every Microsoft Sentinel data
    connector with the tables it writes and the Content Hub solution that
    ships it (copied from the Sentinel as Code Toolkit by
    Update-ConnectorCatalogue.ps1). The renderer and the gap engine use it
    to name the connector behind a table, to tell a connected connector
    that is receiving data from one that has gone quiet, and to point a
    table at the solution that ships it.

    A connector's tables come from its own mapping where Microsoft
    publishes one, otherwise from every table its solution's content uses,
    so a list can include tables the connector does not write. The helpers
    allow for that: a connector counts as silent only when none of its
    tables received data, and a table several connectors claim is called
    shared rather than pinned on one of them.

.NOTES
    File:         Tools/Blueprint/Private/Get-ConnectorCatalogue.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Import-ConnectorCatalogue {
    <#
    .SYNOPSIS
        Load the catalogue and index it by connector id and by table.

    .PARAMETER Path
        Path to connector-catalogue.json.

    .OUTPUTS
        [pscustomobject] Version, Connectors, ById (id to connector) and
        ByTable (table to the connectors that write it), both keyed without
        regard to case; $null when the file is missing.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $doc = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 8
    $byId = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    $byTable = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($c in @($doc.connectors)) {
        if (-not $c -or -not $c.id) { continue }
        $byId[[string]$c.id] = $c
        foreach ($t in @($c.tables)) {
            if (-not $t) { continue }
            if (-not $byTable.ContainsKey([string]$t)) { $byTable[[string]$t] = [System.Collections.Generic.List[object]]::new() }
            $byTable[[string]$t].Add($c)
        }
    }
    # ConvertFrom-Json reads the ISO timestamp as a [datetime].
    $version = if ($doc.version -is [datetime]) { $doc.version.ToUniversalTime().ToString('yyyy-MM-dd') } else { ([string]$doc.version).Substring(0, [math]::Min(10, ([string]$doc.version).Length)) }
    return [pscustomobject]@{
        Version    = $version
        Connectors = @($doc.connectors)
        ById       = $byId
        ByTable    = $byTable
    }
}

function Get-WorkspaceConnectorId {
    <#
    .SYNOPSIS
        The catalogue id of a data connector resource from the workspace.

    .DESCRIPTION
        A codeless (CCF) connector's resource has a generic kind
        (RestApiPoller, GCP, Push) and names its connector definition, which
        is the catalogue id; any other connector's kind is the id.

    .PARAMETER Connector
        One entry from data-connectors-classic.json.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowNull()] $Connector)

    if ($null -eq $Connector) { return '' }
    $props = if ($Connector.PSObject.Properties['properties']) { $Connector.properties } else { $null }
    if ($props -and $props.PSObject.Properties['connectorDefinitionName'] -and $props.connectorDefinitionName) {
        return [string]$props.connectorDefinitionName
    }
    if ($Connector.PSObject.Properties['kind']) { return [string]$Connector.kind }
    return ''
}

function Get-TableActivity {
    <#
    .SYNOPSIS
        Data received per table in the last 7 days, free tables included.

    .DESCRIPTION
        Reads IngestedLast7d (all volume) and falls back to BillableLast7d
        for older captures. tables-with-data.json has one row per table and
        solution, so the rows are summed per table.

    .PARAMETER TablesWithData
        The rows of tables-with-data.json.

    .OUTPUTS
        [hashtable] table name to GB, case-insensitive.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowNull()] [AllowEmptyCollection()] [object[]] $TablesWithData)

    $gb = [System.Collections.Hashtable]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in @($TablesWithData)) {
        if ($null -eq $row -or -not $row.PSObject.Properties['DataType']) { continue }
        $name = [string]$row.DataType
        if (-not $name) { continue }
        $field = if ($row.PSObject.Properties['IngestedLast7d']) { 'IngestedLast7d' } elseif ($row.PSObject.Properties['BillableLast7d']) { 'BillableLast7d' } else { $null }
        $value = 0.0
        if ($field) { [void][double]::TryParse([string]$row.$field, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$value) }
        $gb[$name] = $(if ($gb.ContainsKey($name)) { $gb[$name] } else { 0.0 }) + $value
    }
    return $gb
}

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
        $status = if (-not $entry) { 'Not in the catalogue' } elseif ($tables.Count -eq 0) { 'No tables in the catalogue' } elseif ($withData.Count) { 'Receiving data' } else { 'Silent' }
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

function Get-TableSolutionLabel {
    <#
    .SYNOPSIS
        Name the Content Hub solutions that ship a table, marking the ones
        installed on the workspace.

    .PARAMETER Catalogue
        The output of Import-ConnectorCatalogue.

    .PARAMETER Table
        A table name.

    .PARAMETER InstalledSolutions
        Display names of the installed Content Hub solutions.

    .OUTPUTS
        [string] The solutions, '(installed)' after each one installed, when
        at most three ship the table; otherwise how many share it and which
        of them are installed. '' when the catalogue does not know the table.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Catalogue,
        [Parameter(Mandatory)] [string] $Table,
        [AllowEmptyCollection()] [string[]] $InstalledSolutions = @()
    )

    if (-not $Catalogue.ByTable.ContainsKey($Table)) { return '' }
    $solutions = @(@($Catalogue.ByTable[$Table]) | ForEach-Object { [string]$_.solution } | Where-Object { $_ -and $_ -ne 'Platform' } | Sort-Object -Unique)
    if ($solutions.Count -eq 0) { return '' }
    $installed = @($solutions | Where-Object { $s = $_; @($InstalledSolutions | Where-Object { $_ -and $_.Equals($s, [StringComparison]::OrdinalIgnoreCase) }).Count })
    if ($solutions.Count -le 3) {
        return (@($solutions | ForEach-Object { if ($installed -contains $_) { "$_ (installed)" } else { $_ } }) -join '; ')
    }
    $tail = if ($installed.Count) { '; installed: ' + ($installed -join '; ') } else { '' }
    return "Shared by $($solutions.Count) solutions$tail"
}
