#Requires -Version 7.6

<#
.SYNOPSIS
    The assignments that already give a principal a role at a scope.

.DESCRIPTION
    Replaces the existing-assignment check in
    Deploy/permissions/Set-PlaybookPermissions.ps1, as corrected in its
    1.0.2: before that it compared the role's full resource id with the
    bare GUID Get-AzRoleAssignment returns, so it never matched, and looked
    only at the exact scope.

.NOTES
    File:         Modules/iSOCDeployments/Private/Permissions/Find-iSOCRoleAssignment.ps1
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

function Find-iSOCRoleAssignment {
    <#
    .SYNOPSIS
        Return the assignments of a role to a principal that apply at a
        scope.

    .DESCRIPTION
        An assignment applies when it is at the scope or at a scope above
        it (a resource group's subscription, a vault's resource group).
        With -Exact only one at the scope itself counts, which is what
        removing an assignment needs. The role is compared by its GUID.

    .PARAMETER Assignment
        From Get-iSOCRoleAssignment.

    .PARAMETER PrincipalId
        The principal.

    .PARAMETER RoleDefinitionId
        The role's GUID.

    .PARAMETER Scope
        The scope.

    .PARAMETER Exact
        Count only an assignment at the scope itself.

    .OUTPUTS
        [pscustomobject] The matching assignments.

    .EXAMPLE
        Find-iSOCRoleAssignment -Assignment $existing -PrincipalId $id -RoleDefinitionId $role -Scope $rg
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Assignment = @(),

        [Parameter(Mandatory)]
        [string] $PrincipalId,

        [Parameter(Mandatory)]
        [string] $RoleDefinitionId,

        [Parameter(Mandatory)]
        [string] $Scope,

        [switch] $Exact
    )

    $target = $Scope.TrimEnd('/')
    foreach ($item in $Assignment) {
        if ($null -eq $item) { continue }
        if ($item.PrincipalId -ne $PrincipalId) { continue }
        if (($item.RoleDefinitionId -split '/')[-1] -ne $RoleDefinitionId) { continue }
        $at = ([string]$item.Scope).TrimEnd('/')
        $covers = ($at -ieq $target) -or (-not $Exact -and ($at -eq '' -or $target.StartsWith("$at/", [System.StringComparison]::OrdinalIgnoreCase)))
        if ($covers) { $item }
    }
}
