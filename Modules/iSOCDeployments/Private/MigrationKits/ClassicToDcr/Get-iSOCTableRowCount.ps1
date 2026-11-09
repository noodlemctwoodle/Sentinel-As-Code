#Requires -Version 7.6

<#
.SYNOPSIS
    Count the rows a table holds over a lookback, or say it cannot be told.

.DESCRIPTION
    The authoritative sign that a table is in use: rows, not billable GB,
    which lag.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCTableRowCount.ps1
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

function Get-iSOCTableRowCount {
    <#
    .SYNOPSIS
        Count the rows a table holds over a lookback, or say it cannot be
        told.

    .DESCRIPTION
        Whether a table is empty is decided by its rows, queried directly:
        the Usage table lags by hours, so a table with rows can show no
        billable GB long after the rows are there. A query that fails (no
        read access, Az.OperationalInsights missing) is a warning and no
        count, and the caller then treats the table as not empty.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Table
        The table, a name of letters, digits and underscores.

    .PARAMETER LookbackDays
        How far back to count. Default 90.

    .OUTPUTS
        [int] The rows; nothing when they cannot be counted.

    .EXAMPLE
        Get-iSOCTableRowCount -Context $ctx -Table MyApp_CL
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $Table,

        [int] $LookbackDays = 90
    )

    if ([string]::IsNullOrWhiteSpace($Context.WorkspaceId)) { return $null }
    $query = "$Table | where TimeGenerated > ago($($LookbackDays)d) | count"
    try {
        $response = Invoke-iSOCAzLogQuery -WorkspaceId $Context.WorkspaceId -Query $query
        $rows = Get-iSOCPropertyValue -InputObject $response -Path 'Results'
        $first = @($rows)[0]
        if ($first -and $first.PSObject.Properties['Count']) { return [int]$first.Count }
        0
    }
    catch {
        Write-iSOCLog "Could not count rows in $Table ($($_.Exception.Message.Split([char]10)[0])). Emptiness unknown." -Level Warning
        $null
    }
}
