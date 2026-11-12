#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'azure-diagnostics-categories': writes azure-diagnostics-categories.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Logs/Invoke-AzureDiagnosticsCategoriesCapture.ps1
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

function Invoke-AzureDiagnosticsCategoriesCapture {
    <#
    .SYNOPSIS
        Capture 'azure-diagnostics-categories': writes azure-diagnostics-categories.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # Category-level view of AzureDiagnostics, used to spot resources logging
    # through both the legacy categories and resource-specific tables.
    $kql = @'
AzureDiagnostics
| where TimeGenerated > ago(lookback)
| summarize LogCount = count() by ResourceProvider, Category
| order by LogCount desc
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'azure-diagnostics-categories.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'azure-diagnostics-categories.json' -ErrorRecord $_
    }
}
