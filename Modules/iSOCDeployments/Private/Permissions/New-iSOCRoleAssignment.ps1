#Requires -Version 7.6

<#
.SYNOPSIS
    Assign a role to a principal at a scope.

.DESCRIPTION
    Replaces New-AzRoleAssignment (Deploy/permissions/Set-PlaybookPermissions.ps1) and az role assignment create
    (Deploy/permissions/Set-RunbookPermissions.ps1). The assignment is named by a GUID made from the scope, the
    principal and the role, so sending it again changes nothing.

.NOTES
    File:         Modules/iSOCDeployments/Private/Permissions/New-iSOCRoleAssignment.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.3.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function New-iSOCRoleAssignment {
    <#
    .SYNOPSIS
        Create a role assignment, and say whether it was created or was
        there already.

    .DESCRIPTION
        PUTs the assignment with the principal type ServicePrincipal, which
        a managed identity is, so Azure does not wait to look the principal
        up. A 409 (the principal has the role at the scope under another
        name) is Exists; anything else throws.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Scope
        Where to assign the role.

    .PARAMETER RoleDefinitionId
        The role's GUID.

    .PARAMETER PrincipalId
        The managed identity's principal (object) id.

    .PARAMETER PrincipalType
        The principal's type: ServicePrincipal (default, which a managed
        identity is), User or Group. Empty leaves it out, and Azure looks
        the principal up.

    .PARAMETER Condition
        An ABAC condition the assignment is limited by (version 2.0).

    .OUTPUTS
        [string] Created or Exists.

    .EXAMPLE
        New-iSOCRoleAssignment -Context $ctx -Scope $rg -RoleDefinitionId $role -PrincipalId $id
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The public command that calls it checks ShouldProcess.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $Scope,

        [Parameter(Mandatory)]
        [string] $RoleDefinitionId,

        [Parameter(Mandatory)]
        [string] $PrincipalId,

        [AllowNull()]
        [AllowEmptyString()]
        [string] $Condition,

        [AllowEmptyString()]
        [ValidateSet('ServicePrincipal', 'User', 'Group', '')]
        [string] $PrincipalType = 'ServicePrincipal'
    )

    $target = $Scope.TrimEnd('/')
    $name = ConvertTo-iSOCNameBasedGuid -Name "$target|$PrincipalId|$RoleDefinitionId"
    $body = @{
        properties = @{
            roleDefinitionId = "/subscriptions/$($Context.SubscriptionId)/providers/Microsoft.Authorization/roleDefinitions/$RoleDefinitionId"
            principalId      = $PrincipalId
        }
    }
    if ($PrincipalType) { $body.properties.principalType = $PrincipalType }
    if ($Condition) {
        $body.properties.condition = $Condition
        $body.properties.conditionVersion = '2.0'
    }
    try {
        Invoke-iSOCRestRequest -Method PUT -Path "$target/providers/Microsoft.Authorization/roleAssignments/$name" -ApiVersion (Get-iSOCApiVersion Authorization) -Body $body -Context $Context | Out-Null
        'Created'
    }
    catch {
        $status = $_.Exception.PSObject.Properties['StatusCode']
        if (($status -and [int]$status.Value -eq 409) -or $_.Exception.Message -match 'RoleAssignmentExists|already exists') { return 'Exists' }
        throw
    }
}
