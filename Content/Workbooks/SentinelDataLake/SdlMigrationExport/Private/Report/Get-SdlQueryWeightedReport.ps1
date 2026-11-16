#Requires -Version 7.2

<#
.SYNOPSIS
    Runs the query-weighted per-table cost model.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Report/Get-SdlQueryWeightedReport.ps1
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

function Get-SdlQueryWeightedReport {
    <#
    .SYNOPSIS
        Runs the query-weighted per-table cost model.

    .DESCRIPTION
        The workbook's method. Each LAQueryLogs query is matched to
        the tables it reads; its scan is estimated as the table's
        average hourly ingestion x the query's time-range width,
        scaled to a month, and costed at the lake query price. Tables
        nobody queried are kept with zero query cost. Returns nothing,
        with a warning, when LAQueryLogs is not enabled.

    .PARAMETER Connection
        The connection object.

    .PARAMETER Settings
        The settings object.

    .PARAMETER Inventory
        The table inventory from Get-SdlTableInventory.

    .OUTPUTS
        The Query-Weighted rows.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([object])]
    param (
        [Parameter(Mandatory)]
        [object]$Connection,

        [Parameter(Mandatory)]
        [object]$Settings,

        [Parameter(Mandatory)]
        [object]$Inventory
    )

    $head = @'
let queryDays = toreal(__QDAYS__);
let knownTables = toscalar(
    Usage
    | where TimeGenerated > ago(__DAYS__d)
    | summarize make_set(DataType)
);
let avgHourlySizePerTable = Usage
    | where TimeGenerated > ago(__DAYS__d)
    | where IsBillable == true
    | summarize AvgHourlyIngestionGB = sum(Quantity) / 1000.0 / (toreal(__DAYS__) * 24.0) by DataType;
let queryActivity = LAQueryLogs
    | where TimeGenerated > ago(__QDAYS__d)
    | extend HoursDiff = todouble(datetime_diff('minute', QueryTimeRangeEnd, QueryTimeRangeStart)) / 60.0
    | where isnotempty(HoursDiff) and HoursDiff > 0
    | extend QueryOrigin = case(
        RequestClientApp == 'Sentinel-DataCollectionAggregator', 'Automated',
        RequestClientApp == 'Sentinel-Investigation-Queries', 'Automated',
        RequestClientApp has 'sdk' or RequestClientApp has 'PSClient', 'Automated',
        RequestClientApp == 'AzureMonitorLogsConnector', 'Automated',
        RequestClientApp == 'M365D_AdvancedHunting' and isempty(AADEmail), 'Automated',
        'Human')
    | serialize QueryNumber = row_number()
    | mv-expand TableName = knownTables to typeof(string)
    | where QueryText has_cs TableName
    | extend ExtractedTables = extract_all(@'(?:^|\|?\s*)([A-Z][A-Za-z0-9_]+)(?:\s*\||\s*$)', QueryText)
    | where array_index_of(ExtractedTables, TableName) >= 0
    | join kind=leftouter avgHourlySizePerTable on $left.TableName == $right.DataType
    | extend ScanSizeGB = coalesce(AvgHourlyIngestionGB, 0.0) * HoursDiff
    | summarize TotalScannedSizeGB = sum(ScanSizeGB)
        , QueriesInWindow = dcount(QueryNumber)
        , HumanQueries = dcountif(QueryNumber, QueryOrigin == 'Human')
        , AutomatedQueries = dcountif(QueryNumber, QueryOrigin == 'Automated')
        by TableName;
avgHourlySizePerTable
| join kind=leftouter (queryActivity) on $left.DataType == $right.TableName
| extend TotalScannedSizeGB = coalesce(TotalScannedSizeGB, 0.0)
       , QueriesInWindow = coalesce(QueriesInWindow, long(0))
       , HumanQueries = coalesce(HumanQueries, long(0))
       , AutomatedQueries = coalesce(AutomatedQueries, long(0))
| extend MonthlyGB = AvgHourlyIngestionGB * 24.0 * 30.0
       , MonthlyScanGB = TotalScannedSizeGB / queryDays * 30.0
| extend AnalyticsMonthlyCost = MonthlyGB * (priceAnalytics + analyticsRetentionPerGB + analyticsLakeStoragePerGB)
| extend LakeIngestCost = MonthlyGB * priceLakeIngest
       , LakeProcCost = MonthlyGB * priceLakeProc
       , LakeStorageCost = MonthlyGB * lakeOnlyStoragePerGB
       , LakeQueryCost = MonthlyScanGB * priceLakeQuery
| extend LakeTotalCost = LakeIngestCost + LakeProcCost + LakeStorageCost + LakeQueryCost
| extend MonthlySaving = AnalyticsMonthlyCost - LakeTotalCost
'@
    $tail = @'
| extend Recommendation = case(
    Category == 'Not supported in Lake', 'Not supported - keep in Analytics',
    Category == 'UEBA (Analytics-only)', 'UEBA - keep in Analytics',
    Category == 'Sentinel feature dependency', 'Sentinel feature - keep in Analytics',
    Category == 'System table', 'System table - skip',
    Category == 'Custom log V1 (not supported)', 'Classic V1 - migrate ingestion to DCR first',
    Category == 'Auxiliary plan (not modelled)', 'Auxiliary plan - not modelled',
    Category == 'Basic plan (convert first)', 'Basic plan - convert to Analytics first',
    AnalyticsMonthlyCost > LakeTotalCost * 1.5, 'Strong query-weighted saving - see Migration Report for tier strategy',
    AnalyticsMonthlyCost > LakeTotalCost, 'Marginal - hybrid tier only worth it for compliance/forensic value',
    'Heavily queried - Lake query cost would exceed Analytics. Keep in Analytics or summarise via a Summary rule.')
| extend LakeTotalCost = iif(NotEligibleForLake, real(null), LakeTotalCost)
       , MonthlySaving = iif(NotEligibleForLake, real(null), MonthlySaving)
       , AnalyticsMonthlyCost = iif(Category == 'Auxiliary plan (not modelled)', real(null), AnalyticsMonthlyCost)
| order by MonthlySaving desc nulls last
| project Table=DataType, Category,
          GBPerMonth=round(MonthlyGB, 2),
          AvgGBPerHour=round(AvgHourlyIngestionGB, 4),
          QueriesInWindow, HumanQueries, AutomatedQueries,
          MonthlyScanGB=round(MonthlyScanGB, 2),
          AnalyticsCost___CUR__=round(AnalyticsMonthlyCost, 2),
          LakeTotalCost___CUR__=round(LakeTotalCost, 2),
          MonthlySaving___CUR__=round(MonthlySaving, 2),
          Recommendation
'@
    try {
        $kql = (Get-SdlPricingLet -Settings $Settings) + (Get-SdlClassificationLet -Inventory $Inventory) + $head + "`n" + (Get-SdlCategoryKql) + $tail
        Invoke-SdlKqlQuery -Connection $Connection -Query (Expand-KqlTemplate -Template $kql -Settings $Settings)
    } catch {
        Write-Warning -Message "Query-Weighted skipped (likely LAQueryLogs not enabled): $($_.Exception.Message)"
    }
}
