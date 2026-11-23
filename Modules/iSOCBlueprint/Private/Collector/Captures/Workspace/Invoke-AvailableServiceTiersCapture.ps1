#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'available-service-tiers': writes available-service-tiers.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Workspace/Invoke-AvailableServiceTiersCapture.ps1
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

function Invoke-AvailableServiceTiersCapture {
    <#
    .SYNOPSIS
        Capture 'available-service-tiers': writes available-service-tiers.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $workspaceResourceId = $Context.workspaceResourceId

    $tiers = Invoke-SentinelRest -Path "$workspaceResourceId/availableServiceTiers" -ApiVersion '2020-08-01'
    Save-Json -FileName 'available-service-tiers.json' -Data $tiers
}
