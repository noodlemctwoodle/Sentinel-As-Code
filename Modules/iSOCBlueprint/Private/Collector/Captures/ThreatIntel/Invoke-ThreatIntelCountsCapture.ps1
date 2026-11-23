#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'threat-intel-counts': writes threat-intel-counts.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/ThreatIntel/Invoke-ThreatIntelCountsCapture.ps1
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

function Invoke-ThreatIntelCountsCapture {
    <#
    .SYNOPSIS
        Capture 'threat-intel-counts': writes threat-intel-counts.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Context', Justification = 'The collector calls every capture as & $capture -Context $context, so each takes the same parameter even when it reads its state from script scope.')]
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # KQL on the indicator tables, counts only, never indicator detail. Every
    # column but TimeGenerated is read through column_ifexists: the union is
    # fuzzy, so the columns are only those of the tables present, and a bare
    # name neither has (Source) is a semantic error that left the file empty.
    $kql = @'
union isfuzzy=true ThreatIntelligenceIndicator, ThreatIntelIndicators
| where TimeGenerated > ago(lookback)
| extend IndicatorKey = coalesce(tostring(column_ifexists("Id", "")), tostring(column_ifexists("IndicatorId", "")))
| summarize Count = count(), Indicators = dcount(IndicatorKey), Last = max(TimeGenerated) by SourceSystem = coalesce(tostring(column_ifexists("SourceSystem", "")), tostring(column_ifexists("Source", "")))
| order by Count desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'threat-intel-counts.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'threat-intel-counts.json' -ErrorRecord $_
    }
}
