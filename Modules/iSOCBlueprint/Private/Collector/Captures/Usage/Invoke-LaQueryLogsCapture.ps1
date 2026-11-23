#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'la-query-logs': writes la-query-logs.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Usage/Invoke-LaQueryLogsCapture.ps1
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

function Invoke-LaQueryLogsCapture {
    <#
    .SYNOPSIS
        Capture 'la-query-logs': writes la-query-logs.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
LAQueryLogs
| where TimeGenerated > ago(lookback)
| summarize QueryCount = count()
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'la-query-logs.json' -Data ($r.Results)
    } catch { Skip-Capture -FileName 'la-query-logs.json' -ErrorRecord $_ }
}
