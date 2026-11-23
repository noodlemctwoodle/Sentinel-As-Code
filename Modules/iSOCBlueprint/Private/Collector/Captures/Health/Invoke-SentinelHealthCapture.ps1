#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'sentinel-health': writes sentinel-health.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Health/Invoke-SentinelHealthCapture.ps1
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

function Invoke-SentinelHealthCapture {
    <#
    .SYNOPSIS
        Capture 'sentinel-health': writes sentinel-health.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # SentinelHealth surfaces connector / rule / playbook health events.
    # Tolerate missing table on workspaces where Sentinel health diagnostics
    # are not yet enabled.
    $kql = @'
SentinelHealth
| where TimeGenerated > ago(lookback)
| summarize
    Events      = count(),
    LastEvent   = max(TimeGenerated),
    Statuses    = make_set(Status),
    Failures    = countif(Status != "Success"),
    LastFailure = maxif(TimeGenerated, Status != "Success")
    by SentinelResourceName, SentinelResourceKind, SentinelResourceType
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'sentinel-health.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'sentinel-health.json' -ErrorRecord $_
    }
}
