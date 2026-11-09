#Requires -Version 7.6

<#
.SYNOPSIS
    Read the table to Content Hub solution mapping.

.DESCRIPTION
    The mapping is refreshed from the Azure-Sentinel Solutions Analyzer and
    ships in the module's Resources/ClassicToDcr folder.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCSolutionMapping.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCSolutionMapping {
    <#
    .SYNOPSIS
        Read the table to Content Hub solution mapping.

    .DESCRIPTION
        The mapping comes from the Azure-Sentinel Solutions Analyzer and
        ships as Resources/ClassicToDcr/solution-mapping.json. It is read as
        a hashtable, because it has an empty property name that
        ConvertFrom-Json accepts only that way, and _normalizedLookup is
        added: tablesToSolutions keyed without case. A missing file is a
        warning and no mapping.

    .PARAMETER Path
        The mapping file. Defaults to the module's own.

    .OUTPUTS
        [hashtable] The mapping, with _normalizedLookup; nothing when the
        file is missing.

    .EXAMPLE
        $mapping = Get-iSOCSolutionMapping
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string] $Path = (Join-Path $script:iSOCDeploymentsRoot 'Resources/ClassicToDcr/solution-mapping.json')
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-iSOCLog "Solution mapping file not found at $Path" -Level Warning
        return $null
    }
    $raw = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 20 -AsHashtable

    $normalized = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $raw['tablesToSolutions'].GetEnumerator()) {
        $normalized[$entry.Key] = $entry.Value
    }
    $raw['_normalizedLookup'] = $normalized
    $raw
}
