#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'diagnostic-settings': writes diagnostic-settings.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/DataCollection/Invoke-DiagnosticSettingsCapture.ps1
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

function Invoke-DiagnosticSettingsCapture {
    <#
    .SYNOPSIS
        Capture 'diagnostic-settings': writes diagnostic-settings.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $workspaceResourceId = $Context.workspaceResourceId

    $ds = Invoke-SentinelRest -Path "$workspaceResourceId/providers/Microsoft.Insights/diagnosticSettings" -ApiVersion '2021-05-01-preview'
    Save-Json -FileName 'diagnostic-settings.json' -Data $ds
}
