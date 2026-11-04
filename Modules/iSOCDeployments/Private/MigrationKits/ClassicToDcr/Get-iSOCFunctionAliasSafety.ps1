#Requires -Version 7.2

<#
.SYNOPSIS
    Whether a parser's alias can be followed through chains, and why not.

.DESCRIPTION
    An alias that is empty, not a plain name, too short, reserved, or the
    same as a workspace table or column is not followed.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCFunctionAliasSafety.ps1
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

function Get-iSOCFunctionAliasSafety {
    <#
    .SYNOPSIS
        Whether a parser's alias can be followed through chains, and why not.

    .DESCRIPTION
        Not followed, with the reason:

          - an empty alias
          - one that is not a plain KQL name, so a whole-word match is not
            reliable
          - one shorter than -MinimumLength
          - a reserved name (Get-iSOCReservedAliasName)
          - one equal, in any case, to a table in the workspace: a query
            naming Update far more likely means the Update table
          - one equal, in any case, to a column in the workspace: a bare
            name where a column goes cannot be told from a function call
            without a full KQL parser

        Leaving out the table or column list turns off only that check.

    .PARAMETER Alias
        The parser's functionAlias. It is trimmed first.

    .PARAMETER MinimumLength
        The shortest alias followed. Default 4.

    .PARAMETER WorkspaceTableName
        Every table in the workspace.

    .PARAMETER WorkspaceColumnName
        Every column in the workspace.

    .OUTPUTS
        [pscustomobject] Alias (trimmed), IsSafe and Reason.

    .EXAMPLE
        Get-iSOCFunctionAliasSafety -Alias 'OfficeParser' -WorkspaceTableName $inventory.AllTableNames
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Alias,

        [int] $MinimumLength = 4,

        [AllowNull()]
        [string[]] $WorkspaceTableName,

        [AllowNull()]
        [string[]] $WorkspaceColumnName
    )

    $trimmed = if ($null -eq $Alias) { '' } else { $Alias.Trim() }

    if (-not $trimmed) {
        return [pscustomobject]@{ Alias = ''; IsSafe = $false; Reason = 'alias is empty' }
    }
    if ($trimmed -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        return [pscustomobject]@{
            Alias  = $trimmed
            IsSafe = $false
            Reason = 'not a plain KQL identifier, so a word-boundary match is not reliable'
        }
    }
    if ($trimmed.Length -lt $MinimumLength) {
        return [pscustomobject]@{
            Alias  = $trimmed
            IsSafe = $false
            Reason = "shorter than $MinimumLength characters, too generic to match safely"
        }
    }
    if ((Get-iSOCReservedAliasName) -contains $trimmed.ToLowerInvariant()) {
        return [pscustomobject]@{
            Alias  = $trimmed
            IsSafe = $false
            Reason = 'reserved KQL keyword, scoping function or universal Log Analytics column name'
        }
    }
    foreach ($tableName in @($WorkspaceTableName)) {
        if ($tableName -and [string]::Equals([string]$tableName, $trimmed, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{
                Alias  = $trimmed
                IsSafe = $false
                Reason = "collides with the workspace table '$tableName', so a query naming it far more likely means the table"
            }
        }
    }
    foreach ($columnName in @($WorkspaceColumnName)) {
        if ($columnName -and [string]::Equals([string]$columnName, $trimmed, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{
                Alias  = $trimmed
                IsSafe = $false
                Reason = "collides with the column name '$columnName', and a bare identifier in a column position cannot be told apart from a function call without a full KQL parser"
            }
        }
    }
    [pscustomobject]@{ Alias = $trimmed; IsSafe = $true; Reason = '' }
}
