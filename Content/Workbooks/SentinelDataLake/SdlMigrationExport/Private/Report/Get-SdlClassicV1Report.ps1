#Requires -Version 7.6

<#
.SYNOPSIS
    Lists the Classic V1 custom tables with their monthly volume.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Report/Get-SdlClassicV1Report.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SdlClassicV1Report {
    <#
    .SYNOPSIS
        Lists the Classic V1 custom tables with their monthly volume.

    .DESCRIPTION
        Classic (MMA / HTTP Data Collector) custom tables are not
        mirrored to the lake and must move to DCR-based ingestion
        first.

    .PARAMETER Connection
        The connection object.

    .PARAMETER Settings
        The settings object.

    .PARAMETER Inventory
        The table inventory from Get-SdlTableInventory.

    .OUTPUTS
        [pscustomobject] One row per Classic V1 table.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [object]$Connection,

        [Parameter(Mandatory)]
        [object]$Settings,

        [Parameter(Mandatory)]
        [object]$Inventory
    )

    if (-not $Inventory.ClassicV1.Count) {
        return
    }
    $list = ConvertTo-KqlList -Item $Inventory.ClassicV1
    $body = @'
Usage
| where TimeGenerated > ago(__DAYS__d)
| where IsBillable == true
| where DataType in (classicV1Tables)
| summarize GBPerMonth = (sum(Quantity) / 1000.0 / toreal(__DAYS__)) * 30.0 by DataType
| project Table=DataType, GBPerMonth=round(GBPerMonth, 2)
'@
    $kql = "let classicV1Tables = dynamic([$list]);`n" + $body
    $volume = @{}
    foreach ($row in @(Invoke-SdlKqlQuery -Connection $Connection -Query (Expand-KqlTemplate -Template $kql -Settings $Settings))) {
        $volume[$row.Table] = $row.GBPerMonth
    }
    foreach ($table in $Inventory.ClassicV1) {
        [pscustomobject]@{
            Table           = $table
            DeprecationType = 'Classic V1 _CL'
            Replacement     = 'Migrate to DCR-based ingestion via Logs Ingestion API'
            Urgency         = 'Required for Lake - legacy HTTP Data Collector API and MMA agent deprecated'
            GBPerMonth      = if ($volume.ContainsKey($table)) { $volume[$table] } else { 0 }
            DocsUrl         = 'https://learn.microsoft.com/azure/azure-monitor/logs/custom-logs-migrate'
        }
    }
}
