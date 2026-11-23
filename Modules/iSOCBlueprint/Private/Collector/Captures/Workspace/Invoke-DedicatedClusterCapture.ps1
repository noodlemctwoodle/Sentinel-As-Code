#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'dedicated-cluster': writes dedicated-cluster.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Workspace/Invoke-DedicatedClusterCapture.ps1
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

function Invoke-DedicatedClusterCapture {
    <#
    .SYNOPSIS
        Capture 'dedicated-cluster': writes dedicated-cluster.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # 'clusterResourceId' is only present on the workspace.features object when
    # a Log Analytics dedicated cluster is linked. Probe for the property
    # explicitly under StrictMode rather than dotting through it blindly.
    $clusterId = $null
    if ($script:WorkspaceObject -and
        $script:WorkspaceObject.properties -and
        $script:WorkspaceObject.properties.PSObject.Properties.Name -contains 'features' -and
        $script:WorkspaceObject.properties.features -and
        $script:WorkspaceObject.properties.features.PSObject.Properties.Name -contains 'clusterResourceId') {
        $clusterId = $script:WorkspaceObject.properties.features.clusterResourceId
    }
    if ($clusterId) {
        $cluster = Invoke-SentinelRest -Path $clusterId -ApiVersion '2022-10-01'
        Save-Json -FileName 'dedicated-cluster.json' -Data $cluster[0]
    } else {
        Save-Json -FileName 'dedicated-cluster.json' -Data $null
    }
}
