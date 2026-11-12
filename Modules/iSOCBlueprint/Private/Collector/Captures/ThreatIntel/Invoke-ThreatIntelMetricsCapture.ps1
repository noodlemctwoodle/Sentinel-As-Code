#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'threat-intel-metrics': writes threat-intel-metrics.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/ThreatIntel/Invoke-ThreatIntelMetricsCapture.ps1
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

# Second TI capture source, the Sentinel TI metrics API. Independent of the
# Az.OperationalInsights module + KQL path above, so the section can still
# render when one source fails. The renderer prefers metrics when both
# present (it carries an indicator-type breakdown the KQL summary doesn't).
function Invoke-ThreatIntelMetricsCapture {
    <#
    .SYNOPSIS
        Capture 'threat-intel-metrics': writes threat-intel-metrics.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $apiVersions = $Context.apiVersions
    $sentinelScope = $Context.sentinelScope

    $metrics = Invoke-SentinelRest -Path "$sentinelScope/threatIntelligence/main/metrics" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'threat-intel-metrics.json' -Data $metrics
}
