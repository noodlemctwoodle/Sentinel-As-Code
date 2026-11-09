#Requires -Version 7.6

<#
.SYNOPSIS
    The table names no fixture alias may take: the fixed floor and every table in the solution mapping.

.DESCRIPTION
    The workspace's own tables are checked separately; this list covers
    tables that may arrive later.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Get-iSOCReservedTableName.ps1
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

function Get-iSOCReservedTableName {
    <#
    .SYNOPSIS
        The table names no fixture alias may take: the fixed floor and every
        table in the solution mapping.

    .DESCRIPTION
        The workspace's own table list is the authoritative check, since it
        knows the customer's tables; this list covers names that could
        appear later, from the fixed floor and the tablesToSolutions keys of
        the solution mapping the module ships. A mapping that cannot be read
        is a warning and the floor alone.

    .PARAMETER MappingPath
        The solution mapping. Defaults to the module's own.

    .OUTPUTS
        [string[]]

    .EXAMPLE
        Get-iSOCReservedTableName
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string] $MappingPath = (Join-Path $script:iSOCDeploymentsRoot 'Resources/ClassicToDcr/solution-mapping.json')
    )

    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in (Get-iSOCDependencyFixtureSetting).ReservedTableFloor) { [void]$names.Add($name) }

    if ([string]::IsNullOrWhiteSpace($MappingPath) -or -not (Test-Path -LiteralPath $MappingPath -PathType Leaf)) {
        Write-iSOCLog "Solution mapping not found at '$MappingPath'. Falling back to the static reserved-name floor." -Level Warning
        return @($names)
    }
    try {
        $mapping = Get-Content -LiteralPath $MappingPath -Raw | ConvertFrom-Json -AsHashtable
        if ($mapping -and $mapping.ContainsKey('tablesToSolutions') -and $mapping['tablesToSolutions']) {
            foreach ($tableName in $mapping['tablesToSolutions'].Keys) {
                if ([string]::IsNullOrWhiteSpace($tableName)) { continue }
                [void]$names.Add([string]$tableName)
            }
        }
    }
    catch {
        Write-iSOCLog "Could not read the solution mapping: $($_.Exception.Message.Split([char]10)[0]). Falling back to the static reserved-name floor." -Level Warning
    }
    @($names)
}
