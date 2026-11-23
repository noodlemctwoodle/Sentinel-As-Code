#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'workbooks-saved': writes workbooks-saved.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Sentinel/Invoke-WorkbooksSavedCapture.ps1
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

function Invoke-WorkbooksSavedCapture {
    <#
    .SYNOPSIS
        Capture 'workbooks-saved': writes workbooks-saved.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $SubscriptionId = $Context.SubscriptionId
    $workspaceResourceId = $Context.workspaceResourceId

    $sub = "/subscriptions/$SubscriptionId"
    $all = Invoke-SentinelRest -Path "$sub/providers/Microsoft.Insights/workbooks?category=sentinel" -ApiVersion '2023-06-01'
    $scoped = @($all | Where-Object { $_.properties.sourceId -eq $workspaceResourceId })
    Save-Json -FileName 'workbooks-saved.json' -Data $scoped
}
