#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'threat-intel-tables': writes threat-intel-tables.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/ThreatIntel/Invoke-ThreatIntelTablesCapture.ps1
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

# Data-source hygiene checks. Four independent KQL captures driving section 13.
# Records in each threat intelligence table, current and legacy, with the
# first and last record in 30 days: the table migration status on page 27.
# A table that exists but is empty still returns a row of zeros.
function Invoke-ThreatIntelTablesCapture {
    <#
    .SYNOPSIS
        Capture 'threat-intel-tables': writes threat-intel-tables.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Context', Justification = 'The collector calls every capture as & $capture -Context $context, so each takes the same parameter even when it reads its state from script scope.')]
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
union isfuzzy=true
    (ThreatIntelIndicators       | where TimeGenerated > ago(lookback) | summarize Records30d = count(), Records7d = countif(TimeGenerated > ago(recent)), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated) | extend Table = "ThreatIntelIndicators"),
    (ThreatIntelObjects          | where TimeGenerated > ago(lookback) | summarize Records30d = count(), Records7d = countif(TimeGenerated > ago(recent)), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated) | extend Table = "ThreatIntelObjects"),
    (ThreatIntelligenceIndicator | where TimeGenerated > ago(lookback) | summarize Records30d = count(), Records7d = countif(TimeGenerated > ago(recent)), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated) | extend Table = "ThreatIntelligenceIndicator")
| project Table, Records30d, Records7d, FirstSeen, LastSeen
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'threat-intel-tables.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'threat-intel-tables.json' -ErrorRecord $_
    }
}
