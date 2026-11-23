#Requires -Version 7.6

<#
.SYNOPSIS
    Turn a declared column type into the Tables API type it means.

.DESCRIPTION
    Aliases such as bool, integer and double are accepted; anything else is
    not a column type.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Get-iSOCTableColumnType.ps1
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

function Get-iSOCTableColumnType {
    <#
    .SYNOPSIS
        Turn a declared column type into the Tables API type it means.

    .DESCRIPTION
        Looks the trimmed, lower-cased type up in the TableTypeMap of
        Get-iSOCTableSchemaSetting. The caller makes an unknown type a
        blocking error rather than guessing.

    .PARAMETER DeclaredType
        The type the schema declares.

    .OUTPUTS
        [string] The Tables API type, or nothing when it is not one.

    .EXAMPLE
        Get-iSOCTableColumnType -DeclaredType 'bool'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [string] $DeclaredType
    )

    if ([string]::IsNullOrWhiteSpace($DeclaredType)) { return $null }
    $map = (Get-iSOCTableSchemaSetting).TableTypeMap
    $key = $DeclaredType.Trim().ToLowerInvariant()
    if ($map.ContainsKey($key)) { return $map[$key] }
    $null
}
