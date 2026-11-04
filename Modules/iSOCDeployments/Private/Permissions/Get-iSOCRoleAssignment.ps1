#Requires -Version 7.2

<#
.SYNOPSIS
    The role assignments in effect at a scope.

.DESCRIPTION
    Replaces Get-AzRoleAssignment -Scope (Deploy/permissions/Set-PlaybookPermissions.ps1) and az role assignment
    list (Deploy/permissions/Set-RunbookPermissions.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Permissions/Get-iSOCRoleAssignment.ps1
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

function Get-iSOCRoleAssignment {
    <#
    .SYNOPSIS
        List the role assignments at a scope and inherited from above it,
        every page, or every assignment of one principal in the
        subscription.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Scope
        The scope, such as /subscriptions/<id>/resourceGroups/<name>.

    .PARAMETER PrincipalId
        List this principal's assignments in the subscription instead.

    .OUTPUTS
        [pscustomobject] Id, Name, Scope, RoleDefinitionId (the GUID) and
        PrincipalId of each.

    .EXAMPLE
        $existing = @(Get-iSOCRoleAssignment -Context $ctx -Scope $rg)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [string] $Scope,

        [string] $PrincipalId
    )

    $path = if ($PrincipalId) {
        "/subscriptions/$($Context.SubscriptionId)/providers/Microsoft.Authorization/roleAssignments?`$filter=assignedTo('$PrincipalId')"
    }
    else {
        "$($Scope.TrimEnd('/'))/providers/Microsoft.Authorization/roleAssignments?`$filter=atScope()"
    }
    foreach ($assignment in @(Invoke-iSOCRestRequest -Method GET -Path $path -ApiVersion (Get-iSOCApiVersion Authorization) -Context $Context)) {
        if ($null -eq $assignment) { continue }
        $definition = [string](Get-iSOCPropertyValue -InputObject $assignment -Path 'properties.roleDefinitionId')
        [pscustomobject]@{
            Id               = [string](Get-iSOCPropertyValue -InputObject $assignment -Path 'id')
            Name             = [string](Get-iSOCPropertyValue -InputObject $assignment -Path 'name')
            Scope            = [string](Get-iSOCPropertyValue -InputObject $assignment -Path 'properties.scope')
            RoleDefinitionId = ($definition -split '/')[-1]
            PrincipalId      = [string](Get-iSOCPropertyValue -InputObject $assignment -Path 'properties.principalId')
        }
    }
}
