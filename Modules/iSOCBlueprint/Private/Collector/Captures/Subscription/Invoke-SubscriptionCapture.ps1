#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'subscription': writes subscription.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Subscription/Invoke-SubscriptionCapture.ps1
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

function Invoke-SubscriptionCapture {
    <#
    .SYNOPSIS
        Capture 'subscription': writes subscription.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $SubscriptionId = $Context.SubscriptionId

    # Get-AzSubscription -SubscriptionId still tries to enumerate every other
    # tenant the signed-in account can see in some Az.Accounts builds, which
    # produces a stream of "Authentication failed against tenant <guid> ...
    # rerun Connect-AzAccount with -TenantId <guid>" warnings even though
    # we only asked for one specific subscription. Pass -TenantId explicitly
    # (from the active context) and silence warnings for the call so the
    # production transcript stays clean.
    $activeTenantId = (Get-AzContext).Tenant.Id
    $sub = Get-AzSubscription -SubscriptionId $SubscriptionId -TenantId $activeTenantId -WarningAction SilentlyContinue -ErrorAction Stop |
        Select-Object Id, Name, TenantId, State, HomeTenantId
    Save-Json -FileName 'subscription.json' -Data $sub
}
