#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'linked-services': writes linked-services.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Workspace/Invoke-LinkedServicesCapture.ps1
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

function Invoke-LinkedServicesCapture {
    <#
    .SYNOPSIS
        Capture 'linked-services': writes linked-services.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $apiVersions = $Context.apiVersions
    $workspaceResourceId = $Context.workspaceResourceId

    $ls = Invoke-SentinelRest -Path "$workspaceResourceId/linkedServices" -ApiVersion $apiVersions.OperationalInsights
    Save-Json -FileName 'linked-services.json' -Data $ls
}
