#Requires -Version 7.6

<#
.SYNOPSIS
    The resource id a role is assigned at.

.DESCRIPTION
    Copied from Resolve-Scope (Deploy/permissions/Set-PlaybookPermissions.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Permissions/Resolve-iSOCRoleScope.ps1
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

function Resolve-iSOCRoleScope {
    <#
    .SYNOPSIS
        Return the scope for rg, workspace or keyvault, or nothing for
        keyvault when no vault is named.

    .PARAMETER ScopeType
        rg, workspace or keyvault; anything else is the resource group.

    .PARAMETER SubscriptionId
        The subscription.

    .PARAMETER ResourceGroup
        The Sentinel resource group, which holds the workspace and the
        vault.

    .PARAMETER WorkspaceName
        The workspace.

    .PARAMETER KeyVaultName
        The vault, when playbooks read one.

    .OUTPUTS
        [string] The scope.

    .EXAMPLE
        Resolve-iSOCRoleScope -ScopeType rg -SubscriptionId $sub -ResourceGroup $rg
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $ScopeType,

        [Parameter(Mandatory)]
        [string] $SubscriptionId,

        [Parameter(Mandatory)]
        [string] $ResourceGroup,

        [string] $WorkspaceName,

        [string] $KeyVaultName
    )

    $group = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"
    switch ($ScopeType) {
        'workspace' { return "$group/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName" }
        'keyvault' {
            if (-not $KeyVaultName) { return $null }
            return "$group/providers/Microsoft.KeyVault/vaults/$KeyVaultName"
        }
        default { return $group }
    }
}
