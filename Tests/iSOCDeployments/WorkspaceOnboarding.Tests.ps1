#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for Get-iSOCWorkspaceOnboarding, the first stage of the
    deploy pipelines.

.DESCRIPTION
    The decision table on its own, then the command over one stand-in
    subscription (_helpers/WorkspaceStandIn.psm1): what it returns, the
    playbook resource group it leaves out, the read it stops on when refused,
    the api-versions it reads at, the sign-in it moves to -SubscriptionId and
    the prerequisites it needs. Parity with the inline steps it replaced (the
    Check for Existing Resources step of .github/workflows/sentinel-deploy.yml
    and the Check for Existing Log Analytics Workspace step of
    Pipelines/Sentinel-Deploy.yml, MIGRATION.md edit E42) was proven before
    each step was replaced by the command, and both pipelines now call it.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/WorkspaceOnboarding.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/WorkspaceOnboarding.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.3.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    $script:standInModule = Join-Path $PSScriptRoot '_helpers/WorkspaceStandIn.psm1'
    Import-Module $script:standInModule -Force
    $script:subscription = (Get-WorkspaceStandIn).SubscriptionId

    function Invoke-ModuleOnboarding {
        <#
        .SYNOPSIS
            Run Get-iSOCWorkspaceOnboarding over $State; return its result or error and what it logged.
        .PARAMETER State
            The stand-in state the command runs over.
        .PARAMETER Playbook
            The playbook resource group the command is given.
        #>
        param($State, [string] $Playbook)

        $script:standIn = $State
        $script:logs = [System.Collections.Generic.List[object]]::new()
        $script:azContext = [pscustomobject]@{
            Subscription = [pscustomobject]@{ Id = $State.SubscriptionId; TenantId = 'tenant-1' }
            Tenant       = [pscustomobject]@{ Id = 'tenant-1' }
            Account      = [pscustomobject]@{ Id = 'deployer@example.test' }
            Environment  = [pscustomobject]@{ Name = 'AzureCloud'; ResourceManagerUrl = 'https://management.azure.com/'; ExtendedProperties = [System.Collections.Generic.Dictionary[string, string]]::new() }
        }
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
        Mock -ModuleName iSOCDeployments Get-iSOCAzContext { $script:azContext }
        Mock -ModuleName iSOCDeployments Write-iSOCLog { $script:logs.Add([pscustomobject]@{ Message = $Message; Level = $Level }) }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            $answer = Invoke-WorkspaceStandInArm -State $script:standIn -Method $Method -Path $Path -Body $Body
            if ($answer.Status -eq 404 -and $AllowNotFound) { return }
            if ($answer.Status -ge 400) {
                $exception = [System.Net.Http.HttpRequestException]::new("HTTP $($answer.Status) from $Method stand-in: $($answer.Body.error.message)", $null, [System.Net.HttpStatusCode]$answer.Status)
                throw [System.Management.Automation.ErrorRecord]::new($exception, "iSOCRest.Http$($answer.Status)", 'InvalidOperation', $Path)
            }
            $answer.Body | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        }

        $result = $null
        $failure = $null
        try { $result = Get-iSOCWorkspaceOnboarding -ResourceGroup rg-sentinel -WorkspaceName law-sentinel -PlaybookResourceGroup $Playbook }
        catch { $failure = $_ }
        [pscustomobject]@{ Result = $result; Error = $failure; Logs = $script:logs.ToArray(); State = $script:standIn }
    }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
    Remove-Module WorkspaceStandIn -ErrorAction SilentlyContinue
}

Describe 'Get-iSOCOnboardingDecision' {
    It 'decides <Status> for <Found>' -ForEach @(
        @{ Found = 'everything'; Rg = $true; Ws = $true; Sol = $true; State = $true; Pb = $null; Status = 'Onboarded'; Infra = $false; Sentinel = $false; Exit = 0 }
        @{ Found = 'no resource group'; Rg = $false; Ws = $false; Sol = $false; State = $false; Pb = $null; Status = 'NoResourceGroup'; Infra = $true; Sentinel = $true; Exit = 0 }
        @{ Found = 'no workspace'; Rg = $true; Ws = $false; Sol = $false; State = $false; Pb = $null; Status = 'NoWorkspace'; Infra = $true; Sentinel = $true; Exit = 0 }
        @{ Found = 'neither onboarding resource'; Rg = $true; Ws = $true; Sol = $false; State = $false; Pb = $null; Status = 'NotOnboarded'; Infra = $true; Sentinel = $true; Exit = 0 }
        @{ Found = 'the solution only'; Rg = $true; Ws = $true; Sol = $true; State = $false; Pb = $null; Status = 'StateMissing'; Infra = $true; Sentinel = $true; Exit = 0 }
        @{ Found = 'the onboarding state only'; Rg = $true; Ws = $true; Sol = $false; State = $true; Pb = $true; Status = 'SolutionMissing'; Infra = $false; Sentinel = $false; Exit = 1 }
        @{ Found = 'everything but the playbook group'; Rg = $true; Ws = $true; Sol = $true; State = $true; Pb = $false; Status = 'Onboarded'; Infra = $true; Sentinel = $false; Exit = 0 }
        @{ Found = 'everything and the playbook group'; Rg = $true; Ws = $true; Sol = $true; State = $true; Pb = $true; Status = 'Onboarded'; Infra = $false; Sentinel = $false; Exit = 0 }
        @{ Found = 'no workspace and no playbook group'; Rg = $true; Ws = $false; Sol = $false; State = $false; Pb = $false; Status = 'NoWorkspace'; Infra = $true; Sentinel = $true; Exit = 0 }
    ) {
        $decision = InModuleScope iSOCDeployments -Parameters @{ A = @{ ResourceGroupExists = $Rg; WorkspaceExists = $Ws; SolutionExists = $Sol; OnboardingStateExists = $State; PlaybookResourceGroupExists = $Pb } } {
            param($A) Get-iSOCOnboardingDecision @A
        }
        $decision.Status | Should -Be $Status
        $decision.InfrastructureNeeded | Should -Be $Infra
        $decision.DeploySentinel | Should -Be $Sentinel
        $decision.ExitCode | Should -Be $Exit
    }
}

Describe 'Get-iSOCWorkspaceOnboarding' {
    It 'returns what it found' {
        $run = Invoke-ModuleOnboarding -State (Get-WorkspaceStandIn -ResourceGroups @('rg-sentinel')) -Playbook ' rg-playbooks '
        $run.Result.ResourceGroup | Should -Be 'rg-sentinel'
        $run.Result.WorkspaceName | Should -Be 'law-sentinel'
        $run.Result.PlaybookResourceGroup | Should -Be 'rg-playbooks'
        $run.Result.ResourceGroupExists | Should -BeTrue
        $run.Result.WorkspaceExists | Should -BeTrue
        $run.Result.SolutionExists | Should -BeTrue
        $run.Result.OnboardingStateExists | Should -BeTrue
        $run.Result.PlaybookResourceGroupExists | Should -BeFalse
    }

    It 'leaves the playbook group out when playbooks share the Sentinel group' {
        $run = Invoke-ModuleOnboarding -State (Get-WorkspaceStandIn) -Playbook 'rg-sentinel'
        $run.Result.PlaybookResourceGroup | Should -BeNullOrEmpty
        $run.Result.PlaybookResourceGroupExists | Should -BeNullOrEmpty
    }

    It 'stops on a read it is refused, rather than reading the solution as missing' {
        $solution = '/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-sentinel/providers/Microsoft.OperationsManagement/solutions/SecurityInsights(law-sentinel)'
        $run = Invoke-ModuleOnboarding -State (Get-WorkspaceStandIn -Forbidden @($solution)) -Playbook ''
        $run.Error | Should -Not -BeNullOrEmpty
        $run.Error.Exception.Message | Should -BeLike 'HTTP 403*'
    }

    It 'reads at the module''s api-versions' {
        $script:seen = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Get-iSOCAzSession { @{ SubscriptionId = '11111111-2222-3333-4444-555555555555' } }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { $script:seen.Add("$(($Path -split '/')[-1])=$ApiVersion"); [pscustomobject]@{ id = $Path } }
        Get-iSOCWorkspaceOnboarding -ResourceGroup rg-sentinel -WorkspaceName law-sentinel -PlaybookResourceGroup rg-playbooks | Out-Null
        @($script:seen) | Should -Be @('rg-sentinel=2021-04-01', 'law-sentinel=2022-10-01', 'SecurityInsights(law-sentinel)=2015-11-01-preview', 'default=2025-09-01', 'rg-playbooks=2021-04-01')
    }

    It 'moves the sign-in to -SubscriptionId' {
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Get-iSOCAzSession { @{ SubscriptionId = $SubscriptionId } }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { }
        $other = '99999999-2222-3333-4444-555555555555'
        Get-iSOCWorkspaceOnboarding -ResourceGroup rg-sentinel -WorkspaceName law-sentinel -SubscriptionId $other | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Get-iSOCAzSession -Times 1 -Exactly -ParameterFilter { $SubscriptionId -eq $other }
        Should -Invoke -ModuleName iSOCDeployments Invoke-iSOCRestRequest -ParameterFilter { $Path -eq "/subscriptions/$other/resourceGroups/rg-sentinel" }
    }

    It 'needs the Connect step''s prerequisites' {
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { throw 'Az.Accounts is missing' }
        { Get-iSOCWorkspaceOnboarding -ResourceGroup rg-sentinel -WorkspaceName law-sentinel } | Should -Throw '*Az.Accounts is missing*'
        Should -Invoke -ModuleName iSOCDeployments Assert-iSOCPrerequisite -ParameterFilter { $Step -contains 'Connect' }
    }
}
