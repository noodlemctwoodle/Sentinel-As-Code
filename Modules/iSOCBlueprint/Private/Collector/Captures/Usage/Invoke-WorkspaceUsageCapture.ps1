#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'workspace-usage': writes workspace-usage.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Usage/Invoke-WorkspaceUsageCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Invoke-WorkspaceUsageCapture {
    <#
    .SYNOPSIS
        Capture 'workspace-usage': writes workspace-usage.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # Compact set of usage scalars sourced from the Usage table. Total +
    # billable 30d, plus 14d peak / billable-peak / billable-average. Returned
    # as a single object so the renderer doesnt need five sequential reads.
    $kql = @'
let Total30d        = Usage | where TimeGenerated > ago(lookback) | summarize TotalGB = round(sum(Quantity)/1024, 3);
let Billable30d     = Usage | where TimeGenerated > ago(lookback) | where IsBillable == true | summarize BillableTotalGB = round(sum(Quantity)/1024, 3);
let Peak14d         = Usage | where TimeGenerated > ago(lookback) | summarize DailyGB = round(sum(Quantity)/1024, 3) by bin(TimeGenerated, 1d) | summarize PeakDailyGB = max(DailyGB);
let BillablePeak14d = Usage | where TimeGenerated > ago(lookback) | where IsBillable == true | summarize DailyGB = round(sum(Quantity)/1024, 3) by bin(TimeGenerated, 1d) | summarize BillablePeakDailyGB = max(DailyGB);
let BillableAvg14d  = Usage | where TimeGenerated > ago(lookback) | where IsBillable == true | summarize DailyGB = round(sum(Quantity)/1024, 3) by bin(TimeGenerated, 1d) | summarize BillableAvgDailyGB = round(avg(DailyGB), 3);
Total30d
| extend BillableTotalGB     = toscalar(Billable30d)
| extend PeakDailyGB         = toscalar(Peak14d)
| extend BillablePeakDailyGB = toscalar(BillablePeak14d)
| extend BillableAvgDailyGB  = toscalar(BillableAvg14d)
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'workspace-usage.json' -Data ($r.Results)
    } catch {
        Skip-Capture -FileName 'workspace-usage.json' -ErrorRecord $_
    }
}
