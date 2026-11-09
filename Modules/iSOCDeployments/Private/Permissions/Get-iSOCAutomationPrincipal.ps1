#Requires -Version 7.6

<#
.SYNOPSIS
    The principal an Automation Account's system-assigned identity runs as.

.DESCRIPTION
    Replaces az automation account show (Deploy/permissions/Set-RunbookPermissions.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Permissions/Get-iSOCAutomationPrincipal.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCAutomationPrincipal {
    <#
    .SYNOPSIS
        Return the principal id of an Automation Account's system-assigned
        managed identity, or throw when it has none.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Name
        The Automation Account.

    .PARAMETER ResourceGroup
        Its resource group.

    .OUTPUTS
        [string] The principal id.

    .EXAMPLE
        Get-iSOCAutomationPrincipal -Context $ctx -Name 'aa-dcr-watchlist-sync' -ResourceGroup 'rg-dcr-watchlist-sync'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $ResourceGroup
    )

    Write-iSOCLog "Resolving managed identity for '$Name'..."
    $account = Invoke-iSOCRestRequest -Method GET -Path "/subscriptions/$($Context.SubscriptionId)/resourceGroups/$ResourceGroup/providers/Microsoft.Automation/automationAccounts/$Name" -ApiVersion (Get-iSOCApiVersion Automation) -Context $Context -AllowNotFound
    $principal = Get-iSOCPropertyValue -InputObject $account -Path 'identity.principalId'
    if (-not $principal) { throw "Could not resolve managed identity. Ensure the Automation Account '$Name' exists in '$ResourceGroup' and has a system-assigned managed identity enabled." }
    Write-iSOCLog "  Principal ID: $principal" -Level Success
    [string]$principal
}
