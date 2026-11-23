#Requires -Version 7.6

<#
.SYNOPSIS
    Runs the cost model for the 21 core Defender XDR tables in the
    workspace.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Report/Get-SdlXdrCostReport.ps1
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

function Get-SdlXdrCostReport {
    <#
    .SYNOPSIS
        Runs the cost model for the 21 core Defender XDR tables in the
        workspace.

    .DESCRIPTION
        Measures volume two ways as a cross-check: billed GB from
        Usage and the sum of each record's _BilledSize (the billed
        size in bytes, GB = 10^9 bytes). Usage is costed when it has a
        figure. Only tables present in the workspace can be measured;
        XDR data that stays in Defender is invisible to this query.
        Skipped when XdrLookbackDays is 0.

    .PARAMETER Connection
        The connection object.

    .PARAMETER Settings
        The settings object.

    .OUTPUTS
        The XDR Cost Model rows.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([object])]
    param (
        [Parameter(Mandatory)]
        [object]$Connection,

        [Parameter(Mandatory)]
        [object]$Settings
    )

    if ($Settings.XdrLookbackDays -le 0) {
        return
    }
    $xdrTables = @(
        'DeviceProcessEvents', 'DeviceNetworkEvents', 'DeviceFileEvents', 'DeviceRegistryEvents',
        'DeviceLogonEvents', 'DeviceImageLoadEvents', 'DeviceEvents', 'DeviceInfo', 'DeviceNetworkInfo',
        'EmailEvents', 'EmailUrlInfo', 'EmailAttachmentInfo', 'EmailPostDeliveryEvents', 'UrlClickEvents',
        'IdentityLogonEvents', 'IdentityQueryEvents', 'IdentityDirectoryEvents', 'IdentityInfo',
        'CloudAppEvents', 'AlertInfo', 'AlertEvidence'
    )
    $names = ConvertTo-KqlList -Item $xdrTables
    $union = foreach ($table in $xdrTables) {
        "    ($table | where TimeGenerated > ago(lookbackDays * 1d) | where _IsBillable == true | summarize RowCount=count(), RecordBytes=sum(_BilledSize) | extend TableName='$table')"
    }
    $head = @"
let lookbackDays = toreal($($Settings.XdrLookbackDays));
let xdrTables = dynamic([$names]);
let billed = Usage
    | where TimeGenerated > ago(__XDAYS__d)
    | where IsBillable == true
    | where DataType in (xdrTables)
    | summarize BilledGB = sum(Quantity) / 1000.0 by TableName = DataType;
let observed = union isfuzzy=true
$($union -join ",`n");

"@
    $body = @'
observed
| where RowCount > 0
| join kind=leftouter (billed) on TableName
| extend BilledGB = coalesce(BilledGB, 0.0)
| extend RecordGBPerMonth = RecordBytes / 1000000000.0 / lookbackDays * 30.0
       , BilledGBPerMonth = BilledGB / lookbackDays * 30.0
| extend MonthlyGB = iif(BilledGB > 0, BilledGBPerMonth, RecordGBPerMonth)
       , Basis = iif(BilledGB > 0, 'Usage', '_BilledSize')
| extend AnalyticsMonthlyCost = MonthlyGB * (priceAnalytics + analyticsRetentionPerGB + analyticsLakeStoragePerGB)
| extend LakeMonthlyCost = MonthlyGB * (priceLakeIngest + priceLakeProc + lakeOnlyStoragePerGB)
| extend MonthlySaving = AnalyticsMonthlyCost - LakeMonthlyCost
       , SavingPct = iif(AnalyticsMonthlyCost > 0, round((AnalyticsMonthlyCost - LakeMonthlyCost) / AnalyticsMonthlyCost * 100.0, 1), real(0))
| extend Note = case(
    TableName in ('AlertInfo','AlertEvidence'), 'Detection-critical - keep in Analytics',
    TableName in ('IdentityInfo','DeviceInfo'), 'Reference table - usually not worth moving',
    '')
| order by MonthlyGB desc
| project Table=TableName, Rows=RowCount,
          BilledGBPerMonth=round(BilledGBPerMonth, 2),
          RecordGBPerMonth=round(RecordGBPerMonth, 2),
          GBPerMonth=round(MonthlyGB, 2), Basis,
          AnalyticsMonthlyCost___CUR__=round(AnalyticsMonthlyCost, 2),
          LakeMonthlyCost___CUR__=round(LakeMonthlyCost, 2),
          MonthlySaving___CUR__=round(MonthlySaving, 2),
          SavingPct, Note
'@
    try {
        $kql = (Get-SdlPricingLet -Settings $Settings) + $head + $body
        Invoke-SdlKqlQuery -Connection $Connection -Query (Expand-KqlTemplate -Template $kql -Settings $Settings)
    } catch {
        Write-Warning -Message "XDR cost model skipped: $($_.Exception.Message)"
    }
}
