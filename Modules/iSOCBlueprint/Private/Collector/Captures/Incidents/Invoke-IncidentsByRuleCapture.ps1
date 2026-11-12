#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'incidents-by-rule': writes incidents-by-rule.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Incidents/Invoke-IncidentsByRuleCapture.ps1
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

function Invoke-IncidentsByRuleCapture {
    <#
    .SYNOPSIS
        Capture 'incidents-by-rule': writes incidents-by-rule.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
SecurityIncident
| where TimeGenerated > ago(lookback)
| summarize arg_max(TimeGenerated, *) by IncidentNumber
| mv-expand AlertIds
| summarize Incidents = dcount(IncidentNumber) by Title
| order by Incidents desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'incidents-by-rule.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'incidents-by-rule.json' -ErrorRecord $_
    }
}
