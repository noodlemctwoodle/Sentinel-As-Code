#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'rule-effectiveness': writes rule-effectiveness.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Detection/Invoke-RuleEffectivenessCapture.ps1
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

function Invoke-RuleEffectivenessCapture {
    <#
    .SYNOPSIS
        Capture 'rule-effectiveness': writes rule-effectiveness.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # Incident outcomes per detection: each incident is counted once
    # (arg_max per IncidentNumber), the SecurityAlert side is time-bounded,
    # and Sentinel rules are keyed on the Analytic Rule Id carried in the
    # alert's ExtendedProperties (an array on current alerts, a scalar on
    # older ones). Alerts from other products (Defender XDR, Entra ID
    # Protection, Purview) carry no rule id and are keyed on the alert name
    # with Source set to the product, so a page can tell the two apart.
    # Sentinel rules sort first so the row cap never drops them.
    $kql = @'
let w = lookback;
let alerts = SecurityAlert
| where TimeGenerated > ago(w)
| extend ep = parse_json(ExtendedProperties)
| extend AlertRuleId = tolower(coalesce(tostring(parse_json(tostring(ep["Analytic Rule Ids"]))[0]), tostring(ep["Analytic Rule Id"])))
| summarize arg_max(TimeGenerated, AlertName, AlertRuleId, ProductName, ProviderName) by SystemAlertId;
SecurityIncident
| where TimeGenerated > ago(w)
| summarize arg_max(TimeGenerated, *) by IncidentNumber
| project IncidentNumber, Status, Classification, AlertIds
| mv-expand AlertId = AlertIds to typeof(string)
| join kind=inner alerts on $left.AlertId == $right.SystemAlertId
| extend RuleKey = iff(isempty(AlertRuleId), AlertName, AlertRuleId)
| summarize AlertRuleId = any(AlertRuleId), RuleName = any(AlertName),
    Product = any(ProductName), Provider = any(ProviderName),
    Incidents = dcount(IncidentNumber),
    Closed = dcountif(IncidentNumber, Status == "Closed"),
    TruePositive = dcountif(IncidentNumber, Classification == "TruePositive"),
    FalsePositive = dcountif(IncidentNumber, Classification == "FalsePositive"),
    BenignPositive = dcountif(IncidentNumber, Classification == "BenignPositive"),
    Undetermined = dcountif(IncidentNumber, Status == "Closed" and (Classification == "Undetermined" or isempty(Classification)))
    by RuleKey
| extend FPRate = round(100.0 * FalsePositive / iff(Closed == 0, 1, Closed), 1)
| extend Source = iff(isempty(AlertRuleId), coalesce(Product, Provider, "Other"), "Analytics rule")
| extend IsRule = isnotempty(AlertRuleId)
| order by IsRule desc, Incidents desc
| project-away RuleKey, IsRule
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'rule-effectiveness.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'rule-effectiveness.json' -ErrorRecord $_
    }
}
