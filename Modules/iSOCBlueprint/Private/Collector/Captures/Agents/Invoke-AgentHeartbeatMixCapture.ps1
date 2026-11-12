#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'agent-heartbeat-mix': writes agent-heartbeat-mix.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Agents/Invoke-AgentHeartbeatMixCapture.ps1
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

# Agents by OS, agent category (Azure Monitor Agent, Direct Agent for MMA,
# SCOM) and version over 7 days: the heartbeat mix behind the AMA migration.
function Invoke-AgentHeartbeatMixCapture {
    <#
    .SYNOPSIS
        Capture 'agent-heartbeat-mix': writes agent-heartbeat-mix.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
Heartbeat
| where TimeGenerated > ago(lookback)
| extend OSVersion = strcat(OSName, " ", OSMajorVersion, ".", OSMinorVersion)
| summarize Computers = dcount(Computer), LastSeen = max(TimeGenerated) by OSType, Category, Version, OSVersion
| order by Computers desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'agent-heartbeat-mix.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'agent-heartbeat-mix.json' -ErrorRecord $_
    }
}
