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

    The steps that need Azure run against stand-ins for the module's
    commands, which carry the real commands' parameter blocks and record
    what they are given, so the suite checks what each pipeline parameter
    becomes in the module, and what the step does with the result.

    The pipelines: Pipelines/Sentinel-Dependency-Update.yml, the manifest
    gate of Pipelines/Sentinel-PR-Validation.yml,
    Pipelines/Sentinel-Drift-Detect.yml and Pipelines/Sentinel-Deploy.yml.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Pipelines.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Pipelines.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-05
    Version:      0.2.0
    Last Updated: 2026-11-05
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml, git
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $PSScriptRoot '_helpers/WorkspaceStandIn.psm1') -Force
    $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'
    $script:updatePipeline = Join-Path $script:repoRoot 'Pipelines/Sentinel-Dependency-Update.yml'
    $script:gatePipeline = Join-Path $script:repoRoot 'Pipelines/Sentinel-PR-Validation.yml'
    $script:driftPipeline = Join-Path $script:repoRoot 'Pipelines/Sentinel-Drift-Detect.yml'
    $script:deployPipeline = Join-Path $script:repoRoot 'Pipelines/Sentinel-Deploy.yml'
    $script:workspaceVariables = @{
        azureSubscriptionId   = '00000000-0000-4000-8000-000000000001'
        sentinelResourceGroup = 'rg-sentinel'
        sentinelWorkspaceName = 'law-sentinel'
        sentinelRegion        = 'uksouth'
    }

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
        param([string] $Script, [string] $Checkout, [hashtable] $Environment = @{}, [string] $Prelude = '', [string] $TempDirectory)
        $temp = if ($TempDirectory) { $TempDirectory } else { Join-Path $TestDrive ([guid]::NewGuid().ToString()) }
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        $file = Join-Path $TestDrive "step-$([guid]::NewGuid()).ps1"
        Set-Content -LiteralPath $file -Value ($Prelude + "`n" + $Script) -Encoding utf8
        $agent = @{ BUILD_SOURCESDIRECTORY = $Checkout; AGENT_TEMPDIRECTORY = $temp; TF_BUILD = 'True' }
        foreach ($name in $Environment.Keys) { $agent[$name] = $Environment[$name] }
        $saved = @{}
        foreach ($name in $agent.Keys) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $agent[$name])
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
        if ($Step.Contains('inputs') -and $Step.inputs.Contains('Inline')) { return [string]$Step.inputs.Inline }
        if ($Step.Contains('inputs') -and $Step.inputs.Contains('inlineScript')) { return [string]$Step.inputs.inlineScript }
        if ($Step.Contains('bash')) { return [string]$Step.bash }
        ''
    }

    # The parameters as Azure DevOps puts them into a template expression:
    # booleans as True or False.
    function Get-RenderedParameter {
        param([string] $Path, [hashtable] $Parameters = @{})
        $values = Resolve-PipelineParameter -Yaml (Read-PipelineYaml -Path $Path) -Parameters $Parameters
        $rendered = @{}
        foreach ($name in $values.Keys) { $rendered[$name] = [string]$values[$name] }
        $rendered
    }

    # A step's env as the agent sets it: $(name) from the variables (left
    # as its own text when the variable is not set), and parameters from
    # their template expressions.
    function Get-StepEnvironment {
        param([System.Collections.IDictionary] $Step, [hashtable] $Variables, [hashtable] $Rendered)
        $known = $Variables
        $parameterValues = $Rendered
        $environment = @{}
        if (-not $Step.Contains('env')) { return $environment }
        foreach ($name in $Step.env.Keys) {
            $value = [string]$Step.env[$name]
            $value = [regex]::Replace($value, '\$\(([\w.]+)\)', { param($m) if ($known.ContainsKey($m.Groups[1].Value)) { [string]$known[$m.Groups[1].Value] } else { $m.Value } })
            $value = [regex]::Replace($value, '\$\{\{\s*parameters\.(\w+)\s*\}\}', { param($m) [string]$parameterValues[$m.Groups[1].Value] })
            $environment[$name] = $value
        }
        $environment
    }

    # Stand-ins for module commands with the real commands' parameter
    # blocks. Each writes what it was given to the file STUB_CALLS names
    # and returns what the case sets: Get-iSOCWorkspaceOnboarding returns
    # STUB_ONBOARDING, Deploy-iSOCWorkspace an ExitCode of STUB_EXIT_CODE,
    # Compare-iSOCContent HasDrift from STUB_HAS_DRIFT; Sync-iSOCContent
    # passes the result on. Import-Module does nothing.
    function Get-ModuleStub {
        param([string[]] $Command)
        $text = [System.Text.StringBuilder]::new()
        [void]$text.AppendLine('function Import-Module { }')
        [void]$text.AppendLine(@'
function Save-StubCall {
    param($Name, $Bound)
    $parameters = [ordered]@{}
    foreach ($key in $Bound.Keys) {
        if ($key -eq 'InputObject') { continue }
        $value = $Bound[$key]
        if ($value -is [System.Management.Automation.SwitchParameter]) { $value = $value.IsPresent }
        $parameters[$key] = $value
    }
    Add-Content -LiteralPath $env:STUB_CALLS -Value (ConvertTo-Json -InputObject ([ordered]@{ Command = $Name; Parameters = $parameters }) -Depth 6 -Compress) -WhatIf:$false -Confirm:$false
}
'@)
        foreach ($name in $Command) {
            $path = Join-Path $script:repoRoot "Modules/iSOCDeployments/Public/$name.ps1"
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
            $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            $binding = @($function.Body.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' } | ForEach-Object { $_.Extent.Text })[0]
            $result = switch ($name) {
                'Get-iSOCWorkspaceOnboarding' { '$env:STUB_ONBOARDING | ConvertFrom-Json' }
                'Deploy-iSOCWorkspace' { '[pscustomobject]@{ ExitCode = [int]$env:STUB_EXIT_CODE }' }
                'Compare-iSOCContent' { '[pscustomobject]@{ HasDrift = $env:STUB_HAS_DRIFT -eq ''true'' }' }
                'Sync-iSOCContent' { '$InputObject' }
                default { '' }
            }
            [void]$text.AppendLine("function $name {`n$binding`n$($function.Body.ParamBlock.Extent.Text)`nprocess {`nSave-StubCall '$name' `$PSBoundParameters`n$result`n}`n}")
        }
        $text.ToString()
    }

    # Run one step of a pipeline as the agent would, with the stand-ins.
    function Invoke-StubbedStep {
        param([string] $Path, [string] $Step, [hashtable] $Parameters = @{}, [hashtable] $Variables = @{}, [string[]] $Stub = @(), [hashtable] $Environment = @{}, [string] $Checkout, [string] $TempDirectory)
        $rendered = Get-RenderedParameter -Path $Path -Parameters $Parameters
        $known = @{}
        foreach ($name in $rendered.Keys) { $known[$name] = $rendered[$name] }
        foreach ($name in $Variables.Keys) { $known[$name] = $Variables[$name] }
        $definition = @(Get-PipelineStep -Path $Path -Parameters $Parameters | Where-Object { $_.displayName -eq $Step })[0]
        $script = Get-PipelineInlineScript -Path $Path -Step $Step -Parameters $Parameters -Variables $known
        $stepEnvironment = Get-StepEnvironment -Step $definition -Variables $Variables -Rendered $rendered
        foreach ($name in $Environment.Keys) { $stepEnvironment[$name] = $Environment[$name] }
        $calls = Join-Path $TestDrive "calls-$([guid]::NewGuid()).jsonl"
        $stepEnvironment['STUB_CALLS'] = $calls
        if (-not $Checkout) { $Checkout = Join-Path $TestDrive ([guid]::NewGuid().ToString()); New-Item -ItemType Directory -Path $Checkout | Out-Null }
        $run = Invoke-PipelineStep -Script $script -Checkout $Checkout -Environment $stepEnvironment -Prelude (Get-ModuleStub -Command $Stub) -TempDirectory $TempDirectory
        $recorded = if (Test-Path -LiteralPath $calls) { @(Get-Content -LiteralPath $calls | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable }) } else { @() }
        [pscustomobject]@{ ExitCode = $run.ExitCode; Output = $run.Output; Calls = $recorded; Checkout = $Checkout }
    }

    function Get-Call {
        param($Run, [string] $Command)
        , @($Run.Calls | Where-Object { $_.Command -eq $Command } | ForEach-Object { $_.Parameters })
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

Describe 'Pipelines/Sentinel-Drift-Detect.yml' {
    BeforeAll {
        $script:driftSteps = @{}
        foreach ($engine in 'scripts', 'module', 'compare') {
            $script:driftSteps[$engine] = @(Get-PipelineStep -Path $script:driftPipeline -Parameters @{ engine = $engine })
        }
        $script:driftCommit = 'Commit, Push, and Open PR (when drift detected)'
        $script:driftModule = 'Detect Sentinel Rule Drift (iSOCDeployments)'
        $script:driftScripts = 'Detect Sentinel Rule Drift'
        $script:driftBefore = 'Compare drift with iSOCDeployments (before the script)'
        $script:driftCompare = 'Compare drift: the scripts and iSOCDeployments'
        $script:driftStub = 'Connect-iSOCWorkspace', 'Compare-iSOCContent', 'Sync-iSOCContent', 'Export-iSOCDriftReport'

        # The script's step against a stand-in Tools/Test-SentinelRuleDrift.ps1
        # with the real parameter block, recording what it is given.
        function Invoke-DriftScriptsStep {
            param([hashtable] $Parameters)
            $checkout = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path (Join-Path $checkout 'Tools') -Force | Out-Null
            $real = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:repoRoot 'Tools/Test-SentinelRuleDrift.ps1'), [ref]$null, [ref]$null)
            $record = Join-Path $checkout 'drift.call.json'
            $standIn = "[CmdletBinding()]`n$($real.ParamBlock.Extent.Text)`n" +
                "`$bound = [ordered]@{}; foreach (`$k in `$PSBoundParameters.Keys) { `$v = `$PSBoundParameters[`$k]; if (`$v -is [System.Management.Automation.SwitchParameter]) { `$v = `$v.IsPresent }; `$bound[`$k] = `$v }`n" +
                "ConvertTo-Json -InputObject `$bound | Set-Content -LiteralPath '$record'"
            Set-Content -LiteralPath (Join-Path $checkout 'Tools/Test-SentinelRuleDrift.ps1') -Value $standIn
            $variables = @{ 'Build.SourcesDirectory' = $checkout }
            foreach ($name in $script:workspaceVariables.Keys) { $variables[$name] = $script:workspaceVariables[$name] }
            $flags = Get-PipelineVariableValue -Path $script:driftPipeline -Parameters $Parameters
            foreach ($name in $flags.Keys) { if ($name -like 'flag*') { $variables[$name] = $flags[$name] } }
            $text = Get-PipelineInlineScript -Path $script:driftPipeline -Step $script:driftScripts -Parameters $Parameters -Variables $variables
            $run = Invoke-PipelineStep -Script $text -Checkout $checkout
            $run.ExitCode | Should -Be 0 -Because $run.Output
            Get-Content -LiteralPath $record -Raw | ConvertFrom-Json -AsHashtable
        }
    }

    Context 'Engines' {
        It 'takes an engine of scripts, module or compare, scripts by default' {
            $parameter = @((Read-PipelineYaml -Path $script:driftPipeline).parameters | Where-Object { $_.name -eq 'engine' })
            $parameter[0].default | Should -Be 'scripts'
            @($parameter[0].values) -join ',' | Should -Be 'scripts,module,compare'
        }

        It 'runs <Steps> with engine <Engine>' -ForEach @(
            @{ Engine = 'scripts'; Steps = 'Install powershell-yaml Module|Detect Sentinel Rule Drift|Commit, Push, and Open PR (when drift detected)' }
            @{ Engine = 'module'; Steps = 'Install powershell-yaml Module|Detect Sentinel Rule Drift (iSOCDeployments)|Commit, Push, and Open PR (when drift detected)' }
            @{ Engine = 'compare'; Steps = 'Install powershell-yaml Module|Compare drift with iSOCDeployments (before the script)|Detect Sentinel Rule Drift|Compare drift: the scripts and iSOCDeployments|Commit, Push, and Open PR (when drift detected)' }
        ) {
            (@($script:driftSteps[$Engine] | Where-Object { $_.displayName } | ForEach-Object { $_.displayName }) -join '|') | Should -BeExactly $Steps
        }

        It 'runs the script only under engines scripts and compare' {
            @($script:driftSteps.module | Where-Object { (Get-StepText $_) -match 'Test-SentinelRuleDrift\.ps1' }).Count | Should -Be 0
            @($script:driftSteps.scripts | Where-Object { (Get-StepText $_) -match 'iSOCDeployments' -and $_.displayName -ne $script:driftCommit }).Count | Should -Be 0
        }

        It 'lets no step that reads the workspace set a variable or change PATH, with engine <_>' -ForEach @('scripts', 'module', 'compare') {
            $readers = @($script:driftSteps[$_] | Where-Object { $_.displayName -in $script:driftModule, $script:driftScripts, $script:driftBefore, $script:driftCompare })
            $readers.Count | Should -BeGreaterThan 0
            foreach ($step in $readers) {
                $step.target.settableVariables | Should -Be 'none' -Because $step.displayName
                if ((Get-StepText $step) -match 'iSOCDeployments\.psd1') { $step.target.commands | Should -Be 'restricted' -Because $step.displayName }
            }
        }
    }

    Context 'The commit step' {
        BeforeAll {
            $script:driftCommitStep = @($script:driftSteps.module | Where-Object { $_.displayName -eq $script:driftCommit })[0]
            $script:driftCommitText = Get-StepText $script:driftCommitStep
        }

        It 'is the same step with every engine' {
            $texts = foreach ($engine in 'scripts', 'module', 'compare') { (@($script:driftSteps[$engine] | Where-Object { $_.displayName -eq $script:driftCommit })[0] | ConvertTo-Json -Depth 6 -Compress) -replace '"PipelineJob":"[^"]*"', '' }
            @($texts | Select-Object -Unique).Count | Should -Be 1
        }

        It 'runs only from main, and not when report only' {
            ($script:driftCommitStep.condition -replace '\s', '') | Should -BeExactly "and(succeeded(),ne(variables['flagReportOnly'],'-ReportOnly'),eq(variables['Build.SourceBranch'],'refs/heads/main'))"
        }

        It 'prints the report, so it sets no variable and changes no PATH' {
            & $script:moduleStepRule $script:driftCommitStep | Should -BeTrue
        }

        It 'stages only the rules, the reports and the manifest' {
            @([regex]::Matches($script:driftCommitText, '(?m)^\s*git add .*$') | ForEach-Object { $_.Value.Trim() }) -join '|' | Should -BeExactly 'git add Content/AnalyticalRules reports dependencies.json'
        }

        It 'takes <Variable> through env, not as a macro' -ForEach @(
            @{ Variable = 'syncBranch'; Env = 'SYNC_BRANCH' }
            @{ Variable = 'targetBranch'; Env = 'TARGET_BRANCH' }
        ) {
            $script:driftCommitText | Should -Not -Match ([regex]::Escape("`$($Variable)"))
            $script:driftCommitStep.env[$Env] | Should -BeExactly "`$($Variable)"
        }

        It 'regenerates the manifest with the engine the run uses' {
            $script:driftCommitStep.env.ENGINE | Should -BeExactly '${{ parameters.engine }}'
            $script:driftCommitText | Should -Match ([regex]::Escape('if [ "$ENGINE" = "module" ]; then'))
            $script:driftCommitText | Should -Match 'Update-iSOCDependencyManifest'
            $script:driftCommitText | Should -Match ([regex]::Escape('./Tools/Build-DependencyManifest.ps1 -Mode Generate'))
        }

        It 'makes the bot branches read-only in <_>' -ForEach @('Sentinel-Drift-Detect.yml', 'Sentinel-Dependency-Update.yml') {
            $yaml = Read-PipelineYaml -Path (Join-Path $script:repoRoot "Pipelines/$_")
            foreach ($name in 'syncBranch', 'targetBranch') {
                @($yaml.variables | Where-Object { $_.name -eq $name })[0].readonly | Should -BeTrue -Because $name
            }
        }
    }

    Context 'The module step, run' {
        It 'does what the script is told to do, <Case>' -ForEach @(
            @{ Case = 'with the defaults'; Parameters = @{ engine = 'module' }; Exclude = ''; Sync = $true; HasDrift = $true; Exit = 0 }
            @{ Case = 'report only'; Parameters = @{ engine = 'module'; reportOnly = $true }; Exclude = ''; Sync = $false; HasDrift = $true; Exit = 0 }
            @{ Case = 'with every bucket left out'; Parameters = @{ engine = 'module'; skipContentHub = $true; skipCustom = $true; skipOrphans = $true }; Exclude = 'ContentHub,Custom,Orphan'; Sync = $true; HasDrift = $false; Exit = 0 }
            @{ Case = 'failing on drift, with drift'; Parameters = @{ engine = 'module'; failOnDrift = $true }; Exclude = ''; Sync = $true; HasDrift = $true; Exit = 1 }
            @{ Case = 'failing on drift, with none'; Parameters = @{ engine = 'module'; failOnDrift = $true }; Exclude = ''; Sync = $true; HasDrift = $false; Exit = 0 }
        ) {
            $run = Invoke-StubbedStep -Path $script:driftPipeline -Step $script:driftModule -Parameters $Parameters -Variables $script:workspaceVariables -Stub $script:driftStub -Environment @{ STUB_HAS_DRIFT = "$HasDrift".ToLower() }
            $run.ExitCode | Should -Be $Exit -Because $run.Output

            $connect = Get-Call $run 'Connect-iSOCWorkspace'
            $connect.Count | Should -Be 1
            $connect[0].SubscriptionId | Should -Be $script:workspaceVariables.azureSubscriptionId
            $connect[0].ResourceGroup | Should -Be 'rg-sentinel'
            $connect[0].WorkspaceName | Should -Be 'law-sentinel'

            $compare = Get-Call $run 'Compare-iSOCContent'
            $compare.Count | Should -Be 1
            $compare[0].RepoPath | Should -Be $run.Checkout
            (@($compare[0].ExcludeSource) -join ',') | Should -BeExactly $Exclude
            (Get-Call $run 'Sync-iSOCContent').Count | Should -Be ([int]$Sync)
            (Get-Call $run 'Export-iSOCDriftReport').Count | Should -Be 1

            # The script's step, for the same parameters, is told the same.
            $asScripts = @{}
            foreach ($name in $Parameters.Keys) { $asScripts[$name] = $Parameters[$name] }
            $asScripts['engine'] = 'scripts'
            $scripts = Invoke-DriftScriptsStep -Parameters $asScripts
            (@('ContentHub', 'Custom', 'Orphan' | Where-Object { $scripts["Skip$($_ -replace 'Orphan', 'Orphans')"] }) -join ',') | Should -BeExactly $Exclude
            [bool]$scripts['ReportOnly'] | Should -Be (-not $Sync)
            [bool]$scripts['FailOnDrift'] | Should -Be ([bool]$Parameters['failOnDrift'])
            $scripts.RepoPath | Should -Not -BeNullOrEmpty
        }
    }

    Context 'The compare steps, run' {
        BeforeAll {
            # A drift report as both engines write it, with its summary.
            function Write-DriftReportFile {
                param([string] $Folder, [string] $Stamp, [hashtable] $Summary)
                New-Item -ItemType Directory -Path $Folder -Force | Out-Null
                ConvertTo-Json -InputObject @{ summary = $Summary } | Set-Content -LiteralPath (Join-Path $Folder "sentinel-drift-$Stamp.json")
            }
            $script:summaryA = @{ totalDeployed = 10; contentHubClean = 4; contentHubDrift = 1; customClean = 3; customDrift = 1; orphan = 1; managed = 0; skipped = 0 }
        }

        It 'reads the workspace before the script, writing its report to the temporary folder and nothing to the repository' {
            $temp = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            $checkout = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            Write-DriftReportFile -Folder (Join-Path $checkout 'reports') -Stamp '2026-11-01T06-00Z' -Summary $script:summaryA
            $run = Invoke-StubbedStep -Path $script:driftPipeline -Step $script:driftBefore -Parameters @{ engine = 'compare' } -Variables $script:workspaceVariables -Stub $script:driftStub -Environment @{ STUB_HAS_DRIFT = 'true' } -Checkout $checkout -TempDirectory $temp
            $run.ExitCode | Should -Be 0 -Because $run.Output
            (Get-Call $run 'Sync-iSOCContent').Count | Should -Be 0
            (Get-Call $run 'Export-iSOCDriftReport')[0].Path | Should -Be (Join-Path $temp 'isoc-drift')
            Get-Content -LiteralPath (Join-Path $temp 'isoc-drift/reports-before.txt') | Should -Be 'sentinel-drift-2026-11-01T06-00Z.json'
        }

        It 'passes when <Case>' -ForEach @(
            @{ Case = 'neither engine found drift'; Scripts = $false; Module = $false }
            @{ Case = 'both count drift the same'; Scripts = $true; Module = $true }
        ) {
            $temp = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            $checkout = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            Write-DriftReportFile -Folder (Join-Path $checkout 'reports') -Stamp '2026-11-01T06-00Z' -Summary @{ orphan = 99 }
            New-Item -ItemType Directory -Path (Join-Path $temp 'isoc-drift') -Force | Out-Null
            'sentinel-drift-2026-11-01T06-00Z.json' | Set-Content -LiteralPath (Join-Path $temp 'isoc-drift/reports-before.txt')
            if ($Scripts) { Write-DriftReportFile -Folder (Join-Path $checkout 'reports') -Stamp '2026-11-05T06-00Z' -Summary $script:summaryA }
            if ($Module) { Write-DriftReportFile -Folder (Join-Path $temp 'isoc-drift') -Stamp '2026-11-05T06-00Z' -Summary $script:summaryA }
            $run = Invoke-StubbedStep -Path $script:driftPipeline -Step $script:driftCompare -Parameters @{ engine = 'compare' } -Checkout $checkout -TempDirectory $temp
            $run.ExitCode | Should -Be 0 -Because $run.Output
        }

        It 'fails, naming the edits, when <Case>' -ForEach @(
            @{ Case = 'only the script found drift'; Scripts = $true; Module = $false; Expected = 'Only Tools/Test-SentinelRuleDrift.ps1 found drift' }
            @{ Case = 'only the module found drift'; Scripts = $false; Module = $true; Expected = 'Only the module found drift' }
            @{ Case = 'they count drift differently'; Scripts = $true; Module = $true; Different = $true; Expected = 'count drift differently: orphan: scripts 1, module 2' }
        ) {
            $temp = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            $checkout = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path (Join-Path $temp 'isoc-drift'), (Join-Path $checkout 'reports') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $temp 'isoc-drift/reports-before.txt') -Value ''
            if ($Scripts) { Write-DriftReportFile -Folder (Join-Path $checkout 'reports') -Stamp '2026-11-05T06-00Z' -Summary $script:summaryA }
            if ($Module) {
                $summary = $script:summaryA.Clone()
                if ($Different) { $summary.orphan = 2 }
                Write-DriftReportFile -Folder (Join-Path $temp 'isoc-drift') -Stamp '2026-11-05T06-00Z' -Summary $summary
            }
            $run = Invoke-StubbedStep -Path $script:driftPipeline -Step $script:driftCompare -Parameters @{ engine = 'compare' } -Checkout $checkout -TempDirectory $temp
            $run.ExitCode | Should -Be 1
            $run.Output | Should -Match ([regex]::Escape($Expected))
            $run.Output | Should -Match 'E22 to E24'
        }
    }
}

Describe 'Pipelines/Sentinel-Deploy.yml' {
    BeforeAll {
        $script:deploySteps = @{}
        $script:deployStages = @{}
        foreach ($engine in 'scripts', 'module', 'compare') {
            $script:deploySteps[$engine] = @(Get-PipelineStep -Path $script:deployPipeline -Parameters @{ engine = $engine })
            $script:deployStages[$engine] = @(Get-PipelineStage -Path $script:deployPipeline -Parameters @{ engine = $engine })
        }
        $script:checkModule = 'Check for Existing Resources (iSOCDeployments)'
        $script:checkCompare = 'Compare the check with iSOCDeployments'
        $script:deployStub = 'Connect-iSOCWorkspace', 'Deploy-iSOCWorkspace', 'Get-iSOCWorkspaceOnboarding'
        $script:switched = @{
            disableRules = $false; protectCustomisedRules = $false
            skipAnalyticsRules = $true; skipWorkbooks = $true; skipAutomationRules = $true; skipHuntingQueries = $true
            forceSolutionUpdate = $true; forceContentDeployment = $true
            skipCustomParsers = $true; skipCustomDetections = $true; skipCustomWatchlists = $true; skipCustomPlaybooks = $true
            skipCustomWorkbooks = $true; skipCustomHuntingQueries = $true; skipCustomAutomationRules = $true; skipCustomSummaryRules = $true
            skipCommunityDetections = $false; smartDeployment = $false; whatIf = $true
            solutions = 'Azure Activity, Microsoft Entra ID'; severitiesToInclude = 'High, Medium'
        }

        # A call as canonical JSON: keys in order, so two calls compare as text.
        function Format-Call {
            param([System.Collections.IDictionary] $Call)
            $sorted = [ordered]@{}
            foreach ($key in ($Call.Keys | Sort-Object)) { $sorted[$key] = $Call[$key] }
            ConvertTo-Json -InputObject $sorted -Depth 5 -Compress
        }

        function Get-DefaultSolution {
            $default = @((Read-PipelineYaml -Path $script:deployPipeline).parameters | Where-Object { $_.name -eq 'solutions' })[0].default
            @($default -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
    }

    Context 'Engines' {
        It 'takes an engine of scripts, module or compare, scripts by default' {
            $parameter = @((Read-PipelineYaml -Path $script:deployPipeline).parameters | Where-Object { $_.name -eq 'engine' })
            $parameter[0].default | Should -Be 'scripts'
            @($parameter[0].values) -join ',' | Should -Be 'scripts,module,compare'
        }

        It 'runs these steps with engine <Engine>' -ForEach @(
            @{ Engine = 'scripts'; Steps = @(
                    'CheckInfrastructure/Check for Existing Log Analytics Workspace'
                    'DeployInfrastructure/Register Required Resource Providers', 'DeployInfrastructure/Deploy Sentinel Infrastructure with Bicep', 'DeployInfrastructure/Wait for Workspace Indexing', 'DeployInfrastructure/Configure Sentinel Settings'
                    'DeployContentHub/Deploy Content Hub Solutions'
                    'DeployCustomContent/Restore Deployment State', 'DeployCustomContent/Install powershell-yaml Module', 'DeployCustomContent/Verify dependency manifest is current', 'DeployCustomContent/Deploy Custom Content', 'DeployCustomContent/Save Deployment State'
                    'DeployDefenderDetections/Install powershell-yaml Module', 'DeployDefenderDetections/Deploy Defender Custom Detections') }
            @{ Engine = 'module'; Steps = @(
                    'CheckInfrastructure/Check for Existing Resources (iSOCDeployments)'
                    'DeployInfrastructure/Register Required Resource Providers', 'DeployInfrastructure/Deploy Sentinel Infrastructure with Bicep', 'DeployInfrastructure/Wait for Workspace Indexing'
                    'DeployWorkspaceSettings/Install powershell-yaml Module', 'DeployWorkspaceSettings/Deploy Workspace Settings (iSOCDeployments)'
                    'DeployContentHub/Deploy Content Hub Solutions (iSOCDeployments)'
                    'DeployCustomContent/Restore Deployment State', 'DeployCustomContent/Install powershell-yaml Module', 'DeployCustomContent/Deploy Custom Content (iSOCDeployments)', 'DeployCustomContent/Save Deployment State'
                    'DeployDefenderDetections/Install powershell-yaml Module', 'DeployDefenderDetections/Deploy Defender Custom Detections (iSOCDeployments)') }
            @{ Engine = 'compare'; Steps = @(
                    'CheckInfrastructure/Check for Existing Log Analytics Workspace', 'CheckInfrastructure/Compare the check with iSOCDeployments'
                    'DeployInfrastructure/Register Required Resource Providers', 'DeployInfrastructure/Deploy Sentinel Infrastructure with Bicep', 'DeployInfrastructure/Wait for Workspace Indexing', 'DeployInfrastructure/Configure Sentinel Settings'
                    'DeployWorkspaceSettings/Install powershell-yaml Module', 'DeployWorkspaceSettings/Deploy Workspace Settings (iSOCDeployments)'
                    'DeployContentHub/Deploy Content Hub Solutions', 'DeployContentHub/Deploy Content Hub Solutions (iSOCDeployments)'
                    'DeployCustomContent/Restore Deployment State', 'DeployCustomContent/Install powershell-yaml Module', 'DeployCustomContent/Verify dependency manifest is current', 'DeployCustomContent/Deploy Custom Content', 'DeployCustomContent/Deploy Custom Content (iSOCDeployments)', 'DeployCustomContent/Save Deployment State'
                    'DeployDefenderDetections/Install powershell-yaml Module', 'DeployDefenderDetections/Deploy Defender Custom Detections', 'DeployDefenderDetections/Deploy Defender Custom Detections (iSOCDeployments)') }
        ) {
            (@($script:deploySteps[$Engine] | Where-Object { $_.displayName } | ForEach-Object { "$($_.PipelineStage)/$($_.displayName)" }) -join '|') | Should -BeExactly ($Steps -join '|')
        }

        It 'runs nothing from the module with engine scripts, and none of the scripts with engine module' {
            @($script:deploySteps.scripts | Where-Object { (Get-StepText $_) -match 'iSOCDeployments' }).Count | Should -Be 0
            @($script:deploySteps.module | Where-Object { (Get-StepText $_) -match 'Deploy/content/|Build-DependencyManifest\.ps1' }).Count | Should -Be 0
        }

        It 'checks out the repository for the module check, with engine <_>' -ForEach @('module', 'compare') {
            @($script:deploySteps[$_] | Where-Object { $_.PipelineStage -eq 'CheckInfrastructure' -and $_.Contains('checkout') }).Count | Should -Be 1
        }

        It 'lets each module step set no variable but its own outputs, with engine <_>' -ForEach @('module', 'compare') {
            $moduleSteps = @($script:deploySteps[$_] | Where-Object { (Get-StepText $_) -match 'iSOCDeployments\.psd1' })
            $moduleSteps.Count | Should -Be 5
            foreach ($step in $moduleSteps) {
                $step.target.commands | Should -Be 'restricted' -Because $step.displayName
                $expected = if ($step.displayName -eq $script:checkModule) { 'RESOURCES_EXIST,DEPLOY_SENTINEL' } else { 'none' }
                (@($step.target.settableVariables) -join ',') | Should -BeExactly $expected -Because $step.displayName
                (Get-StepText $step) | Should -Not -Match '\$\([A-Za-z.]+\)' -Because "$($step.displayName) reads variables through env"
            }
        }

        It 'gives the module check the name the infrastructure stage reads its output by' {
            @($script:deploySteps.module | Where-Object { $_.displayName -eq $script:checkModule })[0].name | Should -BeExactly 'CheckSentinelResources'
            (@($script:deployStages.module | Where-Object { $_.stage -eq 'DeployInfrastructure' })[0].condition) | Should -Match ([regex]::Escape("outputs['CheckResources.CheckSentinelResources.RESOURCES_EXIST']"))
        }
    }

    Context 'The workspace settings stage' {
        It 'runs only with engines module and compare' {
            @($script:deployStages.scripts | Where-Object { $_.stage -eq 'DeployWorkspaceSettings' }).Count | Should -Be 0
            foreach ($engine in 'module', 'compare') { @($script:deployStages[$engine] | Where-Object { $_.stage -eq 'DeployWorkspaceSettings' }).Count | Should -Be 1 }
        }

        It 'runs after the infrastructure, when it succeeded or did not run' {
            $stage = @($script:deployStages.module | Where-Object { $_.stage -eq 'DeployWorkspaceSettings' })[0]
            ($stage.dependsOn -join ',') | Should -BeExactly 'CheckInfrastructure,DeployInfrastructure'
            ($stage.condition -replace '\s', '') | Should -BeExactly "or(eq('`${{parameters.deployInfrastructure}}','False'),in(dependencies.DeployInfrastructure.result,'Succeeded','Skipped'))"
        }

        It 'comes before the Content Hub stage, and gates nothing' {
            foreach ($engine in 'module', 'compare') {
                $hub = @($script:deployStages[$engine] | Where-Object { $_.stage -eq 'DeployContentHub' })[0]
                $hub.dependsOn | Should -Contain 'DeployWorkspaceSettings'
                foreach ($stage in $script:deployStages[$engine]) { [string]$stage.condition | Should -Not -Match 'DeployWorkspaceSettings' -Because $stage.stage }
            }
            @($script:deployStages.scripts | Where-Object { $_.stage -eq 'DeployContentHub' })[0].dependsOn | Should -Not -Contain 'DeployWorkspaceSettings'
        }
    }

    Context 'The infrastructure stage' {
        BeforeAll {
            $script:bicepStep = @($script:deploySteps.module | Where-Object { $_.displayName -eq 'Deploy Sentinel Infrastructure with Bicep' })[0]
            $script:bicepText = Get-StepText $script:bicepStep
        }

        It 'reads the module check''s DEPLOY_SENTINEL into the job' {
            $job = @(@($script:deployStages.module | Where-Object { $_.stage -eq 'DeployInfrastructure' })[0].jobs)[0]
            $variable = @($job.variables | Where-Object { $_.name -eq 'deploySentinel' })[0]
            $variable.value | Should -BeExactly "`$[ stageDependencies.CheckInfrastructure.CheckResources.outputs['CheckSentinelResources.DEPLOY_SENTINEL'] ]"
        }

        It 'gives Bicep the playbook group and deploySentinel through env' {
            $script:bicepStep.env.PLAYBOOK_RESOURCE_GROUP | Should -BeExactly '$(playbookResourceGroup)'
            $script:bicepStep.env.DEPLOY_SENTINEL | Should -BeExactly '$(deploySentinel)'
            $script:bicepText | Should -Not -Match ([regex]::Escape('$(playbookResourceGroup)'))
            $script:bicepText | Should -Match ([regex]::Escape('PARAMS="$PARAMS deploySentinel=$DEPLOY_SENTINEL"'))
            $script:bicepText | Should -Match ([regex]::Escape('true|false)'))
        }

        It 'configures the settings in the infrastructure stage only with engines scripts and compare' {
            @($script:deploySteps.module | Where-Object { $_.displayName -eq 'Configure Sentinel Settings' }).Count | Should -Be 0
        }
    }

    Context 'The module check, run' {
        It 'reports <Status>' -ForEach @(
            @{ Status = 'Onboarded'; Needed = $false; Sentinel = $false; Code = 0; Exist = 'true'; Deploy = 'false' }
            @{ Status = 'NotOnboarded'; Needed = $true; Sentinel = $true; Code = 0; Exist = 'false'; Deploy = 'true' }
            @{ Status = 'StateMissing'; Needed = $true; Sentinel = $true; Code = 0; Exist = 'false'; Deploy = 'true' }
            @{ Status = 'SolutionMissing'; Needed = $false; Sentinel = $false; Code = 1; Exist = 'true'; Deploy = 'false' }
        ) {
            $onboarding = ConvertTo-Json -Compress -InputObject @{ Status = $Status; InfrastructureNeeded = $Needed; DeploySentinel = $Sentinel; ExitCode = $Code }
            $run = Invoke-StubbedStep -Path $script:deployPipeline -Step $script:checkModule -Parameters @{ engine = 'module' } -Variables $script:workspaceVariables -Stub $script:deployStub -Environment @{ STUB_ONBOARDING = $onboarding }
            $run.ExitCode | Should -Be $Code
            $run.Output | Should -Match ([regex]::Escape("##vso[task.setvariable variable=RESOURCES_EXIST;isOutput=true]$Exist"))
            $run.Output | Should -Match ([regex]::Escape("##vso[task.setvariable variable=DEPLOY_SENTINEL;isOutput=true]$Deploy"))
            $call = (Get-Call $run 'Get-iSOCWorkspaceOnboarding')[0]
            $call.SubscriptionId | Should -Be $script:workspaceVariables.azureSubscriptionId
            $call.ResourceGroup | Should -Be 'rg-sentinel'
            $call.WorkspaceName | Should -Be 'law-sentinel'
        }

        It 'passes the playbook group <Case>' -ForEach @(
            @{ Case = 'when set'; Value = 'rg-playbooks'; Expected = 'rg-playbooks' }
            @{ Case = 'as empty when the variable is not set'; Value = $null; Expected = '' }
        ) {
            $variables = $script:workspaceVariables.Clone()
            if ($Value) { $variables['playbookResourceGroup'] = $Value }
            $onboarding = '{"Status":"Onboarded","InfrastructureNeeded":false,"DeploySentinel":false,"ExitCode":0}'
            $run = Invoke-StubbedStep -Path $script:deployPipeline -Step $script:checkModule -Parameters @{ engine = 'module' } -Variables $variables -Stub $script:deployStub -Environment @{ STUB_ONBOARDING = $onboarding }
            $run.ExitCode | Should -Be 0 -Because $run.Output
            (Get-Call $run 'Get-iSOCWorkspaceOnboarding')[0].PlaybookResourceGroup | Should -BeExactly $Expected
        }

        It 'compares with the scripts'' decision: <Case>' -ForEach @(
            @{ Case = 'agreeing'; Scripts = 'true'; Status = 'Onboarded'; Needed = $false; Code = 0; Expected = 'the module says true (Onboarded)' }
            @{ Case = 'differing on onboarding, as E42 explains'; Scripts = 'true'; Status = 'StateMissing'; Needed = $true; Code = 0; Expected = 'MIGRATION.md edit E42' }
            @{ Case = 'differing otherwise'; Scripts = 'false'; Status = 'Onboarded'; Needed = $false; Code = 1; Expected = 'decide differently whether Bicep must run' }
        ) {
            $variables = $script:workspaceVariables.Clone()
            $variables['CheckSentinelResources.RESOURCES_EXIST'] = $Scripts
            $onboarding = ConvertTo-Json -Compress -InputObject @{ Status = $Status; InfrastructureNeeded = $Needed; DeploySentinel = $Needed; ExitCode = 0 }
            $run = Invoke-StubbedStep -Path $script:deployPipeline -Step $script:checkCompare -Parameters @{ engine = 'compare' } -Variables $variables -Stub $script:deployStub -Environment @{ STUB_ONBOARDING = $onboarding }
            $run.ExitCode | Should -Be $Code -Because $run.Output
            $run.Output | Should -Match ([regex]::Escape($Expected))
            $run.Output | Should -Not -Match ([regex]::Escape('##vso[task.setvariable'))
        }
    }

    Context 'The module stages, run' {
        It 'deploys <Name> with <Case>' -ForEach @(
            @{ Name = 'the settings'; Case = 'the defaults'; Step = 'Deploy Workspace Settings (iSOCDeployments)'; Parameters = @{ engine = 'module' }; Expected = @{ Stage = @('WorkspaceSettings') } }
            @{ Name = 'the settings'; Case = 'a dry run'; Step = 'Deploy Workspace Settings (iSOCDeployments)'; Parameters = @{ engine = 'module'; whatIf = $true }; Expected = @{ Stage = @('WorkspaceSettings'); WhatIf = $true } }
            @{ Name = 'the settings'; Case = 'engine compare'; Step = 'Deploy Workspace Settings (iSOCDeployments)'; Parameters = @{ engine = 'compare' }; Expected = @{ Stage = @('WorkspaceSettings'); WhatIf = $true } }
            @{ Name = 'the Content Hub solutions'; Case = 'the defaults'; Step = 'Deploy Content Hub Solutions (iSOCDeployments)'; Parameters = @{ engine = 'module' }; Expected = @{ Stage = @('ContentHub'); Solution = 'DEFAULT'; Severity = @('High', 'Medium', 'Low', 'Informational'); DisableRules = $true } }
            @{ Name = 'the Content Hub solutions'; Case = 'every parameter switched'; Step = 'Deploy Content Hub Solutions (iSOCDeployments)'; Parameters = 'SWITCHED'; Expected = @{ Stage = @('ContentHub'); Solution = @('Azure Activity', 'Microsoft Entra ID'); Severity = @('High', 'Medium'); OverwriteCustomisedRules = $true; ExcludeSolutionContentType = @('AnalyticsRule', 'Workbook', 'AutomationRule', 'HuntingQuery'); ForceSolutionUpdate = $true; ForceContentDeployment = $true; WhatIf = $true } }
            @{ Name = 'the Content Hub solutions'; Case = 'engine compare'; Step = 'Deploy Content Hub Solutions (iSOCDeployments)'; Parameters = @{ engine = 'compare' }; Expected = @{ Stage = @('ContentHub'); Solution = 'DEFAULT'; Severity = @('High', 'Medium', 'Low', 'Informational'); DisableRules = $true; WhatIf = $true } }
            @{ Name = 'the custom content'; Case = 'the defaults'; Step = 'Deploy Custom Content (iSOCDeployments)'; Parameters = @{ engine = 'module' }; Expected = @{ Stage = @('CustomContent'); Exclude = @('Content/AnalyticalRules/Community/*'); SmartDeployment = $true } }
            @{ Name = 'the custom content'; Case = 'every parameter switched'; Step = 'Deploy Custom Content (iSOCDeployments)'; Parameters = 'SWITCHED'; Expected = @{ Stage = @('CustomContent'); ExcludeContentType = @('Parser', 'AnalyticsRule', 'Watchlist', 'Playbook', 'Workbook', 'HuntingQuery', 'AutomationRule', 'SummaryRule'); WhatIf = $true } }
            @{ Name = 'the Defender detections'; Case = 'the defaults'; Step = 'Deploy Defender Custom Detections (iSOCDeployments)'; Parameters = @{ engine = 'module' }; Expected = @{ Stage = @('DefenderDetections') } }
            @{ Name = 'the Defender detections'; Case = 'engine compare'; Step = 'Deploy Defender Custom Detections (iSOCDeployments)'; Parameters = @{ engine = 'compare' }; Expected = @{ Stage = @('DefenderDetections'); WhatIf = $true } }
        ) {
            $given = if ($Parameters -eq 'SWITCHED') { $script:switched.Clone() + @{ engine = 'module' } } else { $Parameters }
            $variables = $script:workspaceVariables.Clone()
            $variables['playbookResourceGroup'] = 'rg-playbooks'
            $run = Invoke-StubbedStep -Path $script:deployPipeline -Step $Step -Parameters $given -Variables $variables -Stub $script:deployStub -Environment @{ STUB_EXIT_CODE = '0' }
            $run.ExitCode | Should -Be 0 -Because $run.Output

            $connect = (Get-Call $run 'Connect-iSOCWorkspace')[0]
            Format-Call $connect | Should -BeExactly (Format-Call @{ SubscriptionId = $script:workspaceVariables.azureSubscriptionId; ResourceGroup = 'rg-sentinel'; WorkspaceName = 'law-sentinel'; PlaybookResourceGroup = 'rg-playbooks' })

            $expected = $Expected.Clone()
            $expected['RepoPath'] = $run.Checkout
            if ($expected['Solution'] -eq 'DEFAULT') { $expected['Solution'] = Get-DefaultSolution }
            $deploy = Get-Call $run 'Deploy-iSOCWorkspace'
            $deploy.Count | Should -Be 1
            Format-Call $deploy[0] | Should -BeExactly (Format-Call $expected)
        }

        It 'fails the step when the stage fails' {
            $run = Invoke-StubbedStep -Path $script:deployPipeline -Step 'Deploy Custom Content (iSOCDeployments)' -Parameters @{ engine = 'module' } -Variables $script:workspaceVariables -Stub $script:deployStub -Environment @{ STUB_EXIT_CODE = '1' }
            $run.ExitCode | Should -Be 1
            (Get-Call $run 'Connect-iSOCWorkspace')[0].Contains('PlaybookResourceGroup') | Should -BeFalse -Because 'an unset playbook group is left out'
        }
    }
}
