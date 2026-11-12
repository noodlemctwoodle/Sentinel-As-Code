#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'syslog-contributors': writes syslog-contributors.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Logs/Invoke-SyslogContributorsCapture.ps1
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

# Log composition: who writes Syslog and SecurityEvent, by host (and
# facility for Syslog), with billed size, over 7 days.
function Invoke-SyslogContributorsCapture {
    <#
    .SYNOPSIS
        Capture 'syslog-contributors': writes syslog-contributors.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
Syslog
| where TimeGenerated > ago(lookback)
| summarize LogCount = count(), SizeMB = round(sum(_BilledSize) / 1024.0 / 1024.0, 1) by Computer, Facility
| order by LogCount desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'syslog-contributors.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'syslog-contributors.json' -ErrorRecord $_
    }
}
