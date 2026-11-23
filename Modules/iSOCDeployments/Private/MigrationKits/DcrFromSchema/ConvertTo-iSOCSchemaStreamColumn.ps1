#Requires -Version 7.6

<#
.SYNOPSIS
    Turn the accepted table columns into the data collection rule's stream columns.

.DESCRIPTION
    A stream cannot declare guid, so a guid column is declared string and the
    transform casts it back.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/ConvertTo-iSOCSchemaStreamColumn.ps1
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

function ConvertTo-iSOCSchemaStreamColumn {
    <#
    .SYNOPSIS
        Turn the accepted table columns into the data collection rule's
        stream columns.

    .DESCRIPTION
        One stream column a table column, name and type, the type mapped by
        Get-iSOCDcrColumnType (guid becomes string). The schema has been
        checked, so nothing is dropped.

    .PARAMETER Column
        The accepted columns.

    .OUTPUTS
        [pscustomobject[]] name and type.

    .EXAMPLE
        $streamColumns = @(ConvertTo-iSOCSchemaStreamColumn -Column $columns)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]], [array])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Column
    )

    @($Column | ForEach-Object {
            [pscustomobject]@{
                name = $_.Name
                type = Get-iSOCDcrColumnType -TableColumnType $_.Type
            }
        })
}
