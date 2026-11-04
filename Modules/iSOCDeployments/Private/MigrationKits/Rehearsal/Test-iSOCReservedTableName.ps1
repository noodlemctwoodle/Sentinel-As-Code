#Requires -Version 7.2

<#
.SYNOPSIS
    Whether a proposed parser alias is one of a list of table names, in any case.

.DESCRIPTION
    A function alias shadows a table of the same name for every query in the
    workspace.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Test-iSOCReservedTableName.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-iSOCReservedTableName {
    <#
    .SYNOPSIS
        Whether a proposed parser alias is one of a list of table names, in
        any case.

    .DESCRIPTION
        A function alias shadows a table of the same name for every query in
        the workspace, so one made on a live workspace would quietly repoint
        every detection reading that table. The comparison ignores case, as
        the KQL resolver does.

    .PARAMETER Name
        The alias.

    .PARAMETER ReservedName
        The names it must not be.

    .OUTPUTS
        [bool]

    .EXAMPLE
        Test-iSOCReservedTableName -Name SigninLogs -ReservedName $tables
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]] $ReservedName
    )

    if (-not $ReservedName) { return $false }
    foreach ($reserved in $ReservedName) {
        if ([string]::IsNullOrWhiteSpace($reserved)) { continue }
        if ([string]::Equals($Name, $reserved, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    $false
}
