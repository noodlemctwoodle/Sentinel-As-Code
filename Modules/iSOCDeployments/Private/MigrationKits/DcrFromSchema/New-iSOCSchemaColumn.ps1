#Requires -Version 7.2

<#
.SYNOPSIS
    Build a schema column with every property the rest of the command reads.

.DESCRIPTION
    Under strict mode a missing property is an error, so every column has one
    shape.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/New-iSOCSchemaColumn.ps1
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

function New-iSOCSchemaColumn {
    <#
    .SYNOPSIS
        Build a schema column with every property the rest of the command
        reads.

    .DESCRIPTION
        Name, Type, DeclaredType (the Type unless given), Description,
        DisplayName, DataTypeHint and an empty Issues list, so a column
        added by a repair has the same shape as one read from the file.

    .PARAMETER Name
        The column name.

    .PARAMETER Type
        The Tables API type.

    .PARAMETER DeclaredType
        The type as declared.

    .PARAMETER Description
        The column's description.

    .PARAMETER DisplayName
        The column's display name.

    .PARAMETER DataTypeHint
        The column's dataTypeHint.

    .OUTPUTS
        [pscustomobject]

    .EXAMPLE
        New-iSOCSchemaColumn -Name 'TimeGenerated' -Type 'dateTime'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; nothing outside the call changes.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Type,

        [AllowEmptyString()]
        [string] $DeclaredType = '',

        [AllowEmptyString()]
        [string] $Description = '',

        [AllowEmptyString()]
        [string] $DisplayName = '',

        [AllowEmptyString()]
        [string] $DataTypeHint = ''
    )

    [pscustomobject]@{
        Name         = $Name
        Type         = $Type
        DeclaredType = if ($DeclaredType) { $DeclaredType } else { $Type }
        Description  = $Description
        DisplayName  = $DisplayName
        DataTypeHint = $DataTypeHint
        Issues       = @()
    }
}
