#Requires -Version 7.6

<#
.SYNOPSIS
    The Azure context the collector runs under, switched to the subscription asked for.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Setup/Resolve-CollectorAzureContext.ps1
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


function Resolve-CollectorAzureContext {
    <#
    .SYNOPSIS
        Read the active Az context, switching subscription when one is named.

    .PARAMETER SubscriptionId
        The subscription to run in. When omitted the active context's
        subscription is used.

    .OUTPUTS
        One [pscustomobject] with Context, SubscriptionId and TenantId.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory = $false)] [string]$SubscriptionId)

    $ctx = Get-AzContext -ErrorAction Stop
    if ($SubscriptionId) {
        if ($ctx.Subscription.Id -ne $SubscriptionId) {
            Write-Information "Switching context to subscription $SubscriptionId"
            Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
            $ctx = Get-AzContext -ErrorAction Stop
        }
    } else {
        $SubscriptionId = $ctx.Subscription.Id
    }
    return [pscustomobject]@{
        Context        = $ctx
        SubscriptionId = $SubscriptionId
        TenantId       = $ctx.Tenant.Id
    }
}
