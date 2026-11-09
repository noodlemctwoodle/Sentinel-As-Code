#Requires -Version 7.6

<#
.SYNOPSIS
    Check the sending service principal holds Monitoring Metrics Publisher on the rule, granting it when asked.

.DESCRIPTION
    Without the role the posts are refused, so its absence is a warning with
    the command to grant it.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Confirm-iSOCIngestionRole.ps1
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

function Confirm-iSOCIngestionRole {
    <#
    .SYNOPSIS
        Check the sending service principal holds Monitoring Metrics
        Publisher on the rule, granting it when asked.

    .DESCRIPTION
        The client id must be a service principal's application id in the
        tenant, or this throws. When it holds the role on the rule or above,
        it is said so. Otherwise, with -Grant, the role is assigned at the
        rule, asking ShouldProcess (data-plane RBAC can take minutes, so the
        first posts may be refused); without it, a warning gives the command
        to grant it.

    .PARAMETER Context
        The workspace context.

    .PARAMETER ClientId
        The service principal's application id.

    .PARAMETER DcrId
        The rule's resource id.

    .PARAMETER DcrName
        The rule's name, for the messages.

    .PARAMETER Grant
        Assign the role when it is missing.

    .OUTPUTS
        [string] Held, Granted, Missing or Skipped.

    .EXAMPLE
        Confirm-iSOCIngestionRole -Context $ctx -ClientId $cid -DcrId $dcrId -DcrName dcr-myapp
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $ClientId,

        [Parameter(Mandatory)]
        [string] $DcrId,

        [Parameter(Mandatory)]
        [string] $DcrName,

        [switch] $Grant
    )

    $principal = Resolve-iSOCPrincipal -Context $Context -Identity $ClientId
    if (-not $principal.IsApplication) { throw "No service principal found for client ID $ClientId in this tenant." }

    $roleName = 'Monitoring Metrics Publisher'
    $roleId = Get-iSOCRoleDefinitionId -Name $roleName
    $assignments = @(Get-iSOCRoleAssignment -Context $Context -PrincipalId $principal.ObjectId)
    $existing = @(Find-iSOCRoleAssignment -Assignment $assignments -PrincipalId $principal.ObjectId -RoleDefinitionId $roleId -Scope $DcrId)

    if ($existing.Count -gt 0) {
        Write-iSOCLog "Service principal already holds $roleName on the DCR." -Level Success
        return 'Held'
    }
    if ($Grant) {
        if (-not $PSCmdlet.ShouldProcess("$DcrName / SP $ClientId", "Grant $roleName")) { return 'Skipped' }
        New-iSOCRoleAssignment -Context $Context -Scope $DcrId -RoleDefinitionId $roleId -PrincipalId $principal.ObjectId -PrincipalType ServicePrincipal | Out-Null
        Write-iSOCLog "Granted $roleName. Data-plane RBAC can take a few minutes to take effect, so early POSTs may 403." -Level Warning
        return 'Granted'
    }
    Write-iSOCLog "Service principal does not hold $roleName on the DCR. Streaming will 403 until it does." -Level Warning
    Write-iSOCLog "Grant it with:  New-AzRoleAssignment -ObjectId $($principal.ObjectId) -RoleDefinitionName '$roleName' -Scope $DcrId" -Level Warning
    Write-iSOCLog 'Or re-run with -GrantIngestionRole.' -Level Warning
    'Missing'
}
