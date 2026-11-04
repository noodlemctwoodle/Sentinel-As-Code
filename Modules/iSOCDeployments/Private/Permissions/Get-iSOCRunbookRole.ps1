#Requires -Version 7.2

<#
.SYNOPSIS
    The roles the DCR watchlist sync runbook needs.

.DESCRIPTION
    Replaces $roles (Deploy/permissions/Set-RunbookPermissions.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Permissions/Get-iSOCRunbookRole.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCRunbookRole {
    <#
    .SYNOPSIS
        Return the runbook's roles, each with its scope and why it is
        needed.

    .DESCRIPTION
        Monitoring Reader on the subscription, to list data collection
        rules and their associations; Microsoft Sentinel Contributor on the
        Sentinel resource group only, to write the watchlist.

    .PARAMETER Context
        The workspace context.

    .OUTPUTS
        [pscustomobject] Name, RoleDefinitionId, Scope and Reason.

    .EXAMPLE
        Get-iSOCRunbookRole -Context $ctx
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context
    )

    $subscription = "/subscriptions/$($Context.SubscriptionId)"
    [pscustomobject]@{ Name = 'Monitoring Reader'; RoleDefinitionId = (Get-iSOCRoleDefinitionId -Name 'Monitoring Reader'); Scope = $subscription; Reason = 'List DCRs and associations via ARM API (subscription-wide)' }
    [pscustomobject]@{ Name = 'Microsoft Sentinel Contributor'; RoleDefinitionId = (Get-iSOCRoleDefinitionId -Name 'Microsoft Sentinel Contributor'); Scope = "$subscription/resourceGroups/$($Context.ResourceGroup)"; Reason = 'Create and update Sentinel watchlists (Sentinel RG only)' }
}
