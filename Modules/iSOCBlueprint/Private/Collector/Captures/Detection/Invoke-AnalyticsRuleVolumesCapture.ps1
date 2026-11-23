#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'analytics-rule-volumes': writes analytics-rule-volumes.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Detection/Invoke-AnalyticsRuleVolumesCapture.ps1
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

function Invoke-AnalyticsRuleVolumesCapture {
    <#
    .SYNOPSIS
        Capture 'analytics-rule-volumes': writes analytics-rule-volumes.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # Per-rule alert volume from SecurityAlert, every product. Drives the
    # 'top noisy rules' breakout (TOC 4.11.2) and, summed, the alerts in the
    # alert lifecycle. One row per alert (its first record in the window):
    # an alert whose status changes is written again, and counting records
    # would count it once per change. Note: SecurityAlert's severity column
    # is named `AlertSeverity`, not `Severity`, an earlier version of this
    # KQL used `Severity` which the workspace rejected with BadRequest,
    # returning an empty array and leaving section 21 unpopulated.
    $kql = @'
SecurityAlert
| where TimeGenerated > ago(lookback)
| summarize arg_min(TimeGenerated, AlertName, ProductName, AlertSeverity, ProviderName) by SystemAlertId
| summarize Alerts = count(), Alerts7d = countif(TimeGenerated > ago(recent)), ProviderName = take_any(ProviderName)
    by AlertName, ProductName, AlertSeverity
| order by Alerts desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'analytics-rule-volumes.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'analytics-rule-volumes.json' -ErrorRecord $_
    }
}
