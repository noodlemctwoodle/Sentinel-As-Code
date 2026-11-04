#Requires -Version 7.2

<#
.SYNOPSIS
    Delete a role assignment.

.DESCRIPTION
    Replaces az role assignment delete (Deploy/permissions/Set-RunbookPermissions.ps1), which the script ran
    without looking at what it returned.

.NOTES
    File:         Modules/iSOCDeployments/Private/Permissions/Remove-iSOCRoleAssignment.ps1
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

function Remove-iSOCRoleAssignment {
    <#
    .SYNOPSIS
        Delete one role assignment by its resource id.

    .PARAMETER Context
        The workspace context.

    .PARAMETER AssignmentId
        The assignment's id, from Get-iSOCRoleAssignment.

    .EXAMPLE
        Remove-iSOCRoleAssignment -Context $ctx -AssignmentId $assignment.Id
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The public command that calls it checks ShouldProcess.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $AssignmentId
    )

    Invoke-iSOCRestRequest -Method DELETE -Path $AssignmentId -ApiVersion (Get-iSOCApiVersion Authorization) -Context $Context -AllowNotFound | Out-Null
}
