#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for Deploy-iSOCWorkspace, against the stage sequence of
    the deploy pipelines.

.DESCRIPTION
    Two kinds of parity, then the command on its own.

    What each stage is given: the Content Hub, custom content and Defender
    steps of Pipelines/Sentinel-Deploy.yml and
    .github/workflows/sentinel-deploy.yml are lifted out of the YAML
    unchanged, filled in from the pipelines' own parameter and input
    defaults (or a case's), and run in a child pwsh against stand-in
    scripts that have the real scripts' parameters and record what they
    were given. Deploy-iSOCWorkspace, called as the pipeline would call it
    for the same case, must give the module's commands the same, through
    the map MIGRATION.md's Parameters table lists.

    Which stages run: the pipelines' stage conditions are read from the
    YAML, held to the one shape the suite understands, and evaluated for
    every mix of failed and left-out stages. The command must run the same
    stages as the GitHub workflow, and as Azure DevOps when its
    infrastructure stage is on; with it off, Azure DevOps differs only
    after a failed Content Hub stage (MIGRATION.md edit E44).

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/DeployWorkspace.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/DeployWorkspace.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-05
    Version:      0.1.0
    Last Updated: 2026-11-05
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $PSScriptRoot '_helpers/WorkspaceStandIn.psm1') -Force
    $ado = Read-PipelineYaml -Path (Join-Path $repoRoot 'Pipelines/Sentinel-Deploy.yml')
    $gitHub = Read-PipelineYaml -Path (Join-Path $repoRoot '.github/workflows/sentinel-deploy.yml')

    $adoDefaults = @{}
    foreach ($p in $ado.parameters) { $adoDefaults[$p.name] = $p.default }
    $gitHubDefaults = @{}
    foreach ($name in $gitHub.on.workflow_dispatch.inputs.Keys) {
        $default = $gitHub.on.workflow_dispatch.inputs[$name].default
        $gitHubDefaults[$name] = if ($default -is [bool]) { $default.ToString().ToLower() } else { [string]$default }
    }
    $gitHubBlank = @{}
    foreach ($name in $gitHubDefaults.Keys) { $gitHubBlank[$name] = '' }
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

    $adoSwitched = $adoDefaults.Clone()
    foreach ($k in @($adoSwitched.Keys)) { if ($k -like 'skip*') { $adoSwitched[$k] = $true } }
    $adoSwitched.skipCommunityDetections = $false
    $adoSwitched.disableRules = $false; $adoSwitched.protectCustomisedRules = $false; $adoSwitched.forceSolutionUpdate = $true; $adoSwitched.forceContentDeployment = $true
    $adoSwitched.smartDeployment = $false; $adoSwitched.whatIf = $true; $adoSwitched.solutions = 'Azure Activity, Syslog'; $adoSwitched.severitiesToInclude = 'High,Medium'
    $adoSome = $adoDefaults.Clone()
    $adoSome.skipCustomPlaybooks = $true; $adoSome.disableRules = $false

    $gitHubSwitched = $gitHubDefaults.Clone()
    foreach ($k in 'skip_analytics_rules', 'skip_workbooks', 'skip_automation_rules', 'skip_hunting_queries', 'force_solution_update', 'force_content_deployment', 'what_if') { $gitHubSwitched[$k] = 'true' }
    foreach ($k in 'disable_rules', 'protect_customised_rules', 'smart_deployment') { $gitHubSwitched[$k] = 'false' }
    $gitHubSwitched.skip_custom_content_types = 'parsers,detections,watchlists,playbooks,workbooks,hunting-queries,automation-rules,summary-rules'
    $gitHubSwitched.solutions = 'Azure Activity, Syslog'; $gitHubSwitched.severities_to_include = 'High,Medium'
    $gitHubSome = $gitHubDefaults.Clone()
    $gitHubSome.skip_custom_content_types = ' Playbooks , community-detections '; $gitHubSome.disable_rules = 'false'

    $script:cases = @(
        @{ Case = 'the parameter defaults'; Pipeline = 'Azure DevOps'; Inputs = $adoDefaults; Module = $defaultsModule }
        @{ Case = 'everything switched'; Pipeline = 'Azure DevOps'; Inputs = $adoSwitched; Module = $switchedModule }
        @{ Case = 'some content left out'; Pipeline = 'Azure DevOps'; Inputs = $adoSome; Module = $someModule }
        @{ Case = 'the input defaults'; Pipeline = 'GitHub Actions'; Inputs = $gitHubDefaults; Module = $defaultsModule }
        @{ Case = 'a scheduled run, with no inputs'; Pipeline = 'GitHub Actions'; Inputs = $gitHubBlank; Module = $defaultsModule }
        @{ Case = 'everything switched'; Pipeline = 'GitHub Actions'; Inputs = $gitHubSwitched; Module = $switchedModule }
        @{ Case = 'some content left out'; Pipeline = 'GitHub Actions'; Inputs = $gitHubSome; Module = $someModule }
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
    $script:files = @{ 'Azure DevOps' = Join-Path $script:repoRoot 'Pipelines/Sentinel-Deploy.yml'; 'GitHub Actions' = Join-Path $script:repoRoot '.github/workflows/sentinel-deploy.yml' }
    $script:ado = Read-PipelineYaml -Path $script:files['Azure DevOps']
    $script:gitHub = Read-PipelineYaml -Path $script:files['GitHub Actions']
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

    # The script parameters the pipelines pass, as the module's commands take them.
    $script:hubSkips = [ordered]@{ SkipSolutionDeployment = 'Solution'; SkipAnalyticsRules = 'AnalyticsRule'; SkipWorkbooks = 'Workbook'; SkipAutomationRules = 'AutomationRule'; SkipHuntingQueries = 'HuntingQuery' }
    $script:customSkips = [ordered]@{
        SkipParsers = 'Parser'; SkipDetections = 'AnalyticsRule'; SkipWatchlists = 'Watchlist'; SkipPlaybooks = 'Playbook'; SkipWorkbooks = 'Workbook'
        SkipHuntingQueries = 'HuntingQuery'; SkipAutomationRules = 'AutomationRule'; SkipSummaryRules = 'SummaryRule'
    }

    function Get-StubScript {
        <# A stand-in for one deploy script: the real script's parameters, recording what it was given beside itself. #>
        param([string] $Name)
        $real = Join-Path $script:repoRoot "Deploy/content/$Name.ps1"
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($real, [ref]$null, [ref]$null)
        $attributes = @($ast.ParamBlock.Attributes | ForEach-Object { $_.Extent.Text }) -join "`n"
        @"
$attributes
$($ast.ParamBlock.Extent.Text)
`$record = [ordered]@{}
foreach (`$key in `$PSBoundParameters.Keys) {
    `$value = `$PSBoundParameters[`$key]
    `$record[`$key] = if (`$value -is [System.Management.Automation.SwitchParameter]) { `$value.IsPresent } else { `$value }
}
`$record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path `$PSScriptRoot '$Name.call.json')
"@
    }
    $script:stubs = @{}
    foreach ($name in 'Deploy-SentinelContentHub', 'Deploy-CustomContent', 'Deploy-DefenderDetections') { $script:stubs[$name] = Get-StubScript -Name $name }

    function Get-PipelineVariable {
        <# Every pipeline variable the stage steps read, for one case's parameters (Azure DevOps) or inputs (GitHub). #>
        param([string] $Pipeline, [hashtable] $Inputs, [string] $Root)
        $values = @{
            azureSubscriptionId = $script:subscription; sentinelResourceGroup = 'rg-sentinel'; sentinelWorkspaceName = 'law-sentinel'
            sentinelRegion = 'uksouth'; playbookResourceGroup = 'rg-playbooks'; 'Build.SourcesDirectory' = $Root
            AZURE_SUBSCRIPTION_ID = $script:subscription; RESOURCE_GROUP = 'rg-sentinel'; WORKSPACE_NAME = 'law-sentinel'; REGION = 'uksouth'
            PLAYBOOK_RESOURCE_GROUP = 'rg-playbooks'; workspace = $Root
        }
        if ($Pipeline -eq 'GitHub Actions') {
            foreach ($name in $Inputs.Keys) { $values[$name] = $Inputs[$name] }
            return $values
        }
        $values.solutions = [string]$Inputs.solutions
        $values.severitiesToInclude = [string]$Inputs.severitiesToInclude
        # The flag variables, as the variables section's template expressions set them.
        foreach ($variable in @($script:ado.variables | Where-Object { $_ -is [System.Collections.IDictionary] -and [string]$_['name'] -like 'flag*' })) {
            $ifKey = @($variable.Keys | Where-Object { $_ -like '${{ if *' })
            if ($ifKey.Count -ne 1 -or $ifKey[0] -notmatch '^\$\{\{ if eq\(parameters\.(\w+), true\) \}\}$' -or -not $variable.Contains('${{ else }}')) {
                throw "The variable $($variable.name) is not a parameter flag the suite understands."
            }
            $values[$variable.name] = if ($Inputs[$Matches[1]] -eq $true) { $variable[$ifKey[0]].value } else { $variable['${{ else }}'].value }
        }
        $values
    }

    function Invoke-PipelineStage {
        <# Run one stage step unchanged in a child pwsh against the stand-in scripts; return what each script was given. #>
        param([string] $Pipeline, [string] $Step, [hashtable] $Inputs)
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path (Join-Path $root 'Deploy/content') -Force | Out-Null
        foreach ($name in $script:stubs.Keys) { Set-Content -LiteralPath (Join-Path $root "Deploy/content/$name.ps1") -Value $script:stubs[$name] }
        $inline = Get-PipelineInlineScript -Path $script:files[$Pipeline] -Step $Step -Variables (Get-PipelineVariable -Pipeline $Pipeline -Inputs $Inputs -Root $root)
        $runPath = Join-Path $root 'run.ps1'
        Set-Content -LiteralPath $runPath -Value "`$ErrorActionPreference = 'Stop'`n$inline" -Encoding utf8NoBOM
        $lines = @(& pwsh -NoProfile -NonInteractive -File $runPath 2>&1 | ForEach-Object { "$_" })
        if ($LASTEXITCODE -ne 0) { throw "The $Step step failed: $($lines -join ' | ')" }
        $calls = @{}
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'Deploy/content') -Filter '*.call.json') {
            $calls[$file.Name -replace '\.call\.json$', ''] = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable
        }
        [pscustomobject]@{ Calls = $calls; Root = $root }
    }

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

Describe 'Deploy-iSOCWorkspace beside the <Pipeline> stage steps: <Case>' -ForEach $script:cases {
    BeforeAll {
        $script:hub = (Invoke-PipelineStage -Pipeline $Pipeline -Step 'Deploy Content Hub Solutions' -Inputs $Inputs).Calls['Deploy-SentinelContentHub']
        $script:customRun = Invoke-PipelineStage -Pipeline $Pipeline -Step 'Deploy Custom Content' -Inputs $Inputs
        $script:custom = $script:customRun.Calls['Deploy-CustomContent']
        $script:defender = (Invoke-PipelineStage -Pipeline $Pipeline -Step 'Deploy Defender Custom Detections' -Inputs $Inputs).Calls['Deploy-DefenderDetections']
        $script:module = Invoke-ModuleWorkspace -Parameters $Module
    }

    It 'runs each pipeline step to its script' {
        $script:hub | Should -Not -BeNullOrEmpty
        $script:custom | Should -Not -BeNullOrEmpty
        $script:defender | Should -Not -BeNullOrEmpty
    }

    It 'gives the Content Hub stage what the step gives Deploy-SentinelContentHub.ps1' {
        $given = Get-Given $script:module 'ContentHub'
        $given | Should -Not -BeNullOrEmpty
        @($given.Name) | Should -Be @($script:hub.Solutions)
        Get-Sorted $given.Severity | Should -Be (Get-Sorted $script:hub.SeveritiesToInclude)
        [bool]$given.DisableRules | Should -Be ([bool]$script:hub.DisableRules)
        $protect = if ($script:hub.Contains('ProtectCustomisedRules')) { [bool]$script:hub.ProtectCustomisedRules } else { $true }
        [bool]$given.OverwriteCustomisedRules | Should -Be (-not $protect)
        [bool]$given.ForceSolutionUpdate | Should -Be ([bool]$script:hub.ForceSolutionUpdate)
        [bool]$given.ForceContentDeployment | Should -Be ([bool]$script:hub.ForceContentDeployment)
        $skips = @($script:hubSkips.Keys | Where-Object { $script:hub[$_] -eq $true } | ForEach-Object { $script:hubSkips[$_] })
        Get-Sorted $given.ExcludeContentType | Should -Be (Get-Sorted $skips)
        [bool]$given.WhatIf | Should -Be ([bool]$script:hub.WhatIf)
    }

    It 'gives the custom content stage what the step gives Deploy-CustomContent.ps1' {
        $given = Get-Given $script:module 'CustomContent'
        $given | Should -Not -BeNullOrEmpty
        $skips = @($script:customSkips.Keys | Where-Object { $script:custom[$_] -eq $true } | ForEach-Object { $script:customSkips[$_] })
        Get-Sorted $given.ExcludeContentType | Should -Be (Get-Sorted ($skips + 'WorkspaceSetting', 'DefenderDetection'))
        $exclude = if ($script:custom.SkipCommunityDetections -eq $true) { @('Content/AnalyticalRules/Community/*') } else { @() }
        Get-Sorted $given.Exclude | Should -Be (Get-Sorted $exclude)
        [bool]$given.SmartDeployment | Should -Be ([bool]$script:custom.SmartDeployment)
        [bool]$given.WhatIf | Should -Be ([bool]$script:custom.WhatIf)
    }

    It 'gives the Defender stage the step''s -WhatIf, and the run''s smart deployment and exclusions' {
        $given = Get-Given $script:module 'DefenderDetections'
        $given | Should -Not -BeNullOrEmpty
        @($given.ContentType) | Should -Be @('DefenderDetection')
        [bool]$given.WhatIf | Should -Be ([bool]$script:defender.WhatIf)
        [bool]$given.SmartDeployment | Should -Be ([bool]$Module.SmartDeployment)
        Get-Sorted $given.Exclude | Should -Be (Get-Sorted $Module.Exclude)
    }

    It 'deploys the workspace settings first, with the run''s smart deployment' {
        $script:module.Calls[0].Stage | Should -Be 'WorkspaceSettings'
        [bool]$script:module.Calls[0].Given.SmartDeployment | Should -Be ([bool]$Module.SmartDeployment)
        [bool]$script:module.Calls[0].Given.WhatIf | Should -Be ([bool]$Module.WhatIf)
    }

    It 'connects to what the steps name' {
        foreach ($call in $script:hub, $script:custom) {
            $call.ResourceGroup | Should -Be $script:context.ResourceGroup
            $call.Workspace | Should -Be $script:context.WorkspaceName
            $call.SubscriptionId | Should -Be $script:context.SubscriptionId
            $call.Region | Should -Be $script:context.Region
        }
        $script:custom.PlaybookResourceGroup | Should -Be $script:context.PlaybookResourceGroup
        $script:custom.BasePath | Should -Be $script:customRun.Root
        $script:defender.BasePath | Should -Not -BeNullOrEmpty
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
