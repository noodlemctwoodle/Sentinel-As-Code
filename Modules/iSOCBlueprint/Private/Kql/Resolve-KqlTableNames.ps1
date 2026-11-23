#Requires -Version 7.6

<#
.SYNOPSIS
    Return the sorted, unique table names a query reads, plus any tables declared through connector...

.DESCRIPTION
    Split from Get-KqlTableReferences.ps1 so each file holds one function.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Kql/Resolve-KqlTableNames.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-09
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+, SentinelCommon.Kql.ps1 (dot-sourced by the caller)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Resolve-KqlTableNames {
    <#
    .SYNOPSIS
        Return the sorted, unique table names a query reads, plus any tables
        declared through connector data types.

    .PARAMETER Query
        KQL text. May be empty.

    .PARAMETER DataTypes
        Values of requiredDataConnectors[].dataTypes, for example
        'OfficeActivity (SharePoint)'. The first identifier token of each
        entry is taken as the table name.

    .OUTPUTS
        [string[]]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] [AllowEmptyString()] [string] $Query,
        [Parameter(Mandatory = $false)] [AllowNull()] [string[]] $DataTypes
    )

    $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        $candidates = [System.Collections.Generic.List[string]]::new()
        foreach ($id in @(Get-KqlBareIdentifiers -Query $Query)) { $candidates.Add([string]$id) }

        # Get-KqlBareIdentifiers takes only the first operand after 'union';
        # templates often write 'union SecurityEvent, WindowsEvent', so pick up
        # the rest of a comma-separated list here.
        $stripped = Remove-KqlComments -Query $Query
        foreach ($m in [regex]::Matches($stripped, '(?im)\bunion\b(?:\s+(?:kind|withsource|isfuzzy|hint\.[a-z]+)\s*=\s*[A-Za-z0-9_]+)*\s+([A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)+)')) {
            foreach ($part in ($m.Groups[1].Value -split ',')) { $candidates.Add($part.Trim()) }
        }

        foreach ($id in $candidates) {
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            if ($id -match $script:KqlFunctionNamePattern) { continue }
            [void]$names.Add($id)
        }
    }

    foreach ($dt in @($DataTypes)) {
        if ([string]::IsNullOrWhiteSpace($dt)) { continue }
        if ("$dt" -match '^\s*([A-Za-z_][A-Za-z0-9_]*)') { [void]$names.Add($Matches[1]) }
    }

    # Emitted item by item so callers get a plain string array whether they
    # assign the result, wrap it in @() or pipe it.
    return @($names | Sort-Object)
}
