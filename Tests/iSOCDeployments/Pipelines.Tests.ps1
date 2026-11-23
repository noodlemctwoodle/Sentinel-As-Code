#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the Azure DevOps pipelines that run the iSOCDeployments
    module.

.DESCRIPTION
    The scripts the module replaced are gone, so each pipeline runs the
    module only. The suite reads the stages and steps each pipeline runs,
    and checks that none of them names a removed script, that the module's
    steps may not set variables or change PATH (the deploy check may set
    only its two outputs), and that the bot commit steps run only from
    main, stage only their own files and take their runtime variables
    through env from read-only variables.

    Then it runs the steps: each step's inline PowerShell is lifted out of
    the YAML unchanged and run in a child pwsh with the variables the agent
    sets. The manifest steps run against a copy of the fixture repository
    holding the module, as a checkout does. The steps that need Azure run
    against stand-ins for the module's commands, which carry the real
    commands' parameter blocks and record what they are given, so the suite
    checks what each pipeline parameter becomes in the module and what the
    step does with the result.

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
    Version:      0.3.2
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+, powershell-yaml
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

    # A checkout as the agent has it: the fixture content and the module.
    function Build-PipelineCheckout {
        <#
        .SYNOPSIS
            Creates a checkout in a new temporary folder holding the fixture content and the module, and returns its path.
        #>
        $checkout = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $checkout 'Modules') | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:fixtureRepo 'Content') -Destination $checkout -Recurse
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'Modules/iSOCDeployments') -Destination (Join-Path $checkout 'Modules') -Recurse
        $checkout
    }

    # Run a step's script in a child pwsh with the variables the agent
    # sets for it, as the agent runs it.
    function Invoke-PipelineStep {
        <#
        .SYNOPSIS
            Runs a step script in a child pwsh with the variables the agent sets for it, and returns its exit code and output.
        .PARAMETER Script
            The text of the step script.
        .PARAMETER Checkout
            The path of the checkout, set as the sources directory.
        .PARAMETER Environment
            Further environment variables for the step.
        .PARAMETER Prelude
            PowerShell text run before the script.
        .PARAMETER TempDirectory
            The agent temporary directory; a new one by default.
        #>
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
        } finally {
            foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
        }
    }

    function Get-StepText {
        <#
        .SYNOPSIS
            Returns the script text of a pipeline step, whichever input holds it, or an empty string.
        .PARAMETER Step
            The pipeline step.
        #>
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
        <#
        .SYNOPSIS
            Returns the parameters of a pipeline file, each value as a string.
        .PARAMETER Path
            The path of the pipeline file.
        .PARAMETER Parameters
            The values the pipeline parameters take instead of their defaults.
        #>
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
        <#
        .SYNOPSIS
            Returns the environment of a step, with its pipeline variable macros and parameter expressions replaced by their values.
        .PARAMETER Step
            The pipeline step.
        .PARAMETER Variables
            The values of the pipeline variables, by name.
        .PARAMETER Rendered
            The rendered parameter values, by name.
        #>
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
        <#
        .SYNOPSIS
            Returns PowerShell text that stubs the named module commands with the real parameter blocks, each recording its call to the file the environment names.
        .PARAMETER Command
            The names of the module commands to stub.
        #>
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
        <#
        .SYNOPSIS
            Runs one step of a pipeline as the agent would, with the stand-ins, and returns its exit code, output and the calls the stubs recorded.
        .PARAMETER Path
            The path of the pipeline file.
        .PARAMETER Step
            The display name of the step.
        .PARAMETER Parameters
            The values the pipeline parameters take instead of their defaults.
        .PARAMETER Variables
            The values of the pipeline variables, by name.
        .PARAMETER Stub
            The names of the module commands to stub.
        .PARAMETER Environment
            Further environment variables for the step.
        .PARAMETER Checkout
            The path of the checkout; a new empty folder by default.
        .PARAMETER TempDirectory
            The agent temporary directory; a new one by default.
        #>
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
        <#
        .SYNOPSIS
            Returns the parameters of each recorded call to a command.
        .PARAMETER Run
            The result of Invoke-StubbedStep.
        .PARAMETER Command
            The name of the command.
        #>
        param($Run, [string] $Command)
        , @($Run.Calls | Where-Object { $_.Command -eq $Command } | ForEach-Object { $_.Parameters })
    }

    function Get-ManifestHash {
        <#
        .SYNOPSIS
            Returns the file hash of the dependencies.json in a checkout.
        .PARAMETER Checkout
            The path of the checkout.
        #>
        param([string] $Checkout)
        (Get-FileHash -LiteralPath (Join-Path $Checkout 'dependencies.json')).Hash
    }

    # A call as canonical JSON: keys in order, so two calls compare as text.
    function Format-Call {
        <#
        .SYNOPSIS
            Returns a recorded call as compressed JSON with its keys sorted.
        .PARAMETER Call
            The recorded parameters of the call.
        #>
        param([System.Collections.IDictionary] $Call)
        $sorted = [ordered]@{}
        foreach ($key in ($Call.Keys | Sort-Object)) { $sorted[$key] = $Call[$key] }
        ConvertTo-Json -InputObject $sorted -Depth 5 -Compress
    }

    $script:moduleStepRule = {
        param([System.Collections.IDictionary] $Step)
        $Step.Contains('target') -and $Step.target.commands -eq 'restricted' -and $Step.target.settableVariables -eq 'none'
    }
}

AfterAll {
    Remove-Module WorkspaceStandIn -ErrorAction SilentlyContinue
}

Describe 'The Azure DevOps pipelines' {
    BeforeDiscovery {
        $script:pipelineFiles = @('Sentinel-Deploy.yml', 'Sentinel-Drift-Detect.yml', 'Sentinel-Dependency-Update.yml', 'Sentinel-PR-Validation.yml', 'Sentinel-DCR-Inventory.yml')
    }

    It 'run none of the removed scripts: <_>' -ForEach $script:pipelineFiles {
        $text = Get-Content -LiteralPath (Join-Path $script:repoRoot "Pipelines/$_") -Raw
        $text | Should -Not -Match 'Deploy/content/|Deploy/permissions/|Setup-ServicePrincipal|Tools/(Build-DependencyManifest|Test-SentinelRuleDrift|Export-SentinelWorkbooks|Import-CommunityRules|ClassicToDcr|DcrFromSchema)|Sentinel\.Common'
    }

    It 'take no engine parameter: <_>' -ForEach $script:pipelineFiles {
        $yaml = Read-PipelineYaml -Path (Join-Path $script:repoRoot "Pipelines/$_")
        @($yaml['parameters'] | Where-Object { $_ -and $_.name -eq 'engine' }).Count | Should -Be 0
    }

    It 'make the bot branches read-only in <_>' -ForEach @('Sentinel-Drift-Detect.yml', 'Sentinel-Dependency-Update.yml') {
        $yaml = Read-PipelineYaml -Path (Join-Path $script:repoRoot "Pipelines/$_")
        foreach ($name in 'syncBranch', 'targetBranch') {
            @($yaml.variables | Where-Object { $_.name -eq $name })[0].readonly | Should -BeTrue -Because $name
        }
    }
}

Describe 'Pipelines/Sentinel-Dependency-Update.yml' {
    BeforeAll {
        $script:updateSteps = @(Get-PipelineStep -Path $script:updatePipeline)
        $script:updateCommit = @($script:updateSteps | Where-Object { $_.displayName -eq 'Commit, Push, and Open PR (when drift detected)' })[0]
        $script:updateCommitText = Get-StepText $script:updateCommit
        $script:updateStep = Get-PipelineInlineScript -Path $script:updatePipeline -Step 'Update the dependency manifest' -Variables @{}
    }

    It 'runs the module update, then the commit step' {
        (@($script:updateSteps | Where-Object { $_.displayName } | ForEach-Object { $_.displayName }) -join '|') | Should -BeExactly 'Install powershell-yaml Module|Update the dependency manifest|Commit, Push, and Open PR (when drift detected)'
    }

    It 'lets neither step set a variable or change PATH' {
        & $script:moduleStepRule @($script:updateSteps | Where-Object { $_.displayName -eq 'Update the dependency manifest' })[0] | Should -BeTrue
        & $script:moduleStepRule $script:updateCommit | Should -BeTrue
    }

    It 'commits only from main, staging only dependencies.json' {
        ($script:updateCommit.condition -replace '\s', '') | Should -BeExactly "and(succeeded(),eq(variables['Build.SourceBranch'],'refs/heads/main'))"
        @([regex]::Matches($script:updateCommitText, '(?m)^\s*git add .*$') | ForEach-Object { $_.Value.Trim() }) -join '|' | Should -BeExactly 'git add dependencies.json'
    }

    It 'takes <Variable> through env, not as a macro' -ForEach @(
        @{ Variable = 'syncBranch'; Env = 'SYNC_BRANCH' }
        @{ Variable = 'targetBranch'; Env = 'TARGET_BRANCH' }
        @{ Variable = 'flagReportOnly'; Env = 'REPORT_ONLY' }
    ) {
        $script:updateCommitText | Should -Not -Match ([regex]::Escape("`$($Variable)"))
        $script:updateCommit.env[$Env] | Should -BeExactly "`$($Variable)"
    }

    It 'names the command that reproduces the manifest' {
        $script:updateCommitText | Should -Match ([regex]::Escape('Re-run Update-iSOCDependencyManifest (Modules/iSOCDeployments) locally to reproduce.'))
    }

    It 'puts no macro in the module step' {
        $script:updateStep | Should -Not -Match '\$\([A-Za-z.]+\)'
    }

    It 'writes the manifest when <Case>, and leaves it current' -ForEach @(
        @{ Case = 'there is none'; Stale = $false }
        @{ Case = 'an entry is missing'; Stale = $true }
    ) {
        $checkout = Build-PipelineCheckout
        if ($Stale) {
            (Invoke-PipelineStep -Script $script:updateStep -Checkout $checkout).ExitCode | Should -Be 0
            $path = Join-Path $checkout 'dependencies.json'
            $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
            $manifest.dependencies.Remove(@($manifest.dependencies.Keys | Sort-Object)[0])
            $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path
        }
        $run = Invoke-PipelineStep -Script $script:updateStep -Checkout $checkout
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match 'dependencies\.json: \d+ entries, written\.'
        $gate = Get-PipelineInlineScript -Path $script:gatePipeline -Step 'Verify dependency manifest' -Variables @{}
        (Invoke-PipelineStep -Script $gate -Checkout $checkout).ExitCode | Should -Be 0
    }

    It 'leaves a current manifest alone' {
        $checkout = Build-PipelineCheckout
        (Invoke-PipelineStep -Script $script:updateStep -Checkout $checkout).ExitCode | Should -Be 0
        $before = Get-ManifestHash $checkout
        $run = Invoke-PipelineStep -Script $script:updateStep -Checkout $checkout
        $run.ExitCode | Should -Be 0
        $run.Output | Should -Match 'dependencies\.json: \d+ entries, already current\.'
        Get-ManifestHash $checkout | Should -BeExactly $before
    }
}

Describe 'Pipelines/Sentinel-PR-Validation.yml' {
    BeforeAll {
        $script:gateSteps = @(Get-PipelineStep -Path $script:gatePipeline)
        $script:gateStep = Get-PipelineInlineScript -Path $script:gatePipeline -Step 'Verify dependency manifest' -Variables @{}
        $script:updateStep = Get-PipelineInlineScript -Path $script:updatePipeline -Step 'Update the dependency manifest' -Variables @{}
    }

    It 'checks the manifest in one step, with the module, unable to set a variable or change PATH' {
        $manifestSteps = @($script:gateSteps | Where-Object { $_.displayName -like 'Verify dependency manifest*' })
        $manifestSteps.Count | Should -Be 1
        (Get-StepText $manifestSteps[0]) | Should -Match 'Test-iSOCDependencyManifest'
        & $script:moduleStepRule $manifestSteps[0] | Should -BeTrue
    }

    It 'puts the Bicep CLI on the PATH before the Pester suites, and runs for playbook changes' {
        $names = @($script:gateSteps | Where-Object { $_.displayName } | ForEach-Object { $_.displayName })
        $names.IndexOf('Put the Bicep CLI on the PATH') | Should -BeGreaterThan -1
        $names.IndexOf('Put the Bicep CLI on the PATH') | Should -BeLessThan $names.IndexOf('Run PR validation')
        $yaml = Read-PipelineYaml -Path $script:gatePipeline
        @($yaml.pr.paths.include) | Should -Contain 'Content/Playbooks'
        @($yaml.trigger.paths.include) | Should -Contain 'Content/Playbooks'
    }

    It 'passes a current manifest' {
        $checkout = Build-PipelineCheckout
        (Invoke-PipelineStep -Script $script:updateStep -Checkout $checkout).ExitCode | Should -Be 0
        $run = Invoke-PipelineStep -Script $script:gateStep -Checkout $checkout
        $run.ExitCode | Should -Be 0 -Because $run.Output
    }

    It 'fails a <Case> manifest, naming the fix' -ForEach @(
        @{ Case = 'stale'; Missing = $false }
        @{ Case = 'missing'; Missing = $true }
    ) {
        $checkout = Build-PipelineCheckout
        if (-not $Missing) {
            (Invoke-PipelineStep -Script $script:updateStep -Checkout $checkout).ExitCode | Should -Be 0
            $path = Join-Path $checkout 'dependencies.json'
            $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
            $manifest.dependencies.Remove(@($manifest.dependencies.Keys | Sort-Object)[0])
            $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path
        }
        $run = Invoke-PipelineStep -Script $script:gateStep -Checkout $checkout
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match ([regex]::Escape('##vso[task.logissue type=error]dependencies.json is out of sync with content.'))
        $run.Output | Should -Match ([regex]::Escape('##vso[task.logissue type=error]Fix: run Update-iSOCDependencyManifest'))
    }
}

Describe 'Pipelines/Sentinel-Drift-Detect.yml' {
    BeforeAll {
        $script:driftSteps = @(Get-PipelineStep -Path $script:driftPipeline)
        $script:driftCommit = @($script:driftSteps | Where-Object { $_.displayName -eq 'Commit, Push, and Open PR (when drift detected)' })[0]
        $script:driftCommitText = Get-StepText $script:driftCommit
        $script:driftStub = 'Connect-iSOCWorkspace', 'Compare-iSOCContent', 'Sync-iSOCContent', 'Export-iSOCDriftReport'
    }

    It 'runs the module''s drift step, then the commit step' {
        (@($script:driftSteps | Where-Object { $_.displayName } | ForEach-Object { $_.displayName }) -join '|') | Should -BeExactly 'Install powershell-yaml Module|Detect Sentinel Rule Drift|Commit, Push, and Open PR (when drift detected)'
    }

    It 'lets neither the drift step nor the commit step, which prints the report, set a variable or change PATH' {
        & $script:moduleStepRule @($script:driftSteps | Where-Object { $_.displayName -eq 'Detect Sentinel Rule Drift' })[0] | Should -BeTrue
        & $script:moduleStepRule $script:driftCommit | Should -BeTrue
    }

    It 'commits only from main, and not when report only' {
        ($script:driftCommit.condition -replace '\s', '') | Should -BeExactly "and(succeeded(),ne(variables['flagReportOnly'],'-ReportOnly'),eq(variables['Build.SourceBranch'],'refs/heads/main'))"
    }

    It 'stages only the rules, the reports and the manifest' {
        @([regex]::Matches($script:driftCommitText, '(?m)^\s*git add .*$') | ForEach-Object { $_.Value.Trim() }) -join '|' | Should -BeExactly 'git add Content/AnalyticalRules reports dependencies.json'
    }

    It 'takes <Variable> through env, not as a macro' -ForEach @(
        @{ Variable = 'syncBranch'; Env = 'SYNC_BRANCH' }
        @{ Variable = 'targetBranch'; Env = 'TARGET_BRANCH' }
    ) {
        $script:driftCommitText | Should -Not -Match ([regex]::Escape("`$($Variable)"))
        $script:driftCommit.env[$Env] | Should -BeExactly "`$($Variable)"
    }

    It 'regenerates the manifest with the module' {
        $script:driftCommitText | Should -Match ([regex]::Escape("Update-iSOCDependencyManifest -RepoPath `$PWD.Path"))
    }

    It 'does what the parameters ask, <Case>' -ForEach @(
        @{ Case = 'with the defaults'; Parameters = @{}; Exclude = ''; Sync = $true; HasDrift = $true; Exit = 0 }
        @{ Case = 'report only'; Parameters = @{ reportOnly = $true }; Exclude = ''; Sync = $false; HasDrift = $true; Exit = 0 }
        @{ Case = 'with every bucket left out'; Parameters = @{ skipContentHub = $true; skipCustom = $true; skipOrphans = $true }; Exclude = 'ContentHub,Custom,Orphan'; Sync = $true; HasDrift = $false; Exit = 0 }
        @{ Case = 'failing on drift, with drift'; Parameters = @{ failOnDrift = $true }; Exclude = ''; Sync = $true; HasDrift = $true; Exit = 1 }
        @{ Case = 'failing on drift, with none'; Parameters = @{ failOnDrift = $true }; Exclude = ''; Sync = $true; HasDrift = $false; Exit = 0 }
    ) {
        $run = Invoke-StubbedStep -Path $script:driftPipeline -Step 'Detect Sentinel Rule Drift' -Parameters $Parameters -Variables $script:workspaceVariables -Stub $script:driftStub -Environment @{ STUB_HAS_DRIFT = "$HasDrift".ToLower() }
        $run.ExitCode | Should -Be $Exit -Because $run.Output

        $connect = Get-Call $run 'Connect-iSOCWorkspace'
        $connect.Count | Should -Be 1
        Format-Call $connect[0] | Should -BeExactly (Format-Call @{ SubscriptionId = $script:workspaceVariables.azureSubscriptionId; ResourceGroup = 'rg-sentinel'; WorkspaceName = 'law-sentinel' })

        $compare = Get-Call $run 'Compare-iSOCContent'
        $compare.Count | Should -Be 1
        $compare[0].RepoPath | Should -Be $run.Checkout
        (@($compare[0].ExcludeSource) -join ',') | Should -BeExactly $Exclude
        (Get-Call $run 'Sync-iSOCContent').Count | Should -Be ([int]$Sync)
        (Get-Call $run 'Export-iSOCDriftReport').Count | Should -Be 1
        if ($Exit) { $run.Output | Should -Match ([regex]::Escape('##vso[task.logissue type=error]Drift detected, and failOnDrift is set.')) }
    }
}

Describe 'Pipelines/Sentinel-Deploy.yml' {
    BeforeAll {
        $script:deploySteps = @(Get-PipelineStep -Path $script:deployPipeline)
        $script:deployStages = @(Get-PipelineStage -Path $script:deployPipeline)
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

        function Get-DefaultSolution {
            <#
            .SYNOPSIS
                Returns the default solutions of the deploy pipeline as a list.
            #>
            $default = @((Read-PipelineYaml -Path $script:deployPipeline).parameters | Where-Object { $_.name -eq 'solutions' })[0].default
            @($default -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
    }

    Context 'Stages and steps' {
        It 'runs these steps' {
            $expected = @(
                'CheckInfrastructure/Check for Existing Resources'
                'DeployInfrastructure/Register Required Resource Providers', 'DeployInfrastructure/Deploy Sentinel Infrastructure with Bicep', 'DeployInfrastructure/Wait for Workspace Indexing'
                'DeployWorkspaceSettings/Install powershell-yaml Module', 'DeployWorkspaceSettings/Deploy Workspace Settings'
                'DeployContentHub/Deploy Content Hub Solutions'
                'DeployCustomContent/Restore Deployment State', 'DeployCustomContent/Install powershell-yaml Module', 'DeployCustomContent/Put the Bicep CLI on the PATH', 'DeployCustomContent/Deploy Custom Content', 'DeployCustomContent/Save Deployment State'
                'DeployDefenderDetections/Install powershell-yaml Module', 'DeployDefenderDetections/Deploy Defender Custom Detections')
            (@($script:deploySteps | Where-Object { $_.displayName } | ForEach-Object { "$($_.PipelineStage)/$($_.displayName)" }) -join '|') | Should -BeExactly ($expected -join '|')
        }

        It 'puts the Bicep CLI on the PATH for the custom content, in a step of its own' {
            $bicep = @($script:deploySteps | Where-Object { $_.displayName -eq 'Put the Bicep CLI on the PATH' })
            $bicep.Count | Should -Be 1
            $bicep[0].PipelineStage | Should -Be 'DeployCustomContent'
            (Get-StepText $bicep[0]) | Should -Match 'az bicep install'
            (Get-StepText $bicep[0]) | Should -Match ([regex]::Escape('##vso[task.prependpath]$HOME/.azure/bin'))
            $bicep[0].Contains('target') | Should -BeFalse -Because 'it must be able to change PATH'
        }

        It 'checks out the repository for the check' {
            @($script:deploySteps | Where-Object { $_.PipelineStage -eq 'CheckInfrastructure' -and $_.Contains('checkout') }).Count | Should -Be 1
        }

        It 'lets each module step set no variable but its own outputs, and read variables through env' {
            $moduleSteps = @($script:deploySteps | Where-Object { (Get-StepText $_) -match 'iSOCDeployments\.psd1' })
            $moduleSteps.Count | Should -Be 5
            foreach ($step in $moduleSteps) {
                $step.target.commands | Should -Be 'restricted' -Because $step.displayName
                $expected = if ($step.displayName -eq 'Check for Existing Resources') { 'RESOURCES_EXIST,DEPLOY_SENTINEL' } else { 'none' }
                (@($step.target.settableVariables) -join ',') | Should -BeExactly $expected -Because $step.displayName
                (Get-StepText $step) | Should -Not -Match '\$\([A-Za-z.]+\)' -Because $step.displayName
            }
        }

        It 'gives the check the name the infrastructure stage reads its output by' {
            @($script:deploySteps | Where-Object { $_.displayName -eq 'Check for Existing Resources' })[0].name | Should -BeExactly 'CheckSentinelResources'
            (@($script:deployStages | Where-Object { $_.stage -eq 'DeployInfrastructure' })[0].condition) | Should -Match ([regex]::Escape("outputs['CheckResources.CheckSentinelResources.RESOURCES_EXIST']"))
        }

        It 'runs the workspace settings after the infrastructure, when it succeeded or did not run' {
            $stage = @($script:deployStages | Where-Object { $_.stage -eq 'DeployWorkspaceSettings' })[0]
            ($stage.dependsOn -join ',') | Should -BeExactly 'CheckInfrastructure,DeployInfrastructure'
            ($stage.condition -replace '\s', '') | Should -BeExactly "or(eq('`${{parameters.deployInfrastructure}}','False'),in(dependencies.DeployInfrastructure.result,'Succeeded','Skipped'))"
        }

        It 'runs the workspace settings before Content Hub, and gates nothing on them' {
            @($script:deployStages | Where-Object { $_.stage -eq 'DeployContentHub' })[0].dependsOn | Should -Contain 'DeployWorkspaceSettings'
            foreach ($stage in $script:deployStages) { [string]$stage.condition | Should -Not -Match 'DeployWorkspaceSettings' -Because $stage.stage }
        }

        It 'reads the check''s DEPLOY_SENTINEL into the Bicep job' {
            $job = @(@($script:deployStages | Where-Object { $_.stage -eq 'DeployInfrastructure' })[0].jobs)[0]
            @($job.variables | Where-Object { $_.name -eq 'deploySentinel' })[0].value | Should -BeExactly "`$[ stageDependencies.CheckInfrastructure.CheckResources.outputs['CheckSentinelResources.DEPLOY_SENTINEL'] ]"
        }

        It 'gives Bicep the playbook group and deploySentinel through env' {
            $bicep = @($script:deploySteps | Where-Object { $_.displayName -eq 'Deploy Sentinel Infrastructure with Bicep' })[0]
            $text = Get-StepText $bicep
            $bicep.env.PLAYBOOK_RESOURCE_GROUP | Should -BeExactly '$(playbookResourceGroup)'
            $bicep.env.DEPLOY_SENTINEL | Should -BeExactly '$(deploySentinel)'
            $text | Should -Not -Match ([regex]::Escape('$(playbookResourceGroup)'))
            $text | Should -Match ([regex]::Escape('PARAMS="$PARAMS deploySentinel=$DEPLOY_SENTINEL"'))
            $text | Should -Match ([regex]::Escape('true|false)'))
        }
    }

    Context 'The check, run' {
        It 'reports <Status>' -ForEach @(
            @{ Status = 'Onboarded'; Needed = $false; Sentinel = $false; Code = 0; Exist = 'true'; Deploy = 'false' }
            @{ Status = 'NotOnboarded'; Needed = $true; Sentinel = $true; Code = 0; Exist = 'false'; Deploy = 'true' }
            @{ Status = 'StateMissing'; Needed = $true; Sentinel = $true; Code = 0; Exist = 'false'; Deploy = 'true' }
            @{ Status = 'SolutionMissing'; Needed = $false; Sentinel = $false; Code = 1; Exist = 'true'; Deploy = 'false' }
        ) {
            $onboarding = ConvertTo-Json -Compress -InputObject @{ Status = $Status; InfrastructureNeeded = $Needed; DeploySentinel = $Sentinel; ExitCode = $Code }
            $run = Invoke-StubbedStep -Path $script:deployPipeline -Step 'Check for Existing Resources' -Variables $script:workspaceVariables -Stub $script:deployStub -Environment @{ STUB_ONBOARDING = $onboarding }
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
            $run = Invoke-StubbedStep -Path $script:deployPipeline -Step 'Check for Existing Resources' -Variables $variables -Stub $script:deployStub -Environment @{ STUB_ONBOARDING = $onboarding }
            $run.ExitCode | Should -Be 0 -Because $run.Output
            (Get-Call $run 'Get-iSOCWorkspaceOnboarding')[0].PlaybookResourceGroup | Should -BeExactly $Expected
        }
    }

    Context 'The stages, run' {
        It 'deploys <Name> with <Case>' -ForEach @(
            @{ Name = 'the settings'; Case = 'the defaults'; Step = 'Deploy Workspace Settings'; Parameters = @{}; Expected = @{ Stage = @('WorkspaceSettings') } }
            @{ Name = 'the settings'; Case = 'a dry run'; Step = 'Deploy Workspace Settings'; Parameters = @{ whatIf = $true }; Expected = @{ Stage = @('WorkspaceSettings'); WhatIf = $true } }
            @{ Name = 'the Content Hub solutions'; Case = 'the defaults'; Step = 'Deploy Content Hub Solutions'; Parameters = @{}; Expected = @{ Stage = @('ContentHub'); Solution = 'DEFAULT'; Severity = @('High', 'Medium', 'Low', 'Informational'); DisableRules = $true } }
            @{ Name = 'the Content Hub solutions'; Case = 'every parameter switched'; Step = 'Deploy Content Hub Solutions'; Parameters = 'SWITCHED'; Expected = @{ Stage = @('ContentHub'); Solution = @('Azure Activity', 'Microsoft Entra ID'); Severity = @('High', 'Medium'); OverwriteCustomisedRules = $true; ExcludeSolutionContentType = @('AnalyticsRule', 'Workbook', 'AutomationRule', 'HuntingQuery'); ForceSolutionUpdate = $true; ForceContentDeployment = $true; WhatIf = $true } }
            @{ Name = 'the custom content'; Case = 'the defaults'; Step = 'Deploy Custom Content'; Parameters = @{}; Expected = @{ Stage = @('CustomContent'); Exclude = @('Content/AnalyticalRules/Community/*'); SmartDeployment = $true } }
            @{ Name = 'the custom content'; Case = 'every parameter switched'; Step = 'Deploy Custom Content'; Parameters = 'SWITCHED'; Expected = @{ Stage = @('CustomContent'); ExcludeContentType = @('Parser', 'AnalyticsRule', 'Watchlist', 'Playbook', 'Workbook', 'HuntingQuery', 'AutomationRule', 'SummaryRule'); WhatIf = $true } }
            @{ Name = 'the Defender detections'; Case = 'the defaults'; Step = 'Deploy Defender Custom Detections'; Parameters = @{}; Expected = @{ Stage = @('DefenderDetections') } }
            @{ Name = 'the Defender detections'; Case = 'a dry run'; Step = 'Deploy Defender Custom Detections'; Parameters = @{ whatIf = $true }; Expected = @{ Stage = @('DefenderDetections'); WhatIf = $true } }
        ) {
            $given = if ($Parameters -eq 'SWITCHED') { $script:switched.Clone() } else { $Parameters }
            $variables = $script:workspaceVariables.Clone()
            $variables['playbookResourceGroup'] = 'rg-playbooks'
            $run = Invoke-StubbedStep -Path $script:deployPipeline -Step $Step -Parameters $given -Variables $variables -Stub $script:deployStub -Environment @{ STUB_EXIT_CODE = '0' }
            $run.ExitCode | Should -Be 0 -Because $run.Output

            Format-Call (Get-Call $run 'Connect-iSOCWorkspace')[0] | Should -BeExactly (Format-Call @{ SubscriptionId = $script:workspaceVariables.azureSubscriptionId; ResourceGroup = 'rg-sentinel'; WorkspaceName = 'law-sentinel'; PlaybookResourceGroup = 'rg-playbooks' })

            $expected = $Expected.Clone()
            $expected['RepoPath'] = $run.Checkout
            if ($expected['Solution'] -eq 'DEFAULT') { $expected['Solution'] = Get-DefaultSolution }
            $deploy = Get-Call $run 'Deploy-iSOCWorkspace'
            $deploy.Count | Should -Be 1
            Format-Call $deploy[0] | Should -BeExactly (Format-Call $expected)
        }

        It 'fails the step when the stage fails, leaving out an unset playbook group' {
            $run = Invoke-StubbedStep -Path $script:deployPipeline -Step 'Deploy Custom Content' -Variables $script:workspaceVariables -Stub $script:deployStub -Environment @{ STUB_EXIT_CODE = '1' }
            $run.ExitCode | Should -Be 1
            (Get-Call $run 'Connect-iSOCWorkspace')[0].Contains('PlaybookResourceGroup') | Should -BeFalse
        }
    }
}
