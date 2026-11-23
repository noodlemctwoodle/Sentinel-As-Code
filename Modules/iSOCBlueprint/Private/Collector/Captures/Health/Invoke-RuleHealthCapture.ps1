#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'rule-health': writes rule-health.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Health/Invoke-RuleHealthCapture.ps1
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

# Rule run health: analytics rules whose scheduled runs failed in the last
# 7 days, from SentinelHealth. Empty is the healthy case.
function Invoke-RuleHealthCapture {
    <#
    .SYNOPSIS
        Capture 'rule-health': writes rule-health.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Context', Justification = 'The collector calls every capture as & $capture -Context $context, so each takes the same parameter even when it reads its state from script scope.')]
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
SentinelHealth
| where TimeGenerated > ago(lookback)
| where SentinelResourceType == "Analytics Rule" and Status != "Success"
| summarize Failures = count(), LastFailure = max(TimeGenerated), Reason = any(Description) by RuleName = SentinelResourceName, Status
| order by Failures desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'rule-health.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'rule-health.json' -ErrorRecord $_
    }
}
