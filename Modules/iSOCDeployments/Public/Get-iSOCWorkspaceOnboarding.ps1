#Requires -Version 7.6

<#
.SYNOPSIS
    Get-iSOCWorkspaceOnboarding: whether a workspace and its onboarding
    exist, and what the infrastructure step must deploy.

.DESCRIPTION
    Replaces the inline PowerShell of the first stage of the deploy
    pipelines: the Check for Existing Log Analytics Workspace step of
    Pipelines/Sentinel-Deploy.yml and the Check for Existing Resources step
    of .github/workflows/sentinel-deploy.yml (MIGRATION.md edit E42).

.NOTES
    File:         Modules/iSOCDeployments/Public/Get-iSOCWorkspaceOnboarding.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCWorkspaceOnboarding {
    <#
    .SYNOPSIS
        Read whether a workspace and its onboarding exist, and say what the
        infrastructure template must deploy.

    .DESCRIPTION
        Reads the Sentinel resource group, the workspace, the two resources
        that onboard Sentinel (the SecurityInsights solution and the
        onboarding state) and, when playbooks have a resource group of their
        own, that group. The result says whether the Bicep template needs to
        run (InfrastructureNeeded) and whether its Sentinel module should
        (DeploySentinel, main.bicep's deploySentinel): the onboarding state
        cannot be deployed twice, so the module runs only when Sentinel is
        not fully onboarded. Docs/Infra/Bicep.md explains the two onboarding
        resources.

        One state cannot be repaired by the template: the onboarding state
        present but the solution gone. The command then logs what to do as
        errors and returns ExitCode 1, so the pipeline stops before Bicep.

        It needs only an Az sign-in, not Connect-iSOCWorkspace: the
        workspace it asks about may not exist yet. Nothing in Azure changes,
        and nothing it logs names the subscription. A resource that cannot
        be read for want of permission stops the command, rather than
        reading as missing and sending Bicep to deploy over it.

    .PARAMETER ResourceGroup
        The resource group holding the workspace.

    .PARAMETER WorkspaceName
        The Log Analytics workspace Sentinel runs on.

    .PARAMETER SubscriptionId
        The subscription holding the workspace. Defaults to the sign-in's
        current subscription.

    .PARAMETER PlaybookResourceGroup
        The resource group playbooks deploy to, when it is not
        -ResourceGroup. Blank, or the same as -ResourceGroup, means
        playbooks share the Sentinel resource group.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.WorkspaceOnboarding: ResourceGroup,
        WorkspaceName, PlaybookResourceGroup (null when shared),
        ResourceGroupExists, WorkspaceExists, SolutionExists,
        OnboardingStateExists, PlaybookResourceGroupExists (null when
        shared), Status (Onboarded, NotOnboarded, StateMissing,
        SolutionMissing, NoWorkspace or NoResourceGroup),
        InfrastructureNeeded, DeploySentinel and ExitCode.

    .EXAMPLE
        Get-iSOCWorkspaceOnboarding -ResourceGroup rg-sentinel -WorkspaceName law-sentinel

        Reports whether the workspace is there and onboarded.

    .EXAMPLE
        $onboarding = Get-iSOCWorkspaceOnboarding -ResourceGroup $rg -WorkspaceName $ws -PlaybookResourceGroup $playbookRg
        "bicep_needed=$($onboarding.InfrastructureNeeded.ToString().ToLower())" >> $env:GITHUB_OUTPUT
        "deploy_sentinel=$($onboarding.DeploySentinel.ToString().ToLower())" >> $env:GITHUB_OUTPUT
        exit $onboarding.ExitCode

        A pipeline step: passes the decision to the Bicep job, and fails
        when the onboarding needs someone to repair it.
    #>
    [CmdletBinding()]
    [OutputType('iSOCDeployments.WorkspaceOnboarding')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ResourceGroup,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias('Workspace')]
        [string] $WorkspaceName,

        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
        [string] $SubscriptionId,

        [AllowEmptyString()]
        [string] $PlaybookResourceGroup
    )

    Assert-iSOCPrerequisite -Step Connect
    $session = Get-iSOCAzSession -SubscriptionId $SubscriptionId
    $groupPath = "/subscriptions/$($session.SubscriptionId)/resourceGroups"
    $exists = {
        param([string] $Path, [string] $Api)
        $null -ne (Invoke-iSOCRestRequest -Method GET -Path $Path -ApiVersion (Get-iSOCApiVersion $Api) -AllowNotFound)
    }

    Write-iSOCLog 'Checking for existing Sentinel infrastructure...' -Level Section
    $found = [ordered]@{ ResourceGroupExists = $false; WorkspaceExists = $false; SolutionExists = $false; OnboardingStateExists = $false }
    $found.ResourceGroupExists = & $exists "$groupPath/$ResourceGroup" ResourceGroups
    if (-not $found.ResourceGroupExists) {
        Write-iSOCLog "  Sentinel resource group '$ResourceGroup' missing."
    }
    else {
        Write-iSOCLog "  Sentinel resource group '$ResourceGroup' exists."
        $workspacePath = "$groupPath/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"
        $found.WorkspaceExists = & $exists $workspacePath OperationalInsights
        if (-not $found.WorkspaceExists) {
            Write-iSOCLog "  Workspace '$WorkspaceName' missing."
        }
        else {
            Write-iSOCLog "  Workspace '$WorkspaceName' exists."
            $found.SolutionExists = & $exists "$groupPath/$ResourceGroup/providers/Microsoft.OperationsManagement/solutions/SecurityInsights($WorkspaceName)" OperationsManagement
            $found.OnboardingStateExists = & $exists "$workspacePath/providers/Microsoft.SecurityInsights/onboardingStates/default" SecurityInsights
        }
    }

    $playbookGroup = $PlaybookResourceGroup.Trim()
    if (-not $playbookGroup -or $playbookGroup -eq $ResourceGroup) { $playbookGroup = $null }
    $playbookExists = $null
    if ($playbookGroup) {
        $playbookExists = & $exists "$groupPath/$playbookGroup" ResourceGroups
        Write-iSOCLog "  Playbook resource group '$playbookGroup' $(if ($playbookExists) { 'exists' } else { 'missing' })."
    }

    $decision = Get-iSOCOnboardingDecision @found -PlaybookResourceGroupExists $playbookExists
    switch ($decision.Status) {
        'Onboarded' { Write-iSOCLog '  Sentinel fully onboarded (solution and onboarding state).' }
        'NotOnboarded' { Write-iSOCLog '  Sentinel not onboarded (neither the solution nor the onboarding state).' }
        'StateMissing' {
            Write-iSOCLog '  Partial onboarding: the solution is present, the onboarding state missing.'
            Write-iSOCLog '  Repairable: the Sentinel module deploys again and creates the onboarding state; the solution deploys again harmlessly.'
        }
        'SolutionMissing' {
            foreach ($line in @(
                    "Unrecoverable partial Sentinel onboarding state on workspace '$WorkspaceName':"
                    '  - Present: Sentinel onboarding state (Microsoft.SecurityInsights/onboardingStates/default)'
                    "  - Missing: OMS Sentinel solution (Microsoft.OperationsManagement/solutions/SecurityInsights($WorkspaceName))"
                    'The non-idempotent onboardingStates resource survived but the OMS solution was deleted out of band. The deploy pipeline cannot reconcile this state automatically: re-running with deploySentinel=true would return Conflict on the surviving onboardingStates resource, and deploySentinel=false would leave the OMS solution unrepaired.'
                    'Resolution options:'
                    '  1. Delete the surviving onboardingStates/default resource via the Azure portal and re-run the deployment (Bicep will then create both fresh).'
                    '  2. Manually create the missing OMS solution via portal or an ad-hoc Bicep deploy targeting only that resource.'
                    "Background: Docs/Infra/Bicep.md 'Why two onboarding mechanisms?'."
                )) { Write-iSOCLog $line -Level Error }
        }
    }
    if ($decision.ExitCode -eq 0) {
        Write-iSOCLog "Infrastructure needed: $($decision.InfrastructureNeeded.ToString().ToLower()); Sentinel module: $($decision.DeploySentinel.ToString().ToLower())."
    }

    [pscustomobject]@{
        PSTypeName                  = 'iSOCDeployments.WorkspaceOnboarding'
        ResourceGroup               = $ResourceGroup
        WorkspaceName               = $WorkspaceName
        PlaybookResourceGroup       = $playbookGroup
        ResourceGroupExists         = $found.ResourceGroupExists
        WorkspaceExists             = $found.WorkspaceExists
        SolutionExists              = $found.SolutionExists
        OnboardingStateExists       = $found.OnboardingStateExists
        PlaybookResourceGroupExists = $playbookExists
        Status                      = $decision.Status
        InfrastructureNeeded        = $decision.InfrastructureNeeded
        DeploySentinel              = $decision.DeploySentinel
        ExitCode                    = $decision.ExitCode
    }
}
