#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'subscription-locks': writes subscription-locks.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Subscription/Invoke-SubscriptionLocksCapture.ps1
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

function Invoke-SubscriptionLocksCapture {
    <#
    .SYNOPSIS
        Capture 'subscription-locks': writes subscription-locks.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $ResourceGroup = $Context.ResourceGroup
    $SubscriptionId = $Context.SubscriptionId
    $workspaceResourceId = $Context.workspaceResourceId

    $locks = @()
    $locks += Get-AzResourceLock -Scope "/subscriptions/$SubscriptionId" -ErrorAction SilentlyContinue
    $locks += Get-AzResourceLock -Scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup" -ErrorAction SilentlyContinue
    $locks += Get-AzResourceLock -Scope $workspaceResourceId -ErrorAction SilentlyContinue
    Save-Json -FileName 'subscription-locks.json' -Data $locks
}
