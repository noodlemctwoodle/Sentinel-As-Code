#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }, powershell-yaml

<#
.SYNOPSIS
    Pester tests that the Blueprint pipelines call the iSOCBlueprint module
    correctly.

.DESCRIPTION
    The Blueprint pipelines run the module from inline PowerShell in YAML,
    where a wrong command or parameter name only shows up in a pipeline
    run. This suite pulls every inline script out of the Azure DevOps
    pipeline and the two GitHub workflows, stands in for the pipeline
    macros, parses the PowerShell and checks each call to an iSOCBlueprint
    command: the command is exported, every named parameter and every key
    of a splatted table binds to it, and the module is imported earlier in
    the same script. It also fails when a step still runs a script from
    Tools/Blueprint.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Pipelines.Tests.ps1 -Output Detailed

    Lists every pipeline step checked.

.NOTES
    File:         Tests/iSOCBlueprint/Pipelines.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module powershell-yaml -ErrorAction Stop
    $pipelines = 'Pipelines/Sentinel-Blueprint.yml', '.github/workflows/sentinel-blueprint.yml', '.github/workflows/sentinel-sharepoint-publish.yml'

    $scriptKeys = 'script', 'Inline', 'inlineScript', 'run'
    $collect = {
        param($Node, [string] $Pipeline, [string] $Step)
        if ($Node -is [System.Collections.IDictionary]) {
            $name = foreach ($k in 'displayName', 'name') { if ($Node.Contains($k) -and $Node[$k] -is [string]) { $Node[$k]; break } }
            if ($name) { $Step = $name }
            foreach ($key in @($Node.Keys)) {
                $value = $Node[$key]
                if ($key -in $scriptKeys -and $value -is [string] -and $value -match '\n') {
                    @{ Pipeline = $Pipeline; Step = $Step; Script = $value }
                }
                else { & $collect $value $Pipeline $Step }
            }
        }
        elseif ($Node -is [System.Collections.IList]) { foreach ($item in $Node) { & $collect $item $Pipeline $Step } }
    }

    $steps = foreach ($p in $pipelines) {
        $doc = Get-Content -LiteralPath (Join-Path $repoRoot $p) -Raw | ConvertFrom-Yaml
        & $collect $doc $p ''
    }
    $moduleSteps = @($steps | Where-Object { $_.Script -match '-iSOCBlueprint' })
    $allSteps = @($steps)
}

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'Modules/iSOCBlueprint/iSOCBlueprint.psd1') -Force
    $script:exported = @((Get-Module iSOCBlueprint).ExportedFunctions.Keys)

    function ConvertTo-ParsableScript {
        # Stand in for the pipeline macros: $(Name) in Azure DevOps (a
        # -WhatIf style flag becomes nothing) and ${{ expr }} in both.
        param([string] $Text)
        $Text = [regex]::Replace($Text, '\$\((flag[A-Za-z0-9_]*)\)', '')
        $Text = [regex]::Replace($Text, '\$\(([A-Za-z_][A-Za-z0-9_.]*)\)', 'macro')
        [regex]::Replace($Text, '\$\{\{[^}]*\}\}', 'macro')
    }

    function Get-SplatKey {
        # Keys a script puts in the table it splats: the literal's keys and
        # any $t['Key'] = / $t.Key = assignments.
        param($Ast, [string] $Name)
        $keys = [System.Collections.Generic.List[string]]::new()
        foreach ($a in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
            $left = $a.Left
            if ($left -is [System.Management.Automation.Language.VariableExpressionAst] -and $left.VariablePath.UserPath -eq $Name) {
                foreach ($h in $a.Right.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true) | Select-Object -First 1) {
                    foreach ($pair in $h.KeyValuePairs) { $keys.Add($pair.Item1.SafeGetValue()) }
                }
            }
            elseif ($left -is [System.Management.Automation.Language.IndexExpressionAst] -and $left.Target.VariablePath.UserPath -eq $Name) {
                $keys.Add($left.Index.SafeGetValue())
            }
            elseif ($left -is [System.Management.Automation.Language.MemberExpressionAst] -and $left.Expression.VariablePath.UserPath -eq $Name) {
                $keys.Add($left.Member.Value)
            }
        }
        $keys
    }
}

Describe 'Blueprint pipelines' {
    It 'finds the module steps in the three pipelines' -TestCases @(@{ Found = $moduleSteps.Count }) {
        $Found | Should -BeGreaterOrEqual 10
    }

    It '<Pipeline> "<Step>" runs no script from Tools/Blueprint' -ForEach $allSteps {
        $Script | Should -Not -Match 'Tools/Blueprint/[^\s''"]+\.ps1'
    }

    It '<Pipeline> "<Step>" calls the module with parameters that bind' -ForEach $moduleSteps {
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput((ConvertTo-ParsableScript $Script), [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty

        $commands = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))
        $import = $commands | Where-Object { $_.GetCommandName() -eq 'Import-Module' -and $_.Extent.Text -match 'iSOCBlueprint\.psd1' } | Select-Object -First 1
        $calls = @($commands | Where-Object { $_.GetCommandName() -match '-iSOCBlueprint' })
        $calls.Count | Should -BeGreaterThan 0
        $import | Should -Not -BeNullOrEmpty -Because 'the module is imported before it is used'

        foreach ($call in $calls) {
            $name = $call.GetCommandName()
            $name | Should -BeIn $script:exported
            $import.Extent.StartOffset | Should -BeLessThan $call.Extent.StartOffset -Because "the module is imported before $name"
            $parameters = (Get-Command $name).Parameters
            $known = @($parameters.Keys) + @($parameters.Values | ForEach-Object Aliases)
            foreach ($p in $call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] }) {
                $p.ParameterName | Should -BeIn $known -Because "$name takes -$($p.ParameterName)"
            }
            foreach ($splat in $call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Splatted }) {
                $keys = @(Get-SplatKey -Ast $ast -Name $splat.VariablePath.UserPath)
                $keys.Count | Should -BeGreaterThan 0 -Because "@$($splat.VariablePath.UserPath) is built in the same step"
                foreach ($k in $keys) { $k | Should -BeIn $known -Because "$name takes -$k from @$($splat.VariablePath.UserPath)" }
            }
        }
    }
}
