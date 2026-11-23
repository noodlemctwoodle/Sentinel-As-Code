#Requires -Version 7.6

<#
.SYNOPSIS
    Runs the per-table Migration Report query.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Report/Get-SdlMigrationReport.ps1
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

function Get-SdlMigrationReport {
    <#
    .SYNOPSIS
        Runs the per-table Migration Report query.

    .DESCRIPTION
        Classifies every billable table, costs it on the Analytics
        tier (ingestion, retention beyond 90 days and lake storage
        after analytics retention) and as lake-only (ingestion,
        processing and lake storage for the whole retention), and sets
        the status and recommendation. Mirrors the workbook's savings
        table.

    .PARAMETER Connection
        The connection object.

    .PARAMETER Settings
        The settings object.

    .PARAMETER Inventory
        The table inventory from Get-SdlTableInventory.

    .OUTPUTS
        The Migration Report rows.
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
let daysInRange = toreal(__DAYS__);
Usage
| where TimeGenerated > ago(__DAYS__d)
| where IsBillable == true
| summarize BillableGB = sum(Quantity) / 1000.0, Solution = take_any(Solution) by DataType
| extend MonthlyGB = (BillableGB / daysInRange) * 30.0
| extend AnalyticsMonthlyCost = MonthlyGB * (priceAnalytics + analyticsRetentionPerGB + analyticsLakeStoragePerGB)
| extend LakeIngestCost = MonthlyGB * priceLakeIngest
       , LakeProcCost   = MonthlyGB * priceLakeProc
       , LakeStorageCost = MonthlyGB * lakeOnlyStoragePerGB
| extend LakeMonthlyCost = LakeIngestCost + LakeProcCost + LakeStorageCost
| extend MonthlySaving = AnalyticsMonthlyCost - LakeMonthlyCost
       , SavingPct = iif(AnalyticsMonthlyCost > 0, round((AnalyticsMonthlyCost - LakeMonthlyCost) / AnalyticsMonthlyCost * 100.0, 1), real(0))
| extend Plan = case(
    DataType in (basicPlanTables), 'Basic',
    DataType in (auxiliaryPlanTables), 'Auxiliary',
    'Analytics')
| extend IngestionMode = case(
    DataType in (classicV1Tables), 'Classic V1',
    DataType in (dcrCustomTables), 'DCR-based',
    DataType endswith '_CL', 'Custom (unknown)',
    'Standard')

'@
    $tail = @'
| extend Recommendation = case(
    Category == 'Not supported in Lake', 'Not supported - keep in Analytics',
    Category == 'UEBA (Analytics-only)', 'UEBA - keep in Analytics',
    Category == 'Sentinel feature dependency', 'Sentinel feature - keep in Analytics',
    Category == 'System table', 'System table - skip',
    Category == 'Custom log V1 (not supported)', 'Classic V1 - migrate ingestion to DCR before any tier decision',
    Category == 'Auxiliary plan (not modelled)', 'Auxiliary plan - already low cost, saving against the Analytics rate not modelled',
    Category == 'Basic plan (convert first)', 'Basic plan - convert to Analytics first',
    Category == 'Custom log DCR-based' and MonthlySaving > 0, 'Eligible - DCR-based custom log',
    Category == 'Custom log DCR-based', 'DCR-based custom log - no saving at current model',
    MonthlySaving > 0, 'Eligible - candidate for Lake-only or hybrid tier',
    'No saving at current pricing')
| extend Status = case(
    Category in ('Not supported in Lake','UEBA (Analytics-only)','Sentinel feature dependency','System table','Auxiliary plan (not modelled)'), 'Excluded',
    Category in ('Custom log V1 (not supported)','Basic plan (convert first)'), 'Action required',
    MonthlySaving > 0, 'Eligible',
    'No saving')
| extend AnalyticsMonthlyCost = iif(Category == 'Auxiliary plan (not modelled)', real(null), AnalyticsMonthlyCost)
| extend LakeMonthlyCost = iif(NotEligibleForLake, real(null), LakeMonthlyCost)
       , MonthlySaving   = iif(NotEligibleForLake, real(null), MonthlySaving)
       , SavingPct       = iif(NotEligibleForLake, real(null), SavingPct)
| order by MonthlySaving desc nulls last
| project Table=DataType, Solution, Category, Plan, IngestionMode, Status, Recommendation,
          GBPerMonth=round(MonthlyGB,2),
          AnalyticsCost___CUR__=round(AnalyticsMonthlyCost,2),
          LakeCost___CUR__=round(LakeMonthlyCost,2),
          MonthlySaving___CUR__=round(MonthlySaving,2),
          SavingPct
'@
    $kql = (Get-SdlPricingLet -Settings $Settings) + (Get-SdlClassificationLet -Inventory $Inventory) + $head + (Get-SdlCategoryKql) + $tail
    Invoke-SdlKqlQuery -Connection $Connection -Query (Expand-KqlTemplate -Template $kql -Settings $Settings)
}
