#Requires -Version 7.2

<#
.SYNOPSIS
    The principal a resource's managed identity runs as.

.DESCRIPTION
    Replaces the identity checks in Deploy/permissions/Set-PlaybookPermissions.ps1.

.NOTES
    File:         Modules/iSOCDeployments/Private/Permissions/Get-iSOCManagedIdentityPrincipal.ps1
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

function Get-iSOCManagedIdentityPrincipal {
    <#
    .SYNOPSIS
        Return a resource's identity type and the principal id its role
        assignments go to.

    .DESCRIPTION
        A system-assigned identity's principal, else the first
        user-assigned identity's. A resource without an identity, or one
        whose principal is not given, has no PrincipalId.

    .PARAMETER Resource
        The resource as ARM returns it, with its identity.

    .OUTPUTS
        [pscustomobject] Type and PrincipalId.

    .EXAMPLE
        Get-iSOCManagedIdentityPrincipal -Resource $app
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Resource
    )

    $type = [string](Get-iSOCPropertyValue -InputObject $Resource -Path 'identity.type')
    $principal = $null
    if ($type -match 'SystemAssigned') { $principal = Get-iSOCPropertyValue -InputObject $Resource -Path 'identity.principalId' }
    elseif ($type -match 'UserAssigned') {
        $first = @(Get-iSOCPropertyEntry -InputObject (Get-iSOCPropertyValue -InputObject $Resource -Path 'identity.userAssignedIdentities')) | Select-Object -First 1
        if ($first) { $principal = Get-iSOCPropertyValue -InputObject $first.Value -Path 'principalId' }
    }
    [pscustomobject]@{ Type = $type; PrincipalId = $(if ($principal) { [string]$principal } else { $null }) }
}
