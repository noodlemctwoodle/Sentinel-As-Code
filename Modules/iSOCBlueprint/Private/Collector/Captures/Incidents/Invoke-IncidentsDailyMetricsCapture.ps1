#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'incidents-daily-metrics': writes incidents-daily-metrics.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Incidents/Invoke-IncidentsDailyMetricsCapture.ps1
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

function Invoke-IncidentsDailyMetricsCapture {
    <#
    .SYNOPSIS
        Capture 'incidents-daily-metrics': writes incidents-daily-metrics.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Context', Justification = 'The collector calls every capture as & $capture -Context $context, so each takes the same parameter even when it reads its state from script scope.')]
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # Daily incident-flow metrics over the last 7 days, complementary to
    # the MTTA/MTTR aggregate above.
    $kql = @'
SecurityIncident
| where TimeGenerated > ago(lookback + 1d)
| where CreatedTime between(ago(lookback + 1d) .. ago(1d))
| summarize DailyUnique = dcount(IncidentNumber), DailyCount = count() by bin(CreatedTime, 1d)
| summarize
    AvgDailyUniqueIncidents = round(avg(DailyUnique), 1),
    PeakDailyNewIncidents   = max(DailyCount)
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'incidents-daily-metrics.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'incidents-daily-metrics.json' -ErrorRecord $_
    }
}
