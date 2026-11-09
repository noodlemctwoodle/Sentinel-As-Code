#Requires -Version 7.6

<#
.SYNOPSIS
    Wait for a workspace's Sentinel onboarding to be readable.

.DESCRIPTION
    Copied from the onboarding wait at the start of Get-ContentHubSolutions
    (Deploy/content/Deploy-SentinelContentHub.ps1). A workspace onboarded
    moments before, by the infrastructure stage, can take two or three
    minutes before its onboarding state answers.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Wait-iSOCWorkspaceOnboarding.ps1
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

function Wait-iSOCWorkspaceOnboarding {
    <#
    .SYNOPSIS
        Return once the onboarding state reads, or throw after three
        minutes.

    .DESCRIPTION
        Reads onboardingStates/default once every 15 seconds, one attempt
        each, for up to 180 seconds. The response itself is not used: a
        successful read means onboarding has propagated.

    .PARAMETER Context
        The workspace context.

    .OUTPUTS
        None.

    .EXAMPLE
        Wait-iSOCWorkspaceOnboarding -Context $ctx
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context
    )

    Write-iSOCLog 'Verifying Sentinel onboarding status...' -Level Section
    $path = "$($Context.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/onboardingStates/default"
    $maxWait = 180
    $elapsed = 0
    $interval = 15
    while ($elapsed -lt $maxWait) {
        try {
            [void](Invoke-iSOCRestRequest -Method GET -Path $path -ApiVersion (Get-iSOCApiVersion SecurityInsights) -MaxAttempts 1)
            Write-iSOCLog 'Sentinel onboarding confirmed.' -Level Success
            return
        }
        catch {
            $elapsed += $interval
            if ($elapsed -ge $maxWait) {
                throw "Sentinel workspace '$($Context.WorkspaceName)' is not onboarded after waiting ${maxWait}s. Ensure Bicep deployment completed successfully."
            }
            Write-iSOCLog "Workspace not yet onboarded; waiting ${interval}s ($elapsed/${maxWait}s)..." -Level Warning
            Start-Sleep -Seconds $interval
        }
    }
}
