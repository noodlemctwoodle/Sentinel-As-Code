#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'security-event-duplicates': writes security-event-duplicates.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Logs/Invoke-SecurityEventDuplicatesCapture.ps1
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

function Invoke-SecurityEventDuplicatesCapture {
    <#
    .SYNOPSIS
        Capture 'security-event-duplicates': writes security-event-duplicates.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # Duplicate SecurityEvent records over a 1-hour window, typically an
    # agent dual-collection misconfiguration (MMA + AMA reporting the same
    # events into the workspace).
    $kql = @'
let SecurityEvents = SecurityEvent
| where TimeGenerated > ago(1h)
| where isnotempty(EventRecordId);
let DuplicateEvents = SecurityEvents
| summarize count() by Computer, EventID, EventRecordId
| where count_ > 1;
let SumPerComputer = DuplicateEvents | summarize LogCount = sum(count_) by Computer;
DuplicateEvents
| summarize DuplicateEventIds = make_set(EventID), DuplicateRecords = count() by Computer
| order by DuplicateRecords desc
| lookup SumPerComputer on Computer
| project Computer, DuplicateRecords, LogCount, DuplicateEventIds
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'security-event-duplicates.json' -Data ($r.Results)
    } catch { Skip-Capture -FileName 'security-event-duplicates.json' -ErrorRecord $_ }
}
