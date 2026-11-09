#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for Get-iSOCWorkspaceOnboarding, against the inline
    PowerShell of the deploy pipelines' first stage.

.DESCRIPTION
    The decision table on its own, then parity with GitHub: the Check for
    Existing Resources step of .github/workflows/sentinel-deploy.yml is
    lifted out of the YAML unchanged and run in a child pwsh, with stand-in
    Az cmdlets, beside the command, over one stand-in subscription
    (_helpers/WorkspaceStandIn.psm1). For each state of the workspace the
    command must read what the GitHub step reads and decide as it decides,
    or report the same unrecoverable state. Parity with the old Check for
    Existing Log Analytics Workspace step of Pipelines/Sentinel-Deploy.yml
    (MIGRATION.md edit E42) was proven on release/26.11.0 before that step
    was replaced by the command.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/WorkspaceOnboarding.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/WorkspaceOnboarding.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+, powershell-yaml
#>

BeforeDiscovery {
    $script:cases = @(
        @{ Case = 'a fully onboarded workspace'; State = @{}; Playbook = ''; Status = 'Onboarded'; Infra = $false; Sentinel = $false }
        @{ Case = 'no resource group'; State = @{ ResourceGroups = @('rg-playbooks'); Workspaces = @(); Solutions = @(); Onboarded = @() }; Playbook = ''; Status = 'NoResourceGroup'; Infra = $true; Sentinel = $true }
        @{ Case = 'no workspace'; State = @{ Workspaces = @(); Solutions = @(); Onboarded = @() }; Playbook = ''; Status = 'NoWorkspace'; Infra = $true; Sentinel = $true }
        @{ Case = 'a workspace without Sentinel'; State = @{ Solutions = @(); Onboarded = @() }; Playbook = ''; Status = 'NotOnboarded'; Infra = $true; Sentinel = $true }
        @{ Case = 'the onboarding state missing'; State = @{ Onboarded = @() }; Playbook = ''; Status = 'StateMissing'; Infra = $true; Sentinel = $true }
        @{ Case = 'the solution missing'; State = @{ Solutions = @() }; Playbook = ''; Status = 'SolutionMissing'; Infra = $false; Sentinel = $false }
        @{ Case = 'a playbook group that exists'; State = @{}; Playbook = 'rg-playbooks'; Status = 'Onboarded'; Infra = $false; Sentinel = $false }
        @{ Case = 'a playbook group that is missing'; State = @{ ResourceGroups = @('rg-sentinel') }; Playbook = 'rg-playbooks'; Status = 'Onboarded'; Infra = $true; Sentinel = $false }
        @{ Case = 'the Sentinel group named as the playbook group'; State = @{}; Playbook = 'rg-sentinel'; Status = 'Onboarded'; Infra = $false; Sentinel = $false }
        @{ Case = 'a playbook group with spaces round it'; State = @{}; Playbook = '  rg-playbooks  '; Status = 'Onboarded'; Infra = $false; Sentinel = $false }
        @{ Case = 'nothing at all and a playbook group'; State = @{ ResourceGroups = @(); Workspaces = @(); Solutions = @(); Onboarded = @() }; Playbook = 'rg-playbooks'; Status = 'NoResourceGroup'; Infra = $true; Sentinel = $true }
    )
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    $script:standInModule = Join-Path $PSScriptRoot '_helpers/WorkspaceStandIn.psm1'
    Import-Module $script:standInModule -Force
    $script:gitHubFile = Join-Path $script:repoRoot '.github/workflows/sentinel-deploy.yml'
    $script:subscription = (Get-WorkspaceStandIn).SubscriptionId

    function Get-CaseState {
        param([hashtable] $State)
        Get-WorkspaceStandIn @State
    }

    function Invoke-PipelineStep {
        <# Run one pipeline step unchanged in a child pwsh over $State; return its outputs, error lines, exit code and the state after. #>
        param([string] $File, [string] $Step, $State, [string] $Playbook)

        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        $statePath = Join-Path $dir 'state.json'
        $outputPath = Join-Path $dir 'github-output.txt'
        Export-WorkspaceStandIn -State $State -Path $statePath
        $variables = @{ RESOURCE_GROUP = 'rg-sentinel'; WORKSPACE_NAME = 'law-sentinel'; PLAYBOOK_RESOURCE_GROUP = $Playbook; AZURE_SUBSCRIPTION_ID = $State.SubscriptionId }
        $inline = Get-PipelineInlineScript -Path $File -Step $Step -Variables $variables
        $wrapper = @'
$ErrorActionPreference = 'Stop'
Import-Module '__MODULE__'
$script:StandIn = Import-WorkspaceStandIn -Path '__STATE__'
$env:GITHUB_OUTPUT = '__OUTPUT__'
function Get-StandInBody { param($Answer) $Answer.Body | ConvertTo-Json -Depth 20 | ConvertFrom-Json }
function Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = $script:StandIn.SubscriptionId } } }
function Get-AzResourceGroup {
    [CmdletBinding()] param([string] $Name)
    $answer = Invoke-WorkspaceStandInArm -State $script:StandIn -Method GET -Path "/subscriptions/$($script:StandIn.SubscriptionId)/resourceGroups/$Name"
    if ($answer.Status -eq 200) { return Get-StandInBody $answer }
    Write-Error "Provided resource group does not exist. ($($answer.Status))"
}
function Get-AzOperationalInsightsWorkspace {
    [CmdletBinding()] param([string] $ResourceGroupName, [string] $Name)
    $answer = Invoke-WorkspaceStandInArm -State $script:StandIn -Method GET -Path "/subscriptions/$($script:StandIn.SubscriptionId)/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$Name"
    if ($answer.Status -eq 200) { return Get-StandInBody $answer }
    Write-Error "The workspace was not found. ($($answer.Status))"
}
function Get-AzResource {
    [CmdletBinding()] param([string] $ResourceId, [string] $ApiVersion)
    $answer = Invoke-WorkspaceStandInArm -State $script:StandIn -Method GET -Path $ResourceId
    if ($answer.Status -eq 200) { return Get-StandInBody $answer }
    Write-Error "The resource was not found. ($($answer.Status))"
}
try {
__SCRIPT__
}
finally {
    Export-WorkspaceStandIn -State $script:StandIn -Path '__STATE__'
}
'@
        $runPath = Join-Path $dir 'run.ps1'
        $wrapper.Replace('__MODULE__', $script:standInModule).Replace('__STATE__', $statePath).Replace('__OUTPUT__', $outputPath).Replace('__SCRIPT__', $inline) |
            Set-Content -LiteralPath $runPath -Encoding utf8NoBOM
        $lines = @(& pwsh -NoProfile -NonInteractive -File $runPath 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
        $outputs = @{}
        if (Test-Path -LiteralPath $outputPath) {
            foreach ($line in Get-Content -LiteralPath $outputPath) { if ($line -match '^(\w+)=(.*)$') { $outputs[$Matches[1]] = $Matches[2] } }
        }
        [pscustomobject]@{
            Outputs  = $outputs
            Errors   = @($lines | Where-Object { $_ -like '::error::*' } | ForEach-Object { $_.Substring(9) })
            ExitCode = $code
            Lines    = $lines
            State    = Import-WorkspaceStandIn -Path $statePath
        }
    }

    function Invoke-ModuleOnboarding {
        <# Run Get-iSOCWorkspaceOnboarding over $State; return its result or error and what it logged. #>
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

Describe 'Get-iSOCWorkspaceOnboarding beside the GitHub step: <Case>' -ForEach $script:cases {
    BeforeAll {
        $script:gitHub = Invoke-PipelineStep -File $script:gitHubFile -Step 'Check for Existing Resources' -State (Get-CaseState $State) -Playbook $Playbook
        $script:module = Invoke-ModuleOnboarding -State (Get-CaseState $State) -Playbook $Playbook
    }

    It 'runs the command to a result' {
        $script:module.Error | Should -BeNullOrEmpty
        $script:module.Result.PSObject.TypeNames | Should -Contain 'iSOCDeployments.WorkspaceOnboarding'
    }

    It 'reports <Status>' {
        $script:module.Result.Status | Should -Be $Status
        $script:module.Result.InfrastructureNeeded | Should -Be $Infra
        $script:module.Result.DeploySentinel | Should -Be $Sentinel
    }

    It 'reads what the GitHub step reads, in its order' {
        @($script:gitHub.State.Reads).Count | Should -BeGreaterThan 0
        @($script:module.State.Reads) | Should -Be @($script:gitHub.State.Reads)
    }

    It 'decides as the GitHub step decides' {
        if ($Status -eq 'SolutionMissing') {
            $script:gitHub.ExitCode | Should -Not -Be 0
            $script:module.Result.ExitCode | Should -Be 1
            return
        }
        $script:gitHub.ExitCode | Should -Be 0
        $script:module.Result.ExitCode | Should -Be 0
        $script:gitHub.Outputs['bicep_needed'] | Should -Be $script:module.Result.InfrastructureNeeded.ToString().ToLower()
        $script:gitHub.Outputs['deploy_sentinel'] | Should -Be $script:module.Result.DeploySentinel.ToString().ToLower()
    }

    It 'logs the GitHub step''s errors, naming the deployment rather than the workflow' {
        $moduleErrors = @($script:module.Logs | Where-Object Level -eq 'Error' | ForEach-Object { $_.Message })
        $expected = @($script:gitHub.Errors | ForEach-Object { $_.Replace('re-run this workflow', 're-run the deployment') })
        if ($Status -eq 'SolutionMissing') { $expected.Count | Should -BeGreaterThan 0 }
        ($moduleErrors -join "`n") | Should -BeExactly ($expected -join "`n")
    }

    It 'logs nothing that names the subscription' {
        @($script:module.Logs | Where-Object { $_.Message -like "*$script:subscription*" }) | Should -BeNullOrEmpty
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

    It 'stops on a read it is refused, where the GitHub step read the solution as missing' {
        $solution = '/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-sentinel/providers/Microsoft.OperationsManagement/solutions/SecurityInsights(law-sentinel)'
        $run = Invoke-ModuleOnboarding -State (Get-WorkspaceStandIn -Forbidden @($solution)) -Playbook ''
        $run.Error | Should -Not -BeNullOrEmpty
        $run.Error.Exception.Message | Should -BeLike 'HTTP 403*'
        $gitHub = Invoke-PipelineStep -File $script:gitHubFile -Step 'Check for Existing Resources' -State (Get-WorkspaceStandIn -Forbidden @($solution)) -Playbook ''
        $gitHub.ExitCode | Should -Not -Be 0
        $gitHub.Errors[0] | Should -BeLike 'Unrecoverable partial Sentinel onboarding state*'
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
