#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'top-event-ids': writes top-event-ids.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Logs/Invoke-TopEventIdsCapture.ps1
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

function Invoke-TopEventIdsCapture {
    <#
    .SYNOPSIS
        Capture 'top-event-ids': writes top-event-ids.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Context', Justification = 'The collector calls every capture as & $capture -Context $context, so each takes the same parameter even when it reads its state from script scope.')]
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # Top 10 Windows event IDs by billable size, drives table-noise tuning.
    $kql = @'
find withsource = TableName1 in (Event, SecurityEvent)
    where TimeGenerated > ago(lookback) project _BilledSize, _IsBillable, Computer, _ResourceId, EventID, Activity, RenderedDescription
| where _IsBillable == true
| summarize ["BilledSizeGB"] = round(sum(_BilledSize)/1000/1000/1000, 3), LogCount = count() by TableName = TableName1, EventID, Activity, RenderedDescription
| extend EventDescription = iif(isempty(Activity), RenderedDescription, Activity)
| project-away RenderedDescription, Activity
| project-reorder TableName, EventID, EventDescription, BilledSizeGB, LogCount
| order by BilledSizeGB desc
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'top-event-ids.json' -Data ($r.Results)
    } catch { Skip-Capture -FileName 'top-event-ids.json' -ErrorRecord $_ }
}
