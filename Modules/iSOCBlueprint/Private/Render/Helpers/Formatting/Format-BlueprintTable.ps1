#Requires -Version 7.6

<#
.SYNOPSIS
    Render rows as a Markdown table.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-BlueprintTable.ps1
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

function Format-BlueprintTable {
    <#
    .SYNOPSIS
        Render an array of [pscustomobject] as a Markdown table.

    .DESCRIPTION
        Headers come from -Columns, read as words through Format-ColumnLabel; cells
        still come from the named properties (or hashtable keys). A cell holding a
        number (a .NET numeric value) is written with thousands separators
        (Format-TableCell), except under an identifier-like column; text cells are
        written as given. A pipe in a cell is escaped and a line break becomes a
        space. When there are no items the empty message is returned instead of a
        table. -Items is intentionally non-mandatory because callers commonly pipe
        empty arrays through ForEach-Object: a null reaching this function is the
        empty case, not an error.

    .PARAMETER Items
        The rows. $null or an empty array gives EmptyMessage.

    .PARAMETER Columns
        The property names to show, in order. Each is also the header, after
        Format-ColumnLabel.

    .PARAMETER EmptyMessage
        What to return when there are no rows. Defaults to _None._.

    .OUTPUTS
        [string] of Markdown.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] [object[]]$Items,
        [Parameter(Mandatory = $true)]  [string[]]$Columns,
        [Parameter(Mandatory = $false)] [string]$EmptyMessage = '_None._'
    )
    if (-not $Items -or @($Items).Count -eq 0) { return $EmptyMessage }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('| ' + (@($Columns | ForEach-Object { Format-ColumnLabel $_ }) -join ' | ') + ' |')
    [void]$sb.AppendLine('|' + (($Columns | ForEach-Object { '---' }) -join '|') + '|')
    $identifierColumn = @{}; $gbColumn = @{}
    foreach ($col in $Columns) { $identifierColumn[$col] = Test-IdentifierColumn $col; $gbColumn[$col] = Test-GbColumn $col }
    foreach ($item in $Items) {
        $row = foreach ($col in $Columns) {
            $val = $null
            if ($item -is [hashtable] -and $item.ContainsKey($col)) { $val = $item[$col] }
            elseif ($item.PSObject.Properties.Name -contains $col) { $val = $item.$col }
            $cell = if ($null -eq $val) {
                ''
            } else { (Format-TableCell $val $identifierColumn[$col] $gbColumn[$col]) -replace '\|', '\|' -replace '[\r\n]+', ' ' }
            $cell
        }
        [void]$sb.AppendLine('| ' + ($row -join ' | ') + ' |')
    }
    return $sb.ToString().TrimEnd()
}
