#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'securityevent-top-hosts': writes securityevent-top-hosts.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Logs/Invoke-SecurityeventTopHostsCapture.ps1
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

function Invoke-SecurityeventTopHostsCapture {
    <#
    .SYNOPSIS
        Capture 'securityevent-top-hosts': writes securityevent-top-hosts.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
SecurityEvent
| where TimeGenerated > ago(lookback)
| summarize LogCount = count(), SizeMB = round(sum(_BilledSize) / 1024.0 / 1024.0, 1) by Computer
| order by LogCount desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'securityevent-top-hosts.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'securityevent-top-hosts.json' -ErrorRecord $_
    }
}
