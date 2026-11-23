#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'ama-agents': writes ama-agents.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Agents/Invoke-AmaAgentsCapture.ps1
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

function Invoke-AmaAgentsCapture {
    <#
    .SYNOPSIS
        Capture 'ama-agents': writes ama-agents.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Context', Justification = 'The collector calls every capture as & $capture -Context $context, so each takes the same parameter even when it reads its state from script scope.')]
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # Heartbeat is the canonical signal for Azure Monitor Agent presence.
    $kql = @'
Heartbeat
| where TimeGenerated > ago(lookback)
| summarize
    LastHeartbeat = max(TimeGenerated),
    OS            = any(OSType),
    Version       = any(Version),
    Solutions     = any(Solutions),
    Computer      = any(Computer),
    Resource      = any(_ResourceId)
    by SourceComputerId
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'ama-agents.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'ama-agents.json' -ErrorRecord $_
    }
}
