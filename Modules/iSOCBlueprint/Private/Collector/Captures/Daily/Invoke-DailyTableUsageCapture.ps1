#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'daily-table-usage': writes daily-table-usage.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Daily/Invoke-DailyTableUsageCapture.ps1
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

function Invoke-DailyTableUsageCapture {
    <#
    .SYNOPSIS
        Capture 'daily-table-usage': writes daily-table-usage.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
Usage
| where TimeGenerated > ago(daily) and IsBillable == true
| summarize GB = round(sum(Quantity) / 1024.0, 4) by DataType, DaysAgo = toint((now() - TimeGenerated) / 1d)
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'daily-table-usage.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'daily-table-usage.json' -ErrorRecord $_
    }
}
