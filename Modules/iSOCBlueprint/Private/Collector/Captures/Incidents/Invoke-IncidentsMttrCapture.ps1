#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'incidents-mttr': writes incidents-mttr.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Incidents/Invoke-IncidentsMttrCapture.ps1
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

function Invoke-IncidentsMttrCapture {
    <#
    .SYNOPSIS
        Capture 'incidents-mttr': writes incidents-mttr.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # Mean time to acknowledge / resolve, last 30 days. Surfaces SOC efficiency
    # without exporting incident detail. FirstModifiedTime can be null when an
    # incident was auto-closed without ever being modified, filter those out
    # of the acknowledge-window average so the result isn't NaN; report the
    # acknowledged subset count separately so the omission is visible.
    $kql = @'
SecurityIncident
| where TimeGenerated > ago(lookback)
| summarize arg_max(TimeGenerated, *) by IncidentNumber
| where Status == "Closed"
| extend AckMins  = iff(isnotnull(FirstModifiedTime), datetime_diff('minute', FirstModifiedTime, CreatedTime), int(null))
| extend RsvMins  = iff(isnotnull(ClosedTime),        datetime_diff('minute', ClosedTime,        CreatedTime), int(null))
| summarize
    ClosedCount       = count(),
    AcknowledgedCount = countif(isnotnull(AckMins)),
    MTTAMinutes       = avgif(AckMins, isnotnull(AckMins)),
    MTTRMinutes       = avgif(RsvMins, isnotnull(RsvMins)),
    ClosedCount7d     = countif(TimeGenerated > ago(recent)),
    MTTAMinutes7d     = avgif(AckMins, isnotnull(AckMins) and TimeGenerated > ago(recent)),
    MTTRMinutes7d     = avgif(RsvMins, isnotnull(RsvMins) and TimeGenerated > ago(recent))
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'incidents-mttr.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'incidents-mttr.json' -ErrorRecord $_
    }
}
