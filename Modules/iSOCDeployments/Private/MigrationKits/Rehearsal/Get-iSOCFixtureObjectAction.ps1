#Requires -Version 7.6

<#
.SYNOPSIS
    What the plan does with one fixture object: CREATE, UPDATE, ABORT, DELETE, SKIP or ABSENT.

.DESCRIPTION
    Existence alone never allows a write or a delete: an object that exists
    without the marker stops a create and is left by a removal.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Get-iSOCFixtureObjectAction.ps1
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

function Get-iSOCFixtureObjectAction {
    <#
    .SYNOPSIS
        What the plan does with one fixture object: CREATE, UPDATE, ABORT,
        DELETE, SKIP or ABSENT.

    .DESCRIPTION
        Creating: an object not there is CREATE, one there and owned UPDATE,
        one there and not owned ABORT (the run stops before anything is
        written). Removing: not there is ABSENT, owned DELETE, not owned
        SKIP (it belongs to someone else).

    .PARAMETER Existing
        The object as the workspace has it, if it does.

    .PARAMETER IsOwned
        Whether it carries the fixture's marker.

    .PARAMETER ForRemoval
        Decide for a removal.

    .OUTPUTS
        [string]

    .EXAMPLE
        Get-iSOCFixtureObjectAction -Existing $found -IsOwned $true -ForRemoval
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object] $Existing,

        [bool] $IsOwned,

        [switch] $ForRemoval
    )

    if ($null -eq $Existing) { return $(if ($ForRemoval) { 'ABSENT' } else { 'CREATE' }) }
    if ($IsOwned) { return $(if ($ForRemoval) { 'DELETE' } else { 'UPDATE' }) }
    $(if ($ForRemoval) { 'SKIP' } else { 'ABORT' })
}
