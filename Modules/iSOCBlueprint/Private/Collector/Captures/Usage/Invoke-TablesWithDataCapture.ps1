#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'tables-with-data': writes tables-with-data.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Usage/Invoke-TablesWithDataCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-TablesWithDataCapture {
    <#
    .SYNOPSIS
        Capture 'tables-with-data': writes tables-with-data.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
Usage
| where TimeGenerated > ago(lookback)
| summarize
    BillableLast90d = sumif(Quantity, IsBillable == true) / 1024.0,
    IngestedLast90d = sum(Quantity) / 1024.0,
    BillableLast30d = sumif(Quantity, IsBillable == true and TimeGenerated > ago(lookback)) / 1024.0,
    BillableLast7d  = sumif(Quantity, IsBillable == true and TimeGenerated > ago(recent))  / 1024.0,
    IngestedLast7d  = sumif(Quantity, TimeGenerated > ago(recent)) / 1024.0,
    BillableLast24h = sumif(Quantity, IsBillable == true and TimeGenerated > ago(1d))  / 1024.0,
    FirstSeen       = min(TimeGenerated),
    LastIngested    = max(TimeGenerated),
    DayCount        = dcount(bin(TimeGenerated, 1d))
    by DataType, Solution
'@
    $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
    Save-Json -FileName 'tables-with-data.json' -Data ($result.Results)
}
