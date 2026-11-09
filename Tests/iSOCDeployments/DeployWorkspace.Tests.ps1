#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for Deploy-iSOCWorkspace and the stage gating of the
    deploy pipelines.

.DESCRIPTION
    What each stage is given: for three sets of the command's parameters
    (the pipelines' defaults, everything switched, some content left out),
    Deploy-iSOCWorkspace must give the Content Hub, custom content and
    Defender commands the explicit values listed with each case. Parity of
    what each stage is given with the deleted deploy scripts and the old
    pipeline steps was proven on release/26.11.0 before they were removed;
    the expected values are the ones those steps gave the scripts there,
    through the map MIGRATION.md's Parameters table lists.

    Which stages run: the stage conditions of Pipelines/Sentinel-Deploy.yml
    and the job conditions of .github/workflows/sentinel-deploy.yml are
    read from the YAML, held to the one shape the suite understands, and
    evaluated for every mix of failed and left-out stages. The command must
    run the same stages as the GitHub workflow, and as Azure DevOps when
    its infrastructure stage is on; with it off, Azure DevOps differs only
    after a failed Content Hub stage (MIGRATION.md edit E44).

    Then the command on its own.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/DeployWorkspace.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/DeployWorkspace.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-05
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+, powershell-yaml
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $PSScriptRoot '_helpers/WorkspaceStandIn.psm1') -Force
    $ado = Read-PipelineYaml -Path (Join-Path $repoRoot 'Pipelines/Sentinel-Deploy.yml')

    $adoDefaults = @{}
    foreach ($p in $ado.parameters) { $adoDefaults[$p.name] = $p.default }
    $defaultSolutions = @($adoDefaults.solutions -split ',' | ForEach-Object { $_.Trim() })
    $community = 'Content/AnalyticalRules/Community/*'
    $everyCustomType = @('Parser', 'AnalyticsRule', 'Watchlist', 'Playbook', 'Workbook', 'HuntingQuery', 'AutomationRule', 'SummaryRule')
    $everyHubType = @('AnalyticsRule', 'Workbook', 'AutomationRule', 'HuntingQuery')

    $defaultsModule = @{ Solution = $defaultSolutions; Severity = @('High', 'Medium', 'Low', 'Informational'); DisableRules = $true; Exclude = @($community); SmartDeployment = $true }
    $switchedModule = @{
        Solution = @('Azure Activity', 'Syslog'); Severity = @('High', 'Medium'); OverwriteCustomisedRules = $true; ForceSolutionUpdate = $true; ForceContentDeployment = $true
        ExcludeSolutionContentType = $everyHubType; ExcludeContentType = $everyCustomType; WhatIf = $true
    }
    $someModule = @{ Solution = $defaultSolutions; Severity = @('High', 'Medium', 'Low', 'Informational'); ExcludeContentType = @('Playbook'); Exclude = @($community); SmartDeployment = $true }

    # What the Content Hub, custom content and Defender steps gave the deploy
    # scripts for these cases on release/26.11.0, through MIGRATION.md's
    # Parameters table. Lists are sorted and joined with ', '.
    $script:cases = @(
        @{
            Case = 'the pipeline defaults'; Module = $defaultsModule
            Expected = @{
                HubName = $defaultSolutions; HubSeverity = 'High, Informational, Low, Medium'; HubDisableRules = $true; HubOverwriteCustomisedRules = $false
                HubForceSolutionUpdate = $false; HubForceContentDeployment = $false; HubExcludeContentType = ''
                CustomExcludeContentType = 'DefenderDetection, WorkspaceSetting'; CustomExclude = $community; CustomSmartDeployment = $true; WhatIf = $false
            }
        }
        @{
            Case = 'everything switched'; Module = $switchedModule
            Expected = @{
                HubName = @('Azure Activity', 'Syslog'); HubSeverity = 'High, Medium'; HubDisableRules = $false; HubOverwriteCustomisedRules = $true
                HubForceSolutionUpdate = $true; HubForceContentDeployment = $true; HubExcludeContentType = 'AnalyticsRule, AutomationRule, HuntingQuery, Workbook'
                CustomExcludeContentType = 'AnalyticsRule, AutomationRule, DefenderDetection, HuntingQuery, Parser, Playbook, SummaryRule, Watchlist, Workbook, WorkspaceSetting'
                CustomExclude = ''; CustomSmartDeployment = $false; WhatIf = $true
            }
        }
        @{
            Case = 'some content left out'; Module = $someModule
            Expected = @{
                HubName = $defaultSolutions; HubSeverity = 'High, Informational, Low, Medium'; HubDisableRules = $false; HubOverwriteCustomisedRules = $false
                HubForceSolutionUpdate = $false; HubForceContentDeployment = $false; HubExcludeContentType = ''
                CustomExcludeContentType = 'DefenderDetection, Playbook, WorkspaceSetting'; CustomExclude = $community; CustomSmartDeployment = $true; WhatIf = $false
            }
        }
    )

    $gated = @('ContentHub', 'CustomContent', 'DefenderDetections')
    $script:scenarios = foreach ($failMask in 0..7) {
        foreach ($excludeMask in 0..7) {
            @{
                Failed   = @(0..2 | Where-Object { $failMask -band (1 -shl $_) } | ForEach-Object { $gated[$_] })
                Excluded = @(0..2 | Where-Object { $excludeMask -band (1 -shl $_) } | ForEach-Object { $gated[$_] })
                Label    = "failing [$((@(0..2 | Where-Object { $failMask -band (1 -shl $_) } | ForEach-Object { $gated[$_] })) -join ', ')] leaving out [$((@(0..2 | Where-Object { $excludeMask -band (1 -shl $_) } | ForEach-Object { $gated[$_] })) -join ', ')]"
            }
        }
    }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '_helpers/WorkspaceStandIn.psm1') -Force
    $script:ado = Read-PipelineYaml -Path (Join-Path $script:repoRoot 'Pipelines/Sentinel-Deploy.yml')
    $script:gitHub = Read-PipelineYaml -Path (Join-Path $script:repoRoot '.github/workflows/sentinel-deploy.yml')
    $script:subscription = '11111111-2222-3333-4444-555555555555'
    $script:context = InModuleScope iSOCDeployments -Parameters @{ S = $script:subscription } {
        param($S)
        New-iSOCContext -Value @{
            TenantId = 'tenant-1'; SubscriptionId = $S; ResourceGroup = 'rg-sentinel'; WorkspaceName = 'law-sentinel'
            WorkspaceResourceId = "/subscriptions/$S/resourceGroups/rg-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-sentinel"
            WorkspaceId = 'cccccccc-0000-0000-0000-000000000001'; Region = 'uksouth'; PlaybookResourceGroup = 'rg-playbooks'
            Environment = 'AzureCloud'; IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'deployer@example.test'
        }
    }
    $script:repo = Join-Path $TestDrive 'repo'
    New-Item -ItemType Directory -Path (Join-Path $script:repo 'Content') -Force | Out-Null

    function Invoke-ModuleWorkspace {
        <# Run Deploy-iSOCWorkspace with every stage command stood in for; return what each was given. Stages named in $Fail fail. #>
        param([hashtable] $Parameters, [string[]] $Fail = @(), [switch] $Drift, [switch] $NoManifest)
        $script:calls = [System.Collections.Generic.List[object]]::new()
        $script:fail = @($Fail)
        $script:drift = [bool]$Drift
        $script:noManifest = [bool]$NoManifest
        $script:logs = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName iSOCDeployments Write-iSOCLog { $script:logs.Add([pscustomobject]@{ Message = $Message; Level = $Level }) }
        Mock -ModuleName iSOCDeployments Test-iSOCDependencyManifest { [pscustomobject]@{ Exists = -not $script:noManifest; HasDrift = $script:drift } }
        Mock -ModuleName iSOCDeployments Install-iSOCContentHubSolution {
            $script:calls.Add([pscustomobject]@{ Stage = 'ContentHub'; Given = $PesterBoundParameters })
            [pscustomobject]@{ ExitCode = $(if ($script:fail -contains 'ContentHub') { 1 } else { 0 }) }
        }
        Mock -ModuleName iSOCDeployments Deploy-iSOCContent {
            $stage = switch (@($ContentType)) { 'WorkspaceSetting' { 'WorkspaceSettings' } 'DefenderDetection' { 'DefenderDetections' } default { 'CustomContent' } }
            if (-not $ContentType) { $stage = 'CustomContent' }
            $script:calls.Add([pscustomobject]@{ Stage = $stage; Given = $PesterBoundParameters })
            [pscustomobject]@{ ExitCode = $(if ($script:fail -contains $stage) { 1 } else { 0 }) }
        }
        $run = Deploy-iSOCWorkspace @Parameters -Context $script:context -RepoPath $script:repo
        [pscustomobject]@{ Run = $run; Calls = $script:calls.ToArray(); Logs = $script:logs.ToArray() }
    }

    function Get-Given {
        <# What one stage command was given, or nothing when it was not called. #>
        param($Module, [string] $Stage)
        $call = @($Module.Calls | Where-Object { $_.Stage -eq $Stage })
        if ($call.Count -gt 1) { throw "$Stage was called $($call.Count) times." }
        if ($call.Count -eq 1) { $call[0].Given }
    }

    function Get-Sorted {
        <# A list's names, sorted and joined, so two lists compare whatever order or shape they came in. #>
        param($Value)
        (@($Value | Where-Object { $null -ne $_ -and [string]$_ -ne '' }) | Sort-Object) -join ', '
    }

    function Get-RunStage {
        <# The stages a pipeline would run, from its stage conditions, for a mix of failed and left-out stages. #>
        param([string] $Pipeline, [string[]] $Failed, [string[]] $Excluded, [bool] $DeployInfrastructure = $true)
        $result = @{ Infrastructure = 'Succeeded' }
        $ran = [System.Collections.Generic.List[string]]::new()
        foreach ($condition in Get-PipelineCondition -Pipeline $Pipeline) {
            $on = $Excluded -notcontains $condition.Stage
            $gateOk = $result[$condition.Gate] -in 'Succeeded', 'Skipped'
            $bypass = if ($condition.Bypass -eq 'deployInfrastructure') { -not $DeployInfrastructure } elseif ($condition.Bypass -eq 'deployCustomContent') { $Excluded -contains 'CustomContent' } else { $false }
            if ($on -and ($gateOk -or $bypass)) {
                $ran.Add($condition.Stage)
                $result[$condition.Stage] = if ($Failed -contains $condition.Stage) { 'Failed' } else { 'Succeeded' }
            }
            else { $result[$condition.Stage] = 'Skipped' }
        }
        , @($ran)
    }

    function Get-PipelineCondition {
        <# Each later stage's toggle and gate, read from the pipeline's conditions, which must keep the one shape this suite understands. #>
        param([string] $Pipeline)
        $stageOf = @{
            'deploy-infrastructure' = 'Infrastructure'; 'deploy-content-hub' = 'ContentHub'; 'deploy-custom-content' = 'CustomContent'; 'deploy-defender-detections' = 'DefenderDetections'
            DeployInfrastructure = 'Infrastructure'; DeployContentHub = 'ContentHub'; DeployCustomContent = 'CustomContent'; DeployDefenderDetections = 'DefenderDetections'
        }
        if ($Pipeline -eq 'GitHub Actions') {
            foreach ($job in 'deploy-content-hub', 'deploy-custom-content', 'deploy-defender-detections') {
                $text = ([string]$script:gitHub.jobs[$job]['if']) -replace '\s', ''
                if ($text -notmatch "^always\(\)&&\(inputs\.(?<toggle>\w+)!=false\)&&\(needs\.(?<gate>[\w-]+)\.result=='success'\|\|needs\.\k<gate>\.result=='skipped'\)$") {
                    throw "The $job job's condition has changed: $text"
                }
                [pscustomobject]@{ Stage = $stageOf[$job]; Toggle = $Matches.toggle; Gate = $stageOf[$Matches.gate]; Bypass = $null }
            }
            return
        }
        foreach ($name in 'DeployContentHub', 'DeployCustomContent', 'DeployDefenderDetections') {
            $stage = @($script:ado.stages | Where-Object { $_.stage -eq $name })[0]
            $text = ([string]$stage.condition) -replace '\s', ''
            if ($text -notmatch "^and\(eq\('\$\{\{parameters\.(?<toggle>\w+)\}\}','True'\),or\(eq\('\$\{\{parameters\.(?<bypass>\w+)\}\}','False'\),in\(dependencies\.(?<gate>\w+)\.result,'Succeeded','Skipped'\)\)\)$") {
                throw "The $name stage's condition has changed: $text"
            }
            [pscustomobject]@{ Stage = $stageOf[$name]; Toggle = $Matches.toggle; Gate = $stageOf[$Matches.gate]; Bypass = $Matches.bypass }
        }
    }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
    Remove-Module WorkspaceStandIn -ErrorAction SilentlyContinue
}

Describe 'Deploy-iSOCWorkspace gives each stage command its share of the run: <Case>' -ForEach $script:cases {
    BeforeAll {
        $script:module = Invoke-ModuleWorkspace -Parameters $Module
    }

    It 'gives the Content Hub stage the solutions, severities and switches' {
        $given = Get-Given $script:module 'ContentHub'
        $given | Should -Not -BeNullOrEmpty
        @($given.Name) | Should -Be @($Expected.HubName)
        Get-Sorted $given.Severity | Should -Be $Expected.HubSeverity
        [bool]$given.DisableRules | Should -Be $Expected.HubDisableRules
        [bool]$given.OverwriteCustomisedRules | Should -Be $Expected.HubOverwriteCustomisedRules
        [bool]$given.ForceSolutionUpdate | Should -Be $Expected.HubForceSolutionUpdate
        [bool]$given.ForceContentDeployment | Should -Be $Expected.HubForceContentDeployment
        Get-Sorted $given.ExcludeContentType | Should -Be $Expected.HubExcludeContentType
        [bool]$given.WhatIf | Should -Be $Expected.WhatIf
    }

    It 'gives the custom content stage the content types and paths it leaves out' {
        $given = Get-Given $script:module 'CustomContent'
        $given | Should -Not -BeNullOrEmpty
        Get-Sorted $given.ExcludeContentType | Should -Be $Expected.CustomExcludeContentType
        Get-Sorted $given.Exclude | Should -Be $Expected.CustomExclude
        [bool]$given.SmartDeployment | Should -Be $Expected.CustomSmartDeployment
        [bool]$given.WhatIf | Should -Be $Expected.WhatIf
    }

    It 'gives the Defender stage the run''s -WhatIf, smart deployment and exclusions' {
        $given = Get-Given $script:module 'DefenderDetections'
        $given | Should -Not -BeNullOrEmpty
        @($given.ContentType) | Should -Be @('DefenderDetection')
        [bool]$given.WhatIf | Should -Be $Expected.WhatIf
        [bool]$given.SmartDeployment | Should -Be ([bool]$Module.SmartDeployment)
        Get-Sorted $given.Exclude | Should -Be (Get-Sorted $Module.Exclude)
    }

    It 'deploys the workspace settings first, with the run''s smart deployment' {
        $script:module.Calls[0].Stage | Should -Be 'WorkspaceSettings'
        [bool]$script:module.Calls[0].Given.SmartDeployment | Should -Be ([bool]$Module.SmartDeployment)
        [bool]$script:module.Calls[0].Given.WhatIf | Should -Be ([bool]$Module.WhatIf)
    }
}

Describe 'The pipelines'' stage conditions' {
    It 'gate each stage on the one Deploy-iSOCWorkspace gates it on, in <Pipeline>' -ForEach @(@{ Pipeline = 'Azure DevOps' }, @{ Pipeline = 'GitHub Actions' }) {
        $gates = @{}
        foreach ($stage in InModuleScope iSOCDeployments { Get-iSOCWorkspaceStage }) { $gates[$stage.Name] = $stage.Gate }
        foreach ($condition in Get-PipelineCondition -Pipeline $Pipeline) {
            $expected = if ($condition.Gate -eq 'Infrastructure') { $null } else { $condition.Gate }
            $gates[$condition.Stage] | Should -Be $expected -Because "$Pipeline gates $($condition.Stage) on $($condition.Gate)"
        }
    }

    It 'are switched by the toggles -ExcludeStage stands for' {
        @(Get-PipelineCondition -Pipeline 'GitHub Actions' | ForEach-Object { $_.Toggle }) | Should -Be @('deploy_content_hub', 'deploy_custom_content', 'deploy_defender_detections')
        @(Get-PipelineCondition -Pipeline 'Azure DevOps' | ForEach-Object { $_.Toggle }) | Should -Be @('deployContentHub', 'deployCustomContent', 'deployDefenderDetections')
    }
}

Describe 'Deploy-iSOCWorkspace runs the stages the pipelines run, <Label>' -ForEach $script:scenarios {
    BeforeAll {
        $parameters = @{ Solution = @('Azure Activity') }
        if ($Excluded.Count) { $parameters.ExcludeStage = $Excluded }
        $script:module = Invoke-ModuleWorkspace -Parameters $parameters -Fail $Failed
        $script:ran = @($script:module.Run.Stages | Where-Object { $_.Stage -ne 'WorkspaceSettings' -and $_.Outcome -in 'Succeeded', 'Failed' } | ForEach-Object { $_.Stage })
    }

    It 'as the GitHub workflow does' {
        ($script:ran -join ', ') | Should -Be ((Get-RunStage -Pipeline 'GitHub Actions' -Failed $Failed -Excluded $Excluded) -join ', ')
    }

    It 'as Azure DevOps does with its infrastructure stage on' {
        ($script:ran -join ', ') | Should -Be ((Get-RunStage -Pipeline 'Azure DevOps' -Failed $Failed -Excluded $Excluded -DeployInfrastructure $true) -join ', ')
    }

    It 'as Azure DevOps does with it off, unless the Content Hub stage failed' {
        $adoOff = Get-RunStage -Pipeline 'Azure DevOps' -Failed $Failed -Excluded $Excluded -DeployInfrastructure $false
        $hubFailed = $Failed -contains 'ContentHub' -and $Excluded -notcontains 'ContentHub'
        if ($hubFailed -and $Excluded -notcontains 'CustomContent') { $adoOff | Should -Contain 'CustomContent'; $script:ran | Should -Not -Contain 'CustomContent' }
        else { ($script:ran -join ', ') | Should -Be ($adoOff -join ', ') }
    }

    It 'fails the run when a stage that ran failed' {
        $script:module.Run.ExitCode | Should -Be $(if (@($script:ran | Where-Object { $Failed -contains $_ }).Count) { 1 } else { 0 })
    }
}

Describe 'Deploy-iSOCWorkspace' {
    It 'needs -Solution for the Content Hub stage, and not without it' {
        { Invoke-ModuleWorkspace -Parameters @{} } | Should -Throw '*The ContentHub stage needs -Solution*'
        { Invoke-ModuleWorkspace -Parameters @{ Solution = @(' ', '') } } | Should -Throw '*needs -Solution*'
        $run = Invoke-ModuleWorkspace -Parameters @{ ExcludeStage = @('ContentHub') }
        $run.Run.ExitCode | Should -Be 0
        @($run.Calls | Where-Object Stage -eq 'ContentHub') | Should -BeNullOrEmpty
    }

    It 'trims the solution names' {
        $run = Invoke-ModuleWorkspace -Parameters @{ Solution = @(' Azure Activity ', 'Syslog') }
        @((Get-Given $run 'ContentHub').Name) | Should -Be @('Azure Activity', 'Syslog')
    }

    It 'runs only the stages -Stage names, in their order' {
        $run = Invoke-ModuleWorkspace -Parameters @{ Stage = @('DefenderDetections', 'WorkspaceSettings') }
        @($run.Calls | ForEach-Object { $_.Stage }) | Should -Be @('WorkspaceSettings', 'DefenderDetections')
        @($run.Run.Stages | ForEach-Object { $_.Outcome }) | Should -Be @('Succeeded', 'Excluded', 'Excluded', 'Succeeded')
    }

    It 'refuses to deploy custom content against a stale manifest, and holds back the Defender detections' {
        $run = Invoke-ModuleWorkspace -Parameters @{ Solution = @('Syslog') } -Drift
        @($run.Calls | ForEach-Object { $_.Stage }) | Should -Be @('WorkspaceSettings', 'ContentHub')
        $custom = @($run.Run.Stages | Where-Object Stage -eq 'CustomContent')[0]
        $custom.Outcome | Should -Be 'Failed'
        $custom.Reason | Should -Be 'dependencies.json is out of sync with the content'
        @($run.Run.Stages | Where-Object Stage -eq 'DefenderDetections')[0].Outcome | Should -Be 'NotRun'
        @($run.Logs | Where-Object { $_.Level -eq 'Error' -and $_.Message -like 'dependencies.json is out of sync*' }).Count | Should -Be 1
        $run.Run.ExitCode | Should -Be 1
    }

    It 'refuses to deploy custom content without a manifest' {
        $run = Invoke-ModuleWorkspace -Parameters @{ Stage = @('CustomContent', 'DefenderDetections') } -NoManifest
        @($run.Calls | ForEach-Object { $_.Stage }) | Should -BeNullOrEmpty
        @($run.Run.Stages | ForEach-Object { $_.Outcome }) | Should -Be @('Excluded', 'Excluded', 'Failed', 'NotRun')
    }

    It 'checks the manifest of the repository it deploys' {
        Invoke-ModuleWorkspace -Parameters @{ Stage = @('CustomContent') } | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Test-iSOCDependencyManifest -Times 1 -Exactly -ParameterFilter { $RepoPath -eq $script:repo }
    }

    It 'fails a stage whose command throws, and goes on' {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Test-iSOCDependencyManifest { [pscustomobject]@{ Exists = $true; HasDrift = $false } }
        Mock -ModuleName iSOCDeployments Install-iSOCContentHubSolution { throw 'The workspace is not onboarded.' }
        Mock -ModuleName iSOCDeployments Deploy-iSOCContent { [pscustomobject]@{ ExitCode = 0 } }
        $run = Deploy-iSOCWorkspace -Solution 'Syslog' -Context $script:context -RepoPath $script:repo
        $hub = @($run.Stages | Where-Object Stage -eq 'ContentHub')[0]
        $hub.Outcome | Should -Be 'Failed'
        $hub.Reason | Should -Be 'The workspace is not onboarded.'
        @($run.Stages | ForEach-Object { $_.Outcome }) | Should -Be @('Succeeded', 'Failed', 'NotRun', 'Succeeded')
        $run.Failed | Should -Be 1
        $run.ExitCode | Should -Be 1
    }

    It 'lets a failed workspace settings stage hold back nothing' {
        $run = Invoke-ModuleWorkspace -Parameters @{ Solution = @('Syslog') } -Fail 'WorkspaceSettings'
        @($run.Run.Stages | ForEach-Object { $_.Outcome }) | Should -Be @('Failed', 'Succeeded', 'Succeeded', 'Succeeded')
        $run.Run.ExitCode | Should -Be 1
    }

    It 'passes -WhatIf to every stage command' {
        $run = Invoke-ModuleWorkspace -Parameters @{ Solution = @('Syslog'); WhatIf = $true }
        $run.Calls.Count | Should -Be 4
        foreach ($call in $run.Calls) { [bool]$call.Given.WhatIf | Should -BeTrue -Because $call.Stage }
    }

    It 'returns the stages and their results' {
        $run = Invoke-ModuleWorkspace -Parameters @{ Solution = @('Syslog') } -Fail 'CustomContent'
        $run.Run.PSObject.TypeNames | Should -Contain 'iSOCDeployments.WorkspaceDeployRun'
        @($run.Run.Stages | ForEach-Object { $_.Stage }) | Should -Be @('WorkspaceSettings', 'ContentHub', 'CustomContent', 'DefenderDetections')
        foreach ($stage in $run.Run.Stages) { $stage.PSObject.TypeNames | Should -Contain 'iSOCDeployments.StageResult' }
        @($run.Run.Stages | Where-Object Stage -eq 'CustomContent')[0].Run.ExitCode | Should -Be 1
        $run.Run.Duration | Should -BeOfType [timespan]
    }

    It 'logs nothing that names the subscription' {
        $run = Invoke-ModuleWorkspace -Parameters @{ Solution = @('Syslog') } -Fail 'ContentHub'
        @($run.Logs | Where-Object { $_.Message -like "*$script:subscription*" }) | Should -BeNullOrEmpty
        @($run.Logs | Where-Object { $_.Level -eq 'Warning' -and $_.Message -like 'Not deploying custom content: the ContentHub stage failed.' }).Count | Should -Be 1
    }
}
