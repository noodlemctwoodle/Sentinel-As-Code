#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'cef-in-syslog': writes cef-in-syslog.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Logs/Invoke-CefInSyslogCapture.ps1
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

function Invoke-CefInSyslogCapture {
    <#
    .SYNOPSIS
        Capture 'cef-in-syslog': writes cef-in-syslog.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # CEF records that landed in the Syslog table, usually a Linux syslog
    # forwarder misconfiguration that should be split into a dedicated
    # CommonSecurityLog stream.
    $kql = @'
Syslog
| where TimeGenerated > ago(lookback)
| where SyslogMessage startswith "0|" or SyslogMessage startswith "CEF:"
| extend Parts = split(SyslogMessage, "|")
| extend ProductVendor = strcat(tostring(Parts[1]), "-", tostring(Parts[2]))
| summarize LogCount = count() by Computer, ProductVendor
| order by LogCount desc
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'cef-in-syslog.json' -Data ($r.Results)
    } catch { Skip-Capture -FileName 'cef-in-syslog.json' -ErrorRecord $_ }
}
