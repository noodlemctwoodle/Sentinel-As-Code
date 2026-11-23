#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'threat-intel-health': writes threat-intel-health.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/ThreatIntel/Invoke-ThreatIntelHealthCapture.ps1
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

# Indicator health over 30 days, each indicator at its latest state: how
# many are active, deleted, revoked and still within their validity.
function Invoke-ThreatIntelHealthCapture {
    <#
    .SYNOPSIS
        Capture 'threat-intel-health': writes threat-intel-health.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Context', Justification = 'The collector calls every capture as & $capture -Context $context, so each takes the same parameter even when it reads its state from script scope.')]
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
ThreatIntelIndicators
| where TimeGenerated > ago(lookback)
| summarize arg_max(TimeGenerated, *) by Id
| summarize Total = count(),
    Active = countif(IsActive == true and IsDeleted == false),
    Deleted = countif(IsDeleted == true),
    Revoked = countif(Revoked == true),
    StillValid = countif(isnull(ValidUntil) or ValidUntil > now())
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'threat-intel-health.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'threat-intel-health.json' -ErrorRecord $_
    }
}
