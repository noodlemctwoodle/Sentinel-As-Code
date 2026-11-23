#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'daily-incidents': writes daily-incidents.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Daily/Invoke-DailyIncidentsCapture.ps1
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

function Invoke-DailyIncidentsCapture {
    <#
    .SYNOPSIS
        Capture 'daily-incidents': writes daily-incidents.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Context', Justification = 'The collector calls every capture as & $capture -Context $context, so each takes the same parameter even when it reads its state from script scope.')]
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
let inc = SecurityIncident
| where TimeGenerated > ago(daily)
| summarize arg_max(TimeGenerated, *) by IncidentNumber;
let closing = SecurityIncident
| where TimeGenerated > ago(daily) and Status == "Closed"
| summarize arg_min(TimeGenerated, ModifiedBy) by IncidentNumber
| project IncidentNumber, ClosingBy = ModifiedBy;
inc
| join kind=leftouter closing on IncidentNumber
| extend IsClosed = Status == "Closed"
| extend ClosedBy = iff(not(IsClosed), "", case(ClosingBy contains "Automation", "AutomationRule",
                   ClosingBy has_any ("Microsoft 365 Defender", "Microsoft Defender XDR", "Microsoft XDR"), "DefenderXdr",
                   ClosingBy contains "@", "Analyst",
                   "Other")),
    Class = iff(IsClosed, iff(isempty(Classification), "Unclassified", Classification), ""),
    AckMins = iff(IsClosed and isnotnull(FirstModifiedTime), datetime_diff('minute', FirstModifiedTime, CreatedTime), long(null)),
    RsvMins = iff(IsClosed and isnotnull(ClosedTime), datetime_diff('minute', ClosedTime, CreatedTime), long(null))
| summarize Incidents = count(), AckCount = countif(isnotnull(AckMins)), AckSum = sum(AckMins), RsvCount = countif(isnotnull(RsvMins)), RsvSum = sum(RsvMins)
    by DaysAgo = toint((now() - TimeGenerated) / 1d), Severity, Status = iff(IsClosed, "Closed", "Open"), Class, ClosedBy
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'daily-incidents.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'daily-incidents.json' -ErrorRecord $_
    }
}
