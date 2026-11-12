#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'threat-intel-by-type': writes threat-intel-by-type.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/ThreatIntel/Invoke-ThreatIntelByTypeCapture.ps1
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

# Indicators by observable type over 30 days: the current ThreatIntelIndicators
# schema first, the retired ThreatIntelligenceIndicator table when the
# current one is absent.
function Invoke-ThreatIntelByTypeCapture {
    <#
    .SYNOPSIS
        Capture 'threat-intel-by-type': writes threat-intel-by-type.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kqlModern = @'
ThreatIntelIndicators
| where TimeGenerated > ago(lookback)
| extend ObservableType = tostring(split(tostring(ObservableKey), ':')[0])
| extend Type = case(
    ObservableType startswith "ipv4" or ObservableType startswith "ipv6", "IP",
    ObservableType == "domain-name", "Domain",
    ObservableType == "url", "URL",
    ObservableType == "file", "FileHash",
    ObservableType == "email-addr" or ObservableType == "email-message", "Email",
    isempty(ObservableType), "Unspecified",
    ObservableType)
| summarize Count = count(), Indicators = dcount(Id) by Type
| order by Count desc
'@
    $kqlLegacy = @'
ThreatIntelligenceIndicator
| where TimeGenerated > ago(lookback)
| extend Type = case(
    isnotempty(NetworkIP) or isnotempty(NetworkSourceIP) or isnotempty(NetworkDestinationIP), "IP",
    isnotempty(DomainName), "Domain",
    isnotempty(Url), "URL",
    isnotempty(FileHashValue), "FileHash",
    isnotempty(EmailSenderAddress), "Email",
    "Other")
| summarize Count = count(), Indicators = dcount(IndicatorId) by Type
| order by Count desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kqlModern) -ErrorAction Stop
        Save-Json -FileName 'threat-intel-by-type.json' -Data ($result.Results)
    } catch {
        try {
            $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kqlLegacy) -ErrorAction Stop
            Save-Json -FileName 'threat-intel-by-type.json' -Data ($result.Results)
        } catch {
            Skip-Capture -FileName 'threat-intel-by-type.json' -ErrorRecord $_
        }
    }
}
