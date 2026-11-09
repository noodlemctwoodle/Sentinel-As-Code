#Requires -Version 7.6

<#
.SYNOPSIS
    Record one content file's deployment outcome in the state.

.DESCRIPTION
    Copied from Set-DeploymentItemState (Deploy/content/Deploy-CustomContent.ps1),
    unchanged in behaviour, with the state passed in.

.NOTES
    File:         Modules/iSOCDeployments/Private/State/Set-iSOCDeploymentItemState.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Set-iSOCDeploymentItemState {
    <#
    .SYNOPSIS
        Mark a file deployed now, or forget it so the next run retries it.

    .PARAMETER State
        From Read-iSOCDeploymentState.

    .PARAMETER Key
        The file's repository-relative path.

    .PARAMETER Status
        success or failed.

    .EXAMPLE
        Set-iSOCDeploymentItemState -State $run.State -Key $relative -Status success
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes the in-memory state only; saving it is Save-iSOCDeploymentState.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $State,

        [Parameter(Mandatory)]
        [string] $Key,

        [Parameter(Mandatory)]
        [ValidateSet('success', 'failed')]
        [string] $Status
    )

    if ($Status -eq 'success') {
        $State.Items[$Key] = @{
            lastDeployed = (Get-Date -Format 'o')
            status       = 'success'
        }
    }
    elseif ($State.Items.ContainsKey($Key)) {
        $State.Items.Remove($Key)
    }
}
