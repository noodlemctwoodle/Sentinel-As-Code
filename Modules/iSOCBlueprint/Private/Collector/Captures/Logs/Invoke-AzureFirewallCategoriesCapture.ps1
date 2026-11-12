#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'azure-firewall-categories': writes azure-firewall-categories.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Logs/Invoke-AzureFirewallCategoriesCapture.ps1
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

# Azure Firewall rows by category, legacy (AzureFirewall*) and
# resource-specific (AZFW*), asked for by name so a small legacy category
# is not lost below the top 100 of azure-diagnostics-categories.
function Invoke-AzureFirewallCategoriesCapture {
    <#
    .SYNOPSIS
        Capture 'azure-firewall-categories': writes azure-firewall-categories.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
AzureDiagnostics
| where TimeGenerated > ago(lookback)
| where Category in ("AzureFirewallApplicationRule", "AzureFirewallNetworkRule", "AzureFirewallDnsProxy",
                     "AZFWApplicationRule", "AZFWNetworkRule", "AZFWDnsQuery", "AZFWNatRule",
                     "AZFWThreatIntel", "AZFWIdpsSignature")
| summarize LogCount = count() by Category
| order by Category asc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'azure-firewall-categories.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'azure-firewall-categories.json' -ErrorRecord $_
    }
}
