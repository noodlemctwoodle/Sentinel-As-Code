#Requires -Version 7.2

<#
.SYNOPSIS
    Lists the tables that cannot move to the lake, with the reason.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Report/Get-SdlExclusionReport.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.2+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SdlExclusionReport {
    <#
    .SYNOPSIS
        Lists the tables that cannot move to the lake, with the
        reason.

    .DESCRIPTION
        Read off the Migration Report rather than re-queried, so the
        two always agree.

    .PARAMETER MigrationReport
        Rows from Get-SdlMigrationReport.

    .OUTPUTS
        [pscustomobject] Table, Category, Reason and GBPerMonth,
        largest first.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$MigrationReport = @()
    )

    $reason = @{
        'Not supported in Lake'         = 'Sentinel Data Lake does not mirror this table.'
        'UEBA (Analytics-only)'         = 'Required by UEBA. Moving breaks behavioural analytics.'
        'Sentinel feature dependency'   = 'Required by Sentinel features (alerts, watchlists, TI, Fusion).'
        'System table'                  = 'Operational/metadata table; not security telemetry.'
        'Custom log V1 (not supported)' = 'Legacy MMA/HTTP Data Collector ingestion; migrate to DCR.'
        'Auxiliary plan (not modelled)' = 'Already on the low-cost Auxiliary plan; a saving against the Analytics rate would be meaningless, so none is modelled.'
        'Basic plan (convert first)'    = 'Tables on Basic plan cannot move directly to Lake.'
    }
    $excluded = $MigrationReport | Where-Object -FilterScript { $reason.ContainsKey([string]$_.Category) }
    foreach ($row in ($excluded | Sort-Object -Property { [double]$_.GBPerMonth } -Descending)) {
        [pscustomobject]@{
            Table      = $row.Table
            Category   = $row.Category
            Reason     = $reason[[string]$row.Category]
            GBPerMonth = $row.GBPerMonth
        }
    }
}
