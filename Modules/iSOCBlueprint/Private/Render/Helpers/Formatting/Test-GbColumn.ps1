#Requires -Version 7.6

<#
.SYNOPSIS
    Test whether a table column holds GB figures.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Test-GbColumn.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-GbColumn {
    <#
    .SYNOPSIS
        Test whether a table column holds GB figures.

    .DESCRIPTION
        A volume column (its header says GB): every cell is a GB figure as the
        dashboard writes it, 56,941.81, whether the value arrived as a number or as
        the text a KQL result gives.

    .PARAMETER Name
        The column name. It is tested after Format-ColumnLabel, for GB as a word.

    .OUTPUTS
        [bool].
    #>
    [CmdletBinding()]
    param([string]$Name)
    return (Format-ColumnLabel $Name) -cmatch '\bGB\b'
}
