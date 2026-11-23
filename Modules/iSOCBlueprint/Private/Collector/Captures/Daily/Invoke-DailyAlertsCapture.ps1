#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'daily-alerts': writes daily-alerts.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Daily/Invoke-DailyAlertsCapture.ps1
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

function Invoke-DailyAlertsCapture {
    <#
    .SYNOPSIS
        Capture 'daily-alerts': writes daily-alerts.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Context', Justification = 'The collector calls every capture as & $capture -Context $context, so each takes the same parameter even when it reads its state from script scope.')]
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
SecurityAlert
| where TimeGenerated > ago(daily)
| extend ep = parse_json(ExtendedProperties)
| extend AlertRuleId = tolower(coalesce(tostring(parse_json(tostring(ep["Analytic Rule Ids"]))[0]), tostring(ep["Analytic Rule Id"])))
| summarize arg_min(TimeGenerated, AlertName, ProductName, AlertSeverity, ProviderName, AlertRuleId) by SystemAlertId
| summarize Alerts = count() by DaysAgo = toint((now() - TimeGenerated) / 1d), AlertName, ProductName, AlertSeverity, ProviderName, AlertRuleId
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'daily-alerts.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'daily-alerts.json' -ErrorRecord $_
    }
}
