#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'azure-diagnostics-providers': writes azure-diagnostics-providers.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Logs/Invoke-AzureDiagnosticsProvidersCapture.ps1
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

function Invoke-AzureDiagnosticsProvidersCapture {
    <#
    .SYNOPSIS
        Capture 'azure-diagnostics-providers': writes azure-diagnostics-providers.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Context', Justification = 'The collector calls every capture as & $capture -Context $context, so each takes the same parameter even when it reads its state from script scope.')]
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
AzureDiagnostics
| where TimeGenerated > ago(lookback)
| summarize LogCount = count() by ResourceProvider
| order by LogCount desc
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'azure-diagnostics-providers.json' -Data ($r.Results)
    } catch { Skip-Capture -FileName 'azure-diagnostics-providers.json' -ErrorRecord $_ }
}
