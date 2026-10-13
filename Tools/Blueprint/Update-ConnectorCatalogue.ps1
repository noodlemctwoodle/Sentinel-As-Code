#Requires -Version 7.2

<#
.SYNOPSIS
    Refreshes the Blueprint's data connector catalogue
    (Tools/Blueprint/Private/Resources/connector-catalogue.json) from the
    Sentinel as Code Toolkit's connectors.json.

.DESCRIPTION
    The Toolkit (noodlemctwoodle/Sentinel-As-Code-Toolkit) builds
    data/connectors.json from Microsoft's Solutions Analyzer CSVs in the
    Azure-Sentinel repository: every Content Hub data connector with the
    tables it writes, its publisher and the solution that ships it. The
    Toolkit owns that extraction (scripts/extract-connectors.mjs, with its
    overrides and platform pseudo-connectors); this script takes its output
    and writes the slimmer copy the Blueprint reads, so both tools agree on
    which connector writes which table.

    The copy drops the Markdown descriptions, turns the single-table string
    form into a list, records whether a connector is deprecated (the
    Toolkit marks the title "[Deprecated]") and writes one connector per
    line so a refresh diffs cleanly.

    A connector's table list comes from the connector's own table mapping
    where Microsoft publishes one, otherwise from every table its
    solution's content uses. The second kind can name tables the connector
    does not write (a solution whose rules also read SigninLogs), so the
    Blueprint only treats a connector as silent when none of its tables has
    data, and names a table shared by several connectors as shared.

.PARAMETER Source
    Path or URL of the Toolkit's connectors.json. Defaults to the file on
    the Toolkit's main branch.

.PARAMETER OutputPath
    Where to write the catalogue. Defaults to the Blueprint resources
    folder.

.EXAMPLE
    ./Tools/Blueprint/Update-ConnectorCatalogue.ps1

.EXAMPLE
    ./Tools/Blueprint/Update-ConnectorCatalogue.ps1 -Source ../Sentinel-As-Code-Toolkit/data/connectors.json

.NOTES
    File:         Tools/Blueprint/Update-ConnectorCatalogue.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Source = 'https://raw.githubusercontent.com/noodlemctwoodle/Sentinel-As-Code-Toolkit/main/data/connectors.json',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path $PSScriptRoot 'Private/Resources/connector-catalogue.json')
)

$ErrorActionPreference = 'Stop'

$raw = if ($Source -match '^https?://') {
    (Invoke-WebRequest -Uri $Source -UseBasicParsing).Content
}
else {
    Get-Content -LiteralPath $Source -Raw
}
$doc = $raw | ConvertFrom-Json -Depth 16
if (-not $doc.PSObject.Properties['tablesByConnector']) { throw "No tablesByConnector in '$Source'; is it the Toolkit's connectors.json?" }

$connectors = @(foreach ($c in @($doc.tablesByConnector)) {
        if (-not $c -or -not $c.connectorId) { continue }
        $tables = @(@($c.tables) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        $title = [string]$c.connectorTitle
        [ordered]@{
            id         = [string]$c.connectorId
            title      = ($title -replace '\s*\[deprecated\]\s*', ' ').Trim()
            publisher  = [string]$c.publisher
            solution   = ([string]$c.source -replace '^Solutions/', '')
            deprecated = [bool]($title -match '\[Deprecated\]')
            tables     = $tables
        }
    }) | Sort-Object { $_.id }

$meta = $doc.metadata
# ConvertFrom-Json reads an ISO timestamp as a [datetime]; write it back as ISO.
$upstreamDate = if ($meta.generatedDate -is [datetime]) { $meta.generatedDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { [string]$meta.generatedDate }
$header = [ordered]@{
    '$comment'  = 'Microsoft Sentinel data connectors and the tables each writes, used by the Blueprint to name the connector behind a table, to check connected connectors for silence (SAC-PLT-10) and to point tables at the Content Hub solution that ships them. Copied from the Sentinel as Code Toolkit by Update-ConnectorCatalogue.ps1; do not edit by hand.'
    version     = $upstreamDate
    generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    source      = $Source
    upstream    = "$($meta.sourceRepository) (Tools/Solutions Analyzer, $($meta.extractionMethod))"
    license     = 'Derived from the Azure-Sentinel repository, MIT licence (https://github.com/Azure/Azure-Sentinel/blob/master/LICENSE)'
}

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('{')
foreach ($key in $header.Keys) { [void]$sb.AppendLine("  $(ConvertTo-Json $key): $(ConvertTo-Json $header[$key]),") }
[void]$sb.AppendLine('  "connectors": [')
for ($i = 0; $i -lt $connectors.Count; $i++) {
    $line = '    ' + ($connectors[$i] | ConvertTo-Json -Compress -Depth 4)
    if ($i -lt $connectors.Count - 1) { $line += ',' }
    [void]$sb.AppendLine($line)
}
[void]$sb.AppendLine('  ]')
[void]$sb.Append('}')
Set-Content -LiteralPath $OutputPath -Value $sb.ToString() -Encoding utf8NoBOM

$tableCount = @($connectors | ForEach-Object { $_.tables } | Sort-Object -Unique).Count
Write-Host "Connector catalogue written: $OutputPath"
Write-Host "  $($connectors.Count) connectors ($(@($connectors | Where-Object { $_.tables.Count }).Count) with tables, $(@($connectors | Where-Object deprecated).Count) deprecated), $tableCount tables; upstream generated $upstreamDate"
