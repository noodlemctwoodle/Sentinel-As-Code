#Requires -Version 7.6

<#
.SYNOPSIS
    Map a Tables API column type onto a DCR stream declaration type.

.DESCRIPTION
    guid has no stream type, so it is declared string; an unknown type is
    string, with a warning.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCDcrColumnType.ps1
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

function Get-iSOCDcrColumnType {
    <#
    .SYNOPSIS
        Map a Tables API column type onto a DCR stream declaration type.

    .DESCRIPTION
        string, int, long, real, boolean (and bool), datetime and dynamic map
        to themselves, in any case (the Tables API writes dateTime). guid
        has no stream type: Azure Monitor stores GUIDs as strings and both
        ingestion APIs send them as strings, so it is declared string, and
        Get-iSOCDcrDefaultTransform casts it back. Anything else is string,
        with a warning.

    .PARAMETER TableColumnType
        The column's Tables API type.

    .OUTPUTS
        [string]

    .EXAMPLE
        Get-iSOCDcrColumnType -TableColumnType dateTime
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $TableColumnType
    )

    $map = @{
        'string'   = 'string'
        'int'      = 'int'
        'long'     = 'long'
        'real'     = 'real'
        'boolean'  = 'boolean'
        'bool'     = 'boolean'
        'datetime' = 'datetime'
        'dynamic'  = 'dynamic'
        'guid'     = 'string'
    }
    $key = $TableColumnType.ToLowerInvariant()
    if ($map.ContainsKey($key)) { return $map[$key] }

    Write-iSOCLog "Unrecognised column type '$TableColumnType'. Declaring it as 'string'." -Level Warning
    'string'
}
