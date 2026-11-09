#Requires -Version 7.6

<#
.SYNOPSIS
    Whether the state records a file's last deployment as a success.

.DESCRIPTION
    Copied from Test-WasDeployedSuccessfully
    (Deploy/content/Deploy-CustomContent.ps1), unchanged in behaviour, with
    the state passed in.

.NOTES
    File:         Modules/iSOCDeployments/Private/State/Test-iSOCDeployedSuccessfully.ps1
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

function Test-iSOCDeployedSuccessfully {
    <#
    .SYNOPSIS
        Return true when the file's last recorded deployment succeeded.

    .PARAMETER State
        From Read-iSOCDeploymentState.

    .PARAMETER Key
        The file's repository-relative path.

    .OUTPUTS
        [bool]

    .EXAMPLE
        Test-iSOCDeployedSuccessfully -State $run.State -Key $relative
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [psobject] $State,

        [Parameter(Mandatory)]
        [string] $Key
    )

    if ($State.Items.ContainsKey($Key)) { return ($State.Items[$Key].status -eq 'success') }
    $false
}
