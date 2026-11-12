#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'workspace-usage-daily': writes workspace-usage-daily.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Daily/Invoke-WorkspaceUsageDailyCapture.ps1
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

function Invoke-WorkspaceUsageDailyCapture {
    <#
    .SYNOPSIS
        Capture 'workspace-usage-daily': writes workspace-usage-daily.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
Usage
| where TimeGenerated > ago(lookback)
| summarize BillableGB = round(sumif(Quantity, IsBillable == true) / 1024.0, 3),
            FreeGB     = round(sumif(Quantity, IsBillable == false) / 1024.0, 3)
    by Day = bin(TimeGenerated, 1d)
| order by Day asc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'workspace-usage-daily.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'workspace-usage-daily.json' -ErrorRecord $_
    }
}
