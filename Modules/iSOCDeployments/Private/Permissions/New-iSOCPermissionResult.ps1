#Requires -Version 7.6

<#
.SYNOPSIS
    The outcome of one role for one identity.

.DESCRIPTION
    One per role a command looked at, and one for an identity it could not
    give any.

.NOTES
    File:         Modules/iSOCDeployments/Private/Permissions/New-iSOCPermissionResult.ps1
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

function New-iSOCPermissionResult {
    <#
    .SYNOPSIS
        Build a permission result.

    .PARAMETER Name
        The identity's owner: a playbook, an Automation Account.

    .PARAMETER PrincipalId
        The managed identity's principal id.

    .PARAMETER Role
        The role, or nothing for a result about the identity itself.

    .PARAMETER Scope
        Where the role applies.

    .PARAMETER Outcome
        Assigned, Removed, Unchanged, Skipped, Failed or WhatIf.

    .PARAMETER Reason
        Why, when the outcome is not a plain one.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.PermissionResult.

    .EXAMPLE
        New-iSOCPermissionResult -Name 'Incident-Close' -Role 'Microsoft Sentinel Responder' -Scope $rg -Outcome Assigned
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; nothing outside the call changes.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [AllowEmptyString()]
        [string] $PrincipalId = '',

        [AllowEmptyString()]
        [string] $Role = '',

        [AllowEmptyString()]
        [string] $Scope = '',

        [Parameter(Mandatory)]
        [ValidateSet('Assigned', 'Removed', 'Unchanged', 'Skipped', 'Failed', 'WhatIf')]
        [string] $Outcome,

        [AllowEmptyString()]
        [string] $Reason = ''
    )

    [pscustomobject]@{
        PSTypeName  = 'iSOCDeployments.PermissionResult'
        Name        = $Name
        PrincipalId = $PrincipalId
        Role        = $Role
        Scope       = $Scope
        Outcome     = $Outcome
        Reason      = $Reason
    }
}
