#Requires -Version 7.6

<#
.SYNOPSIS
    Decide what the infrastructure step must do from what a workspace has.

.DESCRIPTION
    Copied from the decision at the end of the Check for Existing Resources
    step of .github/workflows/sentinel-deploy.yml.

.NOTES
    File:         Modules/iSOCDeployments/Private/Onboarding/Get-iSOCOnboardingDecision.ps1
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

function Get-iSOCOnboardingDecision {
    <#
    .SYNOPSIS
        Decide what the infrastructure step must do from what a workspace
        has.

    .DESCRIPTION
        Sentinel is onboarded twice over: the SecurityInsights solution
        (Microsoft.OperationsManagement/solutions) and the onboarding state
        (Microsoft.SecurityInsights/onboardingStates/default). The Bicep
        template deploys both, and both must exist. The solution deploys
        again harmlessly; the onboarding state does not, and a second
        deployment of it returns Conflict. So:

          both present        Onboarded: the Sentinel module is left out
          neither present     NotOnboarded: the module deploys both
          state missing       StateMissing: the module deploys again, which
                              creates the state and repeats the solution
          solution missing    SolutionMissing: nothing can repair it, since
                              deploying the module would Conflict on the
                              state and leaving it out leaves the solution
                              missing; someone must step in

        A missing resource group or workspace needs the module too. The
        template also runs, without the module, when only a separate
        playbook resource group is missing.

    .PARAMETER ResourceGroupExists
        The Sentinel resource group exists.

    .PARAMETER WorkspaceExists
        The workspace exists.

    .PARAMETER SolutionExists
        The SecurityInsights solution exists.

    .PARAMETER OnboardingStateExists
        The onboarding state exists.

    .PARAMETER PlaybookResourceGroupExists
        The separate playbook resource group exists; leave it out when
        playbooks share the Sentinel resource group.

    .OUTPUTS
        [hashtable] Status, InfrastructureNeeded, DeploySentinel and
        ExitCode (1 for SolutionMissing, else 0).

    .EXAMPLE
        Get-iSOCOnboardingDecision -ResourceGroupExists $true -WorkspaceExists $true -SolutionExists $true -OnboardingStateExists $false
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [bool] $ResourceGroupExists,
        [bool] $WorkspaceExists,
        [bool] $SolutionExists,
        [bool] $OnboardingStateExists,
        [AllowNull()]
        [Nullable[bool]] $PlaybookResourceGroupExists
    )

    $status = if (-not $ResourceGroupExists) { 'NoResourceGroup' }
    elseif (-not $WorkspaceExists) { 'NoWorkspace' }
    elseif ($SolutionExists -and $OnboardingStateExists) { 'Onboarded' }
    elseif (-not $SolutionExists -and -not $OnboardingStateExists) { 'NotOnboarded' }
    elseif ($SolutionExists) { 'StateMissing' }
    else { 'SolutionMissing' }

    if ($status -eq 'SolutionMissing') {
        return @{ Status = $status; InfrastructureNeeded = $false; DeploySentinel = $false; ExitCode = 1 }
    }
    $sentinelReady = $status -eq 'Onboarded'
    $playbookReady = $null -eq $PlaybookResourceGroupExists -or $PlaybookResourceGroupExists
    @{
        Status               = $status
        InfrastructureNeeded = (-not $sentinelReady) -or (-not $playbookReady)
        DeploySentinel       = -not $sentinelReady
        ExitCode             = 0
    }
}
