#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'incident-title-stats': writes incident-title-stats.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Incidents/Invoke-IncidentTitleStatsCapture.ps1
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

# Incident titles over 30 days with volume, closure speed and verdicts:
# the input to the automation-opportunities table (frequent, fast-closing
# or mostly-false-positive titles). Aggregates only, no per-incident rows.
function Invoke-IncidentTitleStatsCapture {
    <#
    .SYNOPSIS
        Capture 'incident-title-stats': writes incident-title-stats.json.

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
| extend MinsToClose = iff(Status == "Closed", datetime_diff("minute", ClosedTime, CreatedTime), int(null))
| summarize Total = count(), Closed = countif(Status == "Closed"), Severity = any(Severity),
    AvgMinsToClose = round(avg(MinsToClose), 1), ClosedWithinHour = countif(Status == "Closed" and MinsToClose <= 60),
    FP = countif(Classification == "FalsePositive"), TP = countif(Classification == "TruePositive"), BP = countif(Classification == "BenignPositive")
    by Title
| where Total >= 5
| order by Total desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'incident-title-stats.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'incident-title-stats.json' -ErrorRecord $_
    }
}
