#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'daily-health': writes daily-health.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Daily/Invoke-DailyHealthCapture.ps1
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

function Invoke-DailyHealthCapture {
    <#
    .SYNOPSIS
        Capture 'daily-health': writes daily-health.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
SentinelHealth
| where TimeGenerated > ago(daily)
| summarize LogCount = count() by DaysAgo = toint((now() - TimeGenerated) / 1d), OperationName, Status
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'daily-health.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'daily-health.json' -ErrorRecord $_
    }
}
