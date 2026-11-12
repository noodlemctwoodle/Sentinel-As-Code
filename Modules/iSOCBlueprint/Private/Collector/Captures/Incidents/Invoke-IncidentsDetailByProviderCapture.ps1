#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'incidents-detail-by-provider': writes incidents-detail-by-provider.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Incidents/Invoke-IncidentsDetailByProviderCapture.ps1
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

function Invoke-IncidentsDetailByProviderCapture {
    <#
    .SYNOPSIS
        Capture 'incidents-detail-by-provider': writes incidents-detail-by-provider.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # SecurityIncident <-> SecurityAlert join with the first-rule indirection
    # producing per-provider, per-product, per-rule incident detail. Aggregate
    # counts only, no incident bodies or alert payloads.
    $kql = @'
SecurityIncident
| where TimeGenerated > ago(lookback)
| summarize arg_max(TimeGenerated, *) by IncidentNumber
| extend FirstRule = tostring(RelatedAnalyticRuleIds[0])
| mv-expand AID = AlertIds
| extend Alert = tostring(AID)
| join kind=inner (
    SecurityAlert
    | where TimeGenerated > ago(lookback)
    | project SystemAlertId, ProviderName, ProductName
) on $left.Alert == $right.SystemAlertId
| summarize AlertCount = count() by ProviderName, ProductName, FirstRule
| order by AlertCount desc
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'incidents-detail-by-provider.json' -Data ($r.Results)
    } catch {
        Skip-Capture -FileName 'incidents-detail-by-provider.json' -ErrorRecord $_
    }
}
