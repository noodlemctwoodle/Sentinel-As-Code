#Requires -Version 7.6

<#
.SYNOPSIS
    Why a proposed fixture alias is unsafe to create, or nothing when it is safe.

.DESCRIPTION
    A live workspace table first, then a known table name, then another
    saved search's alias.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Get-iSOCAliasCollisionReason.ps1
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

function Get-iSOCAliasCollisionReason {
    <#
    .SYNOPSIS
        Why a proposed fixture alias is unsafe to create, or nothing when it
        is safe.

    .DESCRIPTION
        In the order that matters: a table in this workspace (the alias
        would shadow it for every query, the worst case); a known Log
        Analytics or Content Hub table (a solution installed later would be
        shadowed); a saved search the fixture does not own (its query would
        be replaced).

    .PARAMETER Alias
        The alias.

    .PARAMETER WorkspaceTableName
        The workspace's tables.

    .PARAMETER ReservedName
        From Get-iSOCReservedTableName.

    .PARAMETER ForeignAlias
        The aliases of saved searches the fixture does not own.

    .OUTPUTS
        [string] The reason; nothing when it is safe.

    .EXAMPLE
        Get-iSOCAliasCollisionReason -Alias SacDepOneHopParser -WorkspaceTableName $tables -ReservedName $reserved -ForeignAlias $foreign
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Alias,

        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]] $WorkspaceTableName,

        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]] $ReservedName,

        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]] $ForeignAlias
    )

    if (Test-iSOCReservedTableName -Name $Alias -ReservedName $WorkspaceTableName) {
        return "alias '$Alias' matches a table that exists in this workspace; a function alias shadows a table for every query in the workspace"
    }
    if (Test-iSOCReservedTableName -Name $Alias -ReservedName $ReservedName) {
        return "alias '$Alias' matches a known Log Analytics or Content Hub table name"
    }
    if (Test-iSOCReservedTableName -Name $Alias -ReservedName $ForeignAlias) {
        return "alias '$Alias' is already used by a saved search that this fixture does not own"
    }
    $null
}
