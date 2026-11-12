#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'threat-intel-objects': writes threat-intel-objects.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/ThreatIntel/Invoke-ThreatIntelObjectsCapture.ps1
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

function Invoke-ThreatIntelObjectsCapture {
    <#
    .SYNOPSIS
        Capture 'threat-intel-objects': writes threat-intel-objects.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
ThreatIntelObjects
| where TimeGenerated > ago(lookback)
| summarize Count = count() by StixType
| order by Count desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'threat-intel-objects.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'threat-intel-objects.json' -ErrorRecord $_
    }
}
