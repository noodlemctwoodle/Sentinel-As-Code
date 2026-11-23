#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'daily-rule-incidents': writes daily-rule-incidents.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Daily/Invoke-DailyRuleIncidentsCapture.ps1
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

function Invoke-DailyRuleIncidentsCapture {
    <#
    .SYNOPSIS
        Capture 'daily-rule-incidents': writes daily-rule-incidents.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
let alerts = SecurityAlert
| where TimeGenerated > ago(daily)
| extend ep = parse_json(ExtendedProperties)
| extend AlertRuleId = tolower(coalesce(tostring(parse_json(tostring(ep["Analytic Rule Ids"]))[0]), tostring(ep["Analytic Rule Id"])))
| summarize arg_max(TimeGenerated, AlertName, AlertRuleId, ProductName, ProviderName) by SystemAlertId
| project SystemAlertId, AlertName, AlertRuleId, ProductName, ProviderName;
SecurityIncident
| where TimeGenerated > ago(daily)
| summarize arg_max(TimeGenerated, *) by IncidentNumber
| project IncidentNumber, DaysAgo = toint((now() - TimeGenerated) / 1d), Status, Classification, AlertIds
| mv-expand AlertId = AlertIds to typeof(string)
| join kind=inner alerts on $left.AlertId == $right.SystemAlertId
| extend RuleKey = iff(isempty(AlertRuleId), AlertName, AlertRuleId)
| summarize AlertRuleId = any(AlertRuleId), RuleName = any(AlertName), Product = any(ProductName), Provider = any(ProviderName),
    Incidents = dcount(IncidentNumber),
    Closed = dcountif(IncidentNumber, Status == "Closed"),
    TruePositive = dcountif(IncidentNumber, Classification == "TruePositive"),
    FalsePositive = dcountif(IncidentNumber, Classification == "FalsePositive"),
    BenignPositive = dcountif(IncidentNumber, Classification == "BenignPositive"),
    Undetermined = dcountif(IncidentNumber, Status == "Closed" and (Classification == "Undetermined" or isempty(Classification)))
    by RuleKey, DaysAgo
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'daily-rule-incidents.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'daily-rule-incidents.json' -ErrorRecord $_
    }
}
