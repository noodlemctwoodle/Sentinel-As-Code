#Requires -Version 7.2

<#
.SYNOPSIS
    Read the workspace's primary shared key through the Az sign-in.

.DESCRIPTION
    Held in memory for signing, and never logged.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Get-iSOCWorkspaceSharedKey.ps1
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

function Get-iSOCWorkspaceSharedKey {
    <#
    .SYNOPSIS
        Read the workspace's primary shared key through the Az sign-in.

    .DESCRIPTION
        POSTs the workspace's sharedKeys action, which only reads, so it
        runs under -WhatIf. Reading the key needs Log Analytics Contributor
        on the workspace. The key is returned for signing and never logged.
        No key throws.

    .PARAMETER Context
        The workspace context.

    .OUTPUTS
        [string] The primary shared key.

    .EXAMPLE
        $key = Get-iSOCWorkspaceSharedKey -Context $ctx
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context
    )

    $keys = Invoke-iSOCRestRequest -Method POST -Path "$($Context.WorkspaceResourceId)/sharedKeys" -ApiVersion (Get-iSOCApiVersion SharedKeys) -ReadOnly
    $key = [string](Get-iSOCPropertyValue -InputObject $keys -Path 'primarySharedKey')
    if ([string]::IsNullOrWhiteSpace($key)) {
        throw 'Could not retrieve the workspace primary shared key. Confirm you have Log Analytics Contributor on the workspace.'
    }
    $key
}
