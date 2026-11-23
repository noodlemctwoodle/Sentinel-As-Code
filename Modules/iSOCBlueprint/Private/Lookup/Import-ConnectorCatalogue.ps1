#Requires -Version 7.6

<#
.SYNOPSIS
    Load the catalogue and index it by connector id and by table

.DESCRIPTION
    Split from Get-ConnectorCatalogue.ps1 so each file holds one function.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Import-ConnectorCatalogue.ps1
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
    $version = if ($doc.version -is [datetime]) {
        $doc.version.ToUniversalTime().ToString('yyyy-MM-dd')
    } else { ([string]$doc.version).Substring(0, [math]::Min(10, ([string]$doc.version).Length)) }
    return [pscustomobject]@{
        Version    = $version
        Connectors = @($doc.connectors)
        ById       = $byId
        ByTable    = $byTable
    }
}
