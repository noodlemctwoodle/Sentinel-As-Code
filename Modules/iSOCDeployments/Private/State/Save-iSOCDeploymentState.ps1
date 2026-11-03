#Requires -Version 7.2

<#
.SYNOPSIS
    Write deployment-state.json.

.DESCRIPTION
    Replaces Save-DeploymentState (Deploy/content/Deploy-CustomContent.ps1),
    in the same format. The caller saves only when it is not given -WhatIf;
    the script saved under -WhatIf too, creating the file when it was
    missing (MIGRATION.md edit E12).

.NOTES
    File:         Modules/iSOCDeployments/Private/State/Save-iSOCDeploymentState.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Save-iSOCDeploymentState {
    <#
    .SYNOPSIS
        Write the deployment state to its file.

    .DESCRIPTION
        Writes { "deployedItems": { "<path>": { "lastDeployed", "status" } } }
        as UTF-8 with LF line endings. A failure to write is a warning, not
        a failed deployment, as it was.

    .PARAMETER State
        From Read-iSOCDeploymentState.

    .EXAMPLE
        Save-iSOCDeploymentState -State $run.State
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Deploy-iSOCContent decides whether to save; this is the write itself.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $State
    )

    try {
        Write-iSOCTextFile -Path $State.Path -Content (@{ deployedItems = $State.Items } | ConvertTo-Json -Depth 5)
        Write-iSOCLog "Deployment state saved ($($State.Items.Count) item(s))." -Level Debug
    }
    catch {
        Write-iSOCLog "Failed to save deployment state: $($_.Exception.Message)" -Level Warning
    }
}
