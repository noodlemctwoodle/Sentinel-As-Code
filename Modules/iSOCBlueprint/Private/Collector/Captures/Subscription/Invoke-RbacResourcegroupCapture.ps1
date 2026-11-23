#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'rbac-resourcegroup': writes rbac-resourcegroup.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Subscription/Invoke-RbacResourcegroupCapture.ps1
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

function Invoke-RbacResourcegroupCapture {
    <#
    .SYNOPSIS
        Capture 'rbac-resourcegroup': writes rbac-resourcegroup.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $ResourceGroup = $Context.ResourceGroup
    $SubscriptionId = $Context.SubscriptionId

    $rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"
    $assigns = Get-AzRoleAssignment -Scope $rgScope -ErrorAction SilentlyContinue
    Save-Json -FileName 'rbac-resourcegroup.json' -Data $assigns
}
