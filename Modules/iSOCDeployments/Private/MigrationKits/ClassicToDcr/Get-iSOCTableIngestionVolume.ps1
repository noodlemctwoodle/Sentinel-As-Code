#Requires -Version 7.6

<#
.SYNOPSIS
    The billable volume of each table over 90 days, from the Usage table, when it can be read.

.DESCRIPTION
    Best effort: a query that fails is a warning and no volume, so the run
    goes on.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCTableIngestionVolume.ps1
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

function Get-iSOCTableIngestionVolume {
    <#
    .SYNOPSIS
        The billable volume of each table over 90 days, from the Usage
        table, when it can be read.

    .DESCRIPTION
        Shown beside each table, to tell live tables from abandoned ones; it
        decides nothing, since Usage lags by hours. A query that fails (no
        read access, Usage unavailable, Az.OperationalInsights missing) is a
        warning and no volume.

    .PARAMETER Context
        The workspace context.

    .OUTPUTS
        [hashtable] Table name to GB; nothing when it cannot be read.

    .EXAMPLE
        $volume = Get-iSOCTableIngestionVolume -Context $ctx
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context
    )

    $query = @'
Usage
| where TimeGenerated > ago(90d)
| where IsBillable == true
| summarize GB = round(sum(Quantity) / 1024, 4) by DataType
'@

    $result = @{}
    try {
        $response = Invoke-iSOCAzLogQuery -WorkspaceId $Context.WorkspaceId -Query $query
        $rows = Get-iSOCPropertyValue -InputObject $response -Path 'Results'
        foreach ($row in @($rows)) {
            if ($null -eq $row) { continue }
            $result[[string]$row.DataType] = [double]$row.GB
        }
    } catch {
        Write-iSOCLog "Could not read ingestion volume ($($_.Exception.Message.Split([char]10)[0])). Continuing without it." -Level Warning
        return $null
    }
    $result
}
