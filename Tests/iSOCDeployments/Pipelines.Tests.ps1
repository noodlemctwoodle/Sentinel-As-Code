#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the pipeline switch: the pipelines' engine parameter
    and the steps that run the iSOCDeployments module.

.DESCRIPTION
    Each pipeline that has moved to the module takes an engine parameter:
    scripts (the default until sign-off), module, or compare, which runs
    both and fails on a difference. For each engine the suite reads the
    steps the pipeline would run (the ${{ if }} insertions evaluated), so
    it checks which engine a run uses, that the module's steps may not set
    variables or change PATH, and that the bot commit step runs only from
    main, stages only its own file and takes its runtime variables through
    env rather than as macros.

    Then it runs the steps: each step's inline PowerShell is lifted out of
    the YAML unchanged and run in a child pwsh, with the variables the
    agent sets, against a copy of the fixture repository holding the
    script, Modules/Sentinel.Common and the module, as a checkout does. The
    module's step must leave the repository as the script's step does, and
    a compare step must pass when the two agree and fail, naming the edit
    that explains it, when they do not.

    So far: the dependency manifest, in Pipelines/Sentinel-Dependency-Update.yml
    and the manifest gate of Pipelines/Sentinel-PR-Validation.yml.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Pipelines.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Pipelines.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-05
    Version:      0.1.0
    Last Updated: 2026-11-05
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml, git
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $PSScriptRoot '_helpers/WorkspaceStandIn.psm1') -Force
    $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'
    $script:updatePipeline = Join-Path $script:repoRoot 'Pipelines/Sentinel-Dependency-Update.yml'
    $script:gatePipeline = Join-Path $script:repoRoot 'Pipelines/Sentinel-PR-Validation.yml'

    # A checkout as the agent has it: the fixture content, the script with
    # Sentinel.Common beside it, and the module. Without -WithYml the one
    # .yml rule goes, so the two engines read the same files (E8).
    function Build-PipelineCheckout {
        param([switch] $WithYml)
        $checkout = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $checkout 'Tools'), (Join-Path $checkout 'Modules') | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:fixtureRepo 'Content') -Destination $checkout -Recurse
        if (-not $WithYml) { Get-ChildItem -LiteralPath (Join-Path $checkout 'Content') -Recurse -Filter '*.yml' | Remove-Item }
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'Tools/Build-DependencyManifest.ps1') -Destination (Join-Path $checkout 'Tools')
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'Modules/Sentinel.Common') -Destination (Join-Path $checkout 'Modules') -Recurse
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'Modules/iSOCDeployments') -Destination (Join-Path $checkout 'Modules') -Recurse
        $checkout
    }

    # Run a step's script in a child pwsh with the variables the agent
    # sets for it, as the agent runs it.
    function Invoke-PipelineStep {
        param([string] $Script, [string] $Checkout)
        $temp = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $temp | Out-Null
        $file = Join-Path $temp 'step.ps1'
        Set-Content -LiteralPath $file -Value $Script -Encoding utf8
        $environment = @{ BUILD_SOURCESDIRECTORY = $Checkout; AGENT_TEMPDIRECTORY = $temp; TF_BUILD = 'True' }
        $saved = @{}
        foreach ($name in $environment.Keys) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $environment[$name])
        }
        try {
            $output = & pwsh -NoProfile -NonInteractive -File $file 2>&1 | ForEach-Object { "$_" -replace '\x1b\[[0-9;]*m', '' }
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
        }
        finally {
            foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
        }
    }

    function Get-StepText {
        param([System.Collections.IDictionary] $Step)
        if ($Step.Contains('inputs') -and $Step.inputs.Contains('script')) { return [string]$Step.inputs.script }
        if ($Step.Contains('bash')) { return [string]$Step.bash }
        ''
    }

    function Get-ManifestHash {
        param([string] $Checkout)
        (Get-FileHash -LiteralPath (Join-Path $Checkout 'dependencies.json')).Hash
    }

    $script:moduleStepRule = {
        param([System.Collections.IDictionary] $Step)
        $Step.Contains('target') -and $Step.target.commands -eq 'restricted' -and $Step.target.settableVariables -eq 'none'
    }
}

AfterAll {
    Remove-Module WorkspaceStandIn -ErrorAction SilentlyContinue
}

Describe 'Pipelines/Sentinel-Dependency-Update.yml' {
    BeforeAll {
        $script:updateSteps = @{}
        foreach ($engine in 'scripts', 'module', 'compare') {
            $script:updateSteps[$engine] = @(Get-PipelineStep -Path $script:updatePipeline -Parameters @{ engine = $engine })
        }
        $script:commitName = 'Commit, Push, and Open PR (when drift detected)'
    }

    Context 'Engines' {
        It 'takes an engine of scripts, module or compare, scripts by default' {
            $parameter = @((Read-PipelineYaml -Path $script:updatePipeline).parameters | Where-Object { $_.name -eq 'engine' })
            $parameter.Count | Should -Be 1
            $parameter[0].type | Should -Be 'string'
            $parameter[0].default | Should -Be 'scripts'
            @($parameter[0].values) -join ',' | Should -Be 'scripts,module,compare'
        }

        It 'runs <Steps> with engine <Engine>' -ForEach @(
            @{ Engine = 'scripts'; Steps = 'Install powershell-yaml Module|Run dependency-manifest update|Commit, Push, and Open PR (when drift detected)' }
            @{ Engine = 'module'; Steps = 'Install powershell-yaml Module|Update the dependency manifest (iSOCDeployments)|Commit, Push, and Open PR (when drift detected)' }
            @{ Engine = 'compare'; Steps = 'Install powershell-yaml Module|Run dependency-manifest update|Compare the scripts and the module (iSOCDeployments)|Commit, Push, and Open PR (when drift detected)' }
        ) {
            (@($script:updateSteps[$Engine] | Where-Object { $_.displayName } | ForEach-Object { $_.displayName }) -join '|') | Should -BeExactly $Steps
        }

        It 'runs nothing from the module with engine scripts' {
            @($script:updateSteps.scripts | Where-Object { (Get-StepText $_) -match 'iSOCDeployments' }).Count | Should -Be 0
        }

        It 'runs nothing from the script with engine module' {
            @($script:updateSteps.module | Where-Object { (Get-StepText $_) -match 'Build-DependencyManifest\.ps1' }).Count | Should -Be 0
        }

        It 'lets no step that runs the module set a variable or change PATH, with engine <_>' -ForEach @('module', 'compare') {
            $moduleSteps = @($script:updateSteps[$_] | Where-Object { (Get-StepText $_) -match 'iSOCDeployments\.psd1' })
            $moduleSteps.Count | Should -Be 1
            & $script:moduleStepRule $moduleSteps[0] | Should -BeTrue
        }

        It 'commits through the same step with every engine' {
            $texts = foreach ($engine in 'scripts', 'module', 'compare') { Get-StepText @($script:updateSteps[$engine] | Where-Object { $_.displayName -eq $script:commitName })[0] }
            @($texts | Select-Object -Unique).Count | Should -Be 1
        }

        It 'names <Command> in the commit with engine <Engine>' -ForEach @(
            @{ Engine = 'scripts'; Command = 'Tools/Build-DependencyManifest.ps1 -Mode Generate' }
            @{ Engine = 'module'; Command = 'Update-iSOCDependencyManifest (Modules/iSOCDeployments)' }
            @{ Engine = 'compare'; Command = 'Tools/Build-DependencyManifest.ps1 -Mode Generate' }
        ) {
            $yaml = Read-PipelineYaml -Path $script:updatePipeline
            $values = Resolve-PipelineParameter -Yaml $yaml -Parameters @{ engine = $Engine }
            $variable = @($yaml.variables | Where-Object { $_.name -eq 'manifestCommand' })[0]
            $branch = @($variable.Keys | Where-Object { $_ -match '^\$\{\{\s*if\s+(.+?)\s*\}\}$' })[0]
            $condition = [regex]::Match($branch, '^\$\{\{\s*if\s+(.+?)\s*\}\}$').Groups[1].Value
            $value = if (Test-PipelineCondition -Condition $condition -Values $values) { $variable[$branch].value } else { $variable['${{ else }}'].value }
            $value | Should -BeExactly $Command
        }
    }

    Context 'The commit step' {
        BeforeAll {
            $script:commitStep = @($script:updateSteps.module | Where-Object { $_.displayName -eq $script:commitName })[0]
            $script:commitText = Get-StepText $script:commitStep
        }

        It 'runs only from main' {
            ($script:commitStep.condition -replace '\s', '') | Should -BeExactly "and(succeeded(),eq(variables['Build.SourceBranch'],'refs/heads/main'))"
        }

        It 'stages only dependencies.json' {
            @([regex]::Matches($script:commitText, '(?m)^\s*git add .*$') | ForEach-Object { $_.Value.Trim() }) -join '|' | Should -BeExactly 'git add dependencies.json'
        }

        It 'takes <Variable> through env, not as a macro in its text' -ForEach @(
            @{ Variable = 'syncBranch'; Env = 'SYNC_BRANCH' }
            @{ Variable = 'targetBranch'; Env = 'TARGET_BRANCH' }
            @{ Variable = 'flagReportOnly'; Env = 'REPORT_ONLY' }
            @{ Variable = 'manifestCommand'; Env = 'MANIFEST_COMMAND' }
        ) {
            $script:commitText | Should -Not -Match ([regex]::Escape("`$($Variable)"))
            $script:commitStep.env[$Env] | Should -BeExactly "`$($Variable)"
        }
    }

    Context 'The steps, run' {
        BeforeAll {
            $script:scriptsStep = Get-PipelineInlineScript -Path $script:updatePipeline -Step 'Run dependency-manifest update' -Parameters @{ engine = 'scripts' } -Variables @{ 'Build.SourcesDirectory' = '__CHECKOUT__' }
            $script:moduleStep = Get-PipelineInlineScript -Path $script:updatePipeline -Step 'Update the dependency manifest (iSOCDeployments)' -Parameters @{ engine = 'module' } -Variables @{}
            $script:compareStep = Get-PipelineInlineScript -Path $script:updatePipeline -Step 'Compare the scripts and the module (iSOCDeployments)' -Parameters @{ engine = 'compare' } -Variables @{}
        }

        It 'puts no macro in the module steps' {
            $script:moduleStep | Should -Not -Match '\$\([A-Za-z.]+\)'
            $script:compareStep | Should -Not -Match '\$\([A-Za-z.]+\)'
        }

        It 'writes the manifest the script writes, when <Case>' -ForEach @(
            @{ Case = 'there is none'; Prepare = { param($Path) Remove-Item -LiteralPath (Join-Path $Path 'dependencies.json') -ErrorAction SilentlyContinue } }
            @{ Case = 'an entry is missing'; Prepare = {
                    param($Path)
                    $manifest = Get-Content -LiteralPath (Join-Path $Path 'dependencies.json') -Raw | ConvertFrom-Json -AsHashtable
                    $manifest.dependencies.Remove(@($manifest.dependencies.Keys | Sort-Object)[0])
                    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Path 'dependencies.json')
                }
            }
        ) {
            $byScripts = Build-PipelineCheckout
            $byModule = Build-PipelineCheckout
            foreach ($checkout in $byScripts, $byModule) {
                (Invoke-PipelineStep -Script $script:moduleStep -Checkout $checkout).ExitCode | Should -Be 0
                & $Prepare $checkout
            }

            $scripts = Invoke-PipelineStep -Script $script:scriptsStep.Replace('__CHECKOUT__', $byScripts) -Checkout $byScripts
            $module = Invoke-PipelineStep -Script $script:moduleStep -Checkout $byModule
            $scripts.ExitCode | Should -Be 0 -Because $scripts.Output
            $module.ExitCode | Should -Be 0 -Because $module.Output
            Get-ManifestHash $byModule | Should -BeExactly (Get-ManifestHash $byScripts)
            $module.Output | Should -Match 'dependencies\.json: 4 entries, written\.'
        }

        It 'leaves a current manifest alone, as the script does' {
            $checkout = Build-PipelineCheckout
            (Invoke-PipelineStep -Script $script:moduleStep -Checkout $checkout).ExitCode | Should -Be 0
            $before = Get-ManifestHash $checkout
            $module = Invoke-PipelineStep -Script $script:moduleStep -Checkout $checkout
            $scripts = Invoke-PipelineStep -Script $script:scriptsStep.Replace('__CHECKOUT__', $checkout) -Checkout $checkout
            $module.ExitCode | Should -Be 0
            $scripts.ExitCode | Should -Be 0
            $module.Output | Should -Match 'dependencies\.json: 4 entries, already current\.'
            Get-ManifestHash $checkout | Should -BeExactly $before
        }

        It 'compares the engines and passes when they write the same bytes' {
            $checkout = Build-PipelineCheckout
            $run = Invoke-PipelineStep -Script $script:compareStep -Checkout $checkout
            $run.ExitCode | Should -Be 0 -Because $run.Output
            $run.Output | Should -Match 'The scripts and the module wrote the same dependencies\.json'
            Test-Path -LiteralPath (Join-Path $checkout 'dependencies.json') | Should -BeFalse -Because 'the comparison writes only to the agent''s temporary folder'
        }

        It 'fails the comparison, naming edit E8, when the module reads a .yml rule the script does not' {
            $checkout = Build-PipelineCheckout -WithYml
            $run = Invoke-PipelineStep -Script $script:compareStep -Checkout $checkout
            $run.ExitCode | Should -Be 1
            $run.Output | Should -Match ([regex]::Escape('##vso[task.logissue type=error]The module wrote a different dependencies.json'))
            $run.Output | Should -Match 'E8'
            $run.Output | Should -Match 'CommunityRule\.yml'
        }
    }
}

Describe 'Pipelines/Sentinel-PR-Validation.yml' {
    BeforeAll {
        $script:gateSteps = @{}
        foreach ($engine in 'scripts', 'module', 'compare') {
            $script:gateSteps[$engine] = @(Get-PipelineStep -Path $script:gatePipeline -Parameters @{ engine = $engine })
        }
        $script:gateNames = @{
            scripts = 'Verify dependency manifest'
            module  = 'Verify dependency manifest (iSOCDeployments)'
            compare = 'Verify dependency manifest (compare the scripts and iSOCDeployments)'
        }
    }

    Context 'Engines' {
        It 'takes an engine of scripts, module or compare, scripts by default' {
            $parameter = @((Read-PipelineYaml -Path $script:gatePipeline).parameters | Where-Object { $_.name -eq 'engine' })
            $parameter.Count | Should -Be 1
            $parameter[0].default | Should -Be 'scripts'
            @($parameter[0].values) -join ',' | Should -Be 'scripts,module,compare'
        }

        It 'checks the manifest in one step with engine <_>' -ForEach @('scripts', 'module', 'compare') {
            $manifestSteps = @($script:gateSteps[$_] | Where-Object { $_.displayName -like 'Verify dependency manifest*' })
            $manifestSteps.Count | Should -Be 1
            $manifestSteps[0].displayName | Should -BeExactly $script:gateNames[$_]
        }

        It 'keeps every other step the same with engine <_>' -ForEach @('module', 'compare') {
            $others = { param($Steps) (@($Steps | Where-Object { $_.displayName -notlike 'Verify dependency manifest*' } | ForEach-Object { "$($_.displayName)`n$(Get-StepText $_)" }) -join "`n--`n") }
            & $others $script:gateSteps[$_] | Should -BeExactly (& $others $script:gateSteps.scripts)
        }

        It 'lets the module''s step set no variable and change no PATH, with engine <_>' -ForEach @('module', 'compare') {
            $engine = $_
            $step = @($script:gateSteps[$engine] | Where-Object { $_.displayName -eq $script:gateNames[$engine] })[0]
            & $script:moduleStepRule $step | Should -BeTrue
        }
    }

    Context 'The steps, run' {
        BeforeAll {
            $script:moduleGate = Get-PipelineInlineScript -Path $script:gatePipeline -Step $script:gateNames.module -Parameters @{ engine = 'module' } -Variables @{}
            $script:compareGate = Get-PipelineInlineScript -Path $script:gatePipeline -Step $script:gateNames.compare -Parameters @{ engine = 'compare' } -Variables @{}
            $script:updateStep = Get-PipelineInlineScript -Path $script:updatePipeline -Step 'Update the dependency manifest (iSOCDeployments)' -Parameters @{ engine = 'module' } -Variables @{}
            $script:scriptsUpdate = Get-PipelineInlineScript -Path $script:updatePipeline -Step 'Run dependency-manifest update' -Parameters @{ engine = 'scripts' } -Variables @{ 'Build.SourcesDirectory' = '__CHECKOUT__' }

            # A checkout whose manifest is current, or one with an entry
            # taken out.
            function Build-GateCheckout {
                param([switch] $Stale, [switch] $WithYml, [switch] $ByScripts)
                $checkout = Build-PipelineCheckout -WithYml:$WithYml
                $write = if ($ByScripts) { $script:scriptsUpdate.Replace('__CHECKOUT__', $checkout) } else { $script:updateStep }
                (Invoke-PipelineStep -Script $write -Checkout $checkout).ExitCode | Should -Be 0
                if ($Stale) {
                    $path = Join-Path $checkout 'dependencies.json'
                    $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
                    $manifest.dependencies.Remove(@($manifest.dependencies.Keys | Sort-Object)[0])
                    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path
                }
                $checkout
            }
        }

        It 'passes a current manifest with engine module' {
            $run = Invoke-PipelineStep -Script $script:moduleGate -Checkout (Build-GateCheckout)
            $run.ExitCode | Should -Be 0 -Because $run.Output
        }

        It 'fails a stale manifest with engine module, naming the fix' {
            $run = Invoke-PipelineStep -Script $script:moduleGate -Checkout (Build-GateCheckout -Stale)
            $run.ExitCode | Should -Be 1
            $run.Output | Should -Match ([regex]::Escape('##vso[task.logissue type=error]dependencies.json is out of sync with content.'))
            $run.Output | Should -Match ([regex]::Escape('##vso[task.logissue type=error]Fix: run Update-iSOCDependencyManifest'))
        }

        It 'passes a current manifest with engine compare, the engines agreeing' {
            $run = Invoke-PipelineStep -Script $script:compareGate -Checkout (Build-GateCheckout)
            $run.ExitCode | Should -Be 0 -Because $run.Output
            $run.Output | Should -Match 'The scripts and the module agree'
        }

        It 'fails a stale manifest with engine compare, the engines agreeing' {
            $run = Invoke-PipelineStep -Script $script:compareGate -Checkout (Build-GateCheckout -Stale)
            $run.ExitCode | Should -Be 1
            $run.Output | Should -Match ([regex]::Escape('##vso[task.logissue type=error]dependencies.json is out of sync with content.'))
            $run.Output | Should -Not -Match 'The engines disagree'
        }

        It 'fails with engine compare when the engines disagree, naming edit E8' {
            # The script's manifest leaves out the .yml rule, which the
            # module reads.
            $run = Invoke-PipelineStep -Script $script:compareGate -Checkout (Build-GateCheckout -WithYml -ByScripts)
            $run.ExitCode | Should -Be 1
            $run.Output | Should -Match 'The engines disagree: Tools/Build-DependencyManifest\.ps1 says the manifest is current, Test-iSOCDependencyManifest says out of date'
            $run.Output | Should -Match 'E8'
        }
    }
}
