#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the iSOCDeployments module's manifest, help, file
    layout and the rules its code keeps to.

.DESCRIPTION
    Holds the module to the shape its design depends on:

    - the manifest exports one command per file in Public/, declares no
      required modules and carries a version no older than the newest
      release;
    - every public command has a synopsis, a description, an example and a
      description for each parameter, and keeps the product name out of
      its name and synopsis;
    - every file opens with the PowerShell floor and names its own path,
      defines exactly one function named after the file, and is ASCII;
    - the code never calls exit or installs a module, calls Az cmdlets only
      from Private/Az/ and REST only from Private/Rest/, writes to the
      console only through Write-iSOCLog, and never refers to
      Sentinel.Common or the iSOC Blueprint, which stays a separate module;
    - the prerequisite command reports the requirement table.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Module.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Module.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.3.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $moduleRoot = Join-Path $repoRoot 'Modules/iSOCDeployments'
    $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot 'iSOCDeployments.psd1')
    $commands = @($manifest.FunctionsToExport | ForEach-Object { @{ Name = $_ } })
    $functionFiles = @(Get-ChildItem -LiteralPath (Join-Path $moduleRoot 'Public'), (Join-Path $moduleRoot 'Private') -Filter '*.ps1' -File -Recurse) |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
    $allFiles = @(Get-ChildItem -LiteralPath $moduleRoot -File -Recurse) |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:moduleRoot = Join-Path $script:repoRoot 'Modules/iSOCDeployments'
    Import-Module (Join-Path $script:moduleRoot 'iSOCDeployments.psd1') -Force
    $script:manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:moduleRoot 'iSOCDeployments.psd1')

    $script:codeFiles = @(Get-ChildItem -LiteralPath $script:moduleRoot -Include '*.ps1', '*.psm1', '*.psd1' -File -Recurse)
    function Get-CommandCall {
        param([string] $Pattern)
        foreach ($file in $script:codeFiles) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            foreach ($call in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $name = $call.GetCommandName()
                if ($name -and $name -match $Pattern) {
                    [pscustomobject]@{
                        Command = $name
                        Path    = [System.IO.Path]::GetRelativePath($script:repoRoot, $file.FullName).Replace('\', '/')
                        Line    = $call.Extent.StartLineNumber
                    }
                }
            }
        }
    }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Manifest' {
    It 'is a valid module manifest' {
        { Test-ModuleManifest -Path (Join-Path $script:moduleRoot 'iSOCDeployments.psd1') -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports one command per file in Public/' {
        $files = @(Get-ChildItem -LiteralPath (Join-Path $script:moduleRoot 'Public') -Filter '*.ps1' -File | ForEach-Object BaseName | Sort-Object)
        @($script:manifest.FunctionsToExport | Sort-Object) | Should -Be $files
    }

    It 'exports exactly the listed commands once imported, and none of the private helpers' {
        @((Get-Module iSOCDeployments).ExportedFunctions.Keys | Sort-Object) | Should -Be @($script:manifest.FunctionsToExport | Sort-Object)
        Get-Command Write-iSOCLog -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command Invoke-iSOCRestRequest -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'declares no required modules, so reading content offline needs none' {
        $script:manifest.ContainsKey('RequiredModules') | Should -BeFalse
    }

    It 'has a CalVer version no older than the newest release in the CHANGELOG' {
        $script:manifest.ModuleVersion | Should -Match '^\d{2}\.\d{1,2}\.\d+$'
        $changelog = Get-Content -LiteralPath (Join-Path $script:repoRoot 'Docs/Releases/CHANGELOG.md')
        $released = @($changelog | ForEach-Object { if ($_ -match '^## (\d+\.\d+(?:\.\d+)?)\b') { [version]$Matches[1] } } | Sort-Object -Descending)
        $released.Count | Should -BeGreaterThan 0
        [version]$script:manifest.ModuleVersion | Should -BeGreaterOrEqual $released[0]
    }
}

Describe 'Help for <Name>' -ForEach $commands {
    BeforeAll {
        $script:help = Get-Help $Name -Full
        $script:command = Get-Command $Name
    }

    It 'has a synopsis, a description and an example' {
        $script:help.Synopsis | Should -Not -BeNullOrEmpty
        $script:help.Synopsis | Should -Not -Match "^\s*$([regex]::Escape($Name))"
        ($script:help.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty
        @($script:help.Examples.Example).Count | Should -BeGreaterThan 0
    }

    It 'documents every parameter' {
        $common = [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
        foreach ($p in $script:command.Parameters.Keys | Where-Object { $_ -notin $common }) {
            $entry = @($script:help.Parameters.Parameter | Where-Object Name -eq $p)
            ($entry.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty -Because "-$p needs a description"
        }
    }

    It 'keeps the product name out of its name and synopsis' {
        $Name | Should -Not -Match 'Sentinel'
        $script:help.Synopsis | Should -Not -Match 'Sentinel'
    }

    It 'uses the iSOC noun prefix' {
        $Name | Should -Match '^[A-Z][a-z]+-iSOC[A-Z]'
    }
}

Describe 'File <Path>' -ForEach $functionFiles {
    BeforeAll {
        $script:full = Join-Path $script:repoRoot $Path
        $script:text = Get-Content -LiteralPath $script:full -Raw
        $errors = $null
        $script:ast = [System.Management.Automation.Language.Parser]::ParseFile($script:full, [ref]$null, [ref]$errors)
        $script:parseErrors = @($errors)
    }

    It 'parses' {
        @($script:parseErrors | ForEach-Object { "$($_.Message) (line $($_.Extent.StartLineNumber))" }) | Should -BeNullOrEmpty
    }

    It 'opens with the PowerShell floor and names its own path' {
        $script:text | Should -Match '^#Requires -Version 7\.6\r?\n'
        $script:text | Should -Match ("(?m)^\s*File:\s+" + [regex]::Escape($Path) + '\s*$')
    }

    It 'declares no module in #Requires, so the module imports without it' {
        $script:ast.ScriptRequirements.RequiredModules | Should -BeNullOrEmpty
    }

    It 'defines exactly one function, named after the file, and nothing else' {
        $statements = @($script:ast.EndBlock.Statements)
        $statements.Count | Should -Be 1
        $statements[0] | Should -BeOfType ([System.Management.Automation.Language.FunctionDefinitionAst])
        $statements[0].Name | Should -BeExactly ([System.IO.Path]::GetFileNameWithoutExtension($Path))
        $script:ast.ParamBlock | Should -BeNullOrEmpty
        $script:ast.BeginBlock | Should -BeNullOrEmpty
        $script:ast.ProcessBlock | Should -BeNullOrEmpty
    }
}

Describe 'Module file <Path>' -ForEach $allFiles {
    It 'is ASCII, with no em-dash or section sign' {
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $script:repoRoot $Path))
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }

    It 'does not refer to the iSOC Blueprint module' {
        Get-Content -LiteralPath (Join-Path $script:repoRoot $Path) -Raw | Should -Not -Match 'Modules[\\/]iSOCBlueprint'
    }
}

Describe 'Code rules' {
    It 'never calls exit' {
        $exits = foreach ($file in $script:codeFiles) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExitStatementAst] }, $true) |
                ForEach-Object { "$($file.Name):$($_.Extent.StartLineNumber)" }
        }
        @($exits) | Should -BeNullOrEmpty
    }

    It 'never installs a module' {
        @(Get-CommandCall -Pattern '^(Install-Module|Install-PSResource|Save-Module|Update-Module)$') | Should -BeNullOrEmpty
    }

    It 'calls Az cmdlets only from Private/Az/, and Invoke-AzRestMethod only from Private/Rest/' {
        $azCalls = @(Get-CommandCall -Pattern '^[A-Za-z]+-Az[A-Z]')
        $azCalls.Count | Should -BeGreaterThan 0
        foreach ($call in $azCalls) {
            $folder = if ($call.Command -eq 'Invoke-AzRestMethod') { 'Modules/iSOCDeployments/Private/Rest/' } else { 'Modules/iSOCDeployments/Private/Az/' }
            $call.Path | Should -BeLike "$folder*" -Because "$($call.Command) at $($call.Path):$($call.Line)"
        }
    }

    It 'runs Microsoft Graph SDK commands only from Private/Graph/' {
        $mgCalls = @(Get-CommandCall -Pattern '^[A-Za-z]+-Mg[A-Z]')
        $mgCalls.Count | Should -BeGreaterThan 0
        foreach ($call in $mgCalls) { $call.Path | Should -BeLike 'Modules/iSOCDeployments/Private/Graph/*' -Because "$($call.Command) at $($call.Path):$($call.Line)" }
    }

    It 'runs git only from Private/Git/' {
        $gitCalls = @(Get-CommandCall -Pattern '^git(\.exe)?$')
        $gitCalls.Count | Should -BeGreaterThan 0
        foreach ($call in $gitCalls) { $call.Path | Should -Be 'Modules/iSOCDeployments/Private/Git/Invoke-iSOCGit.ps1' -Because "git at $($call.Path):$($call.Line)" }
    }

    It 'runs the Bicep CLI only from Private/Bicep/Invoke-iSOCBicep.ps1' {
        $bicepCalls = @(Get-CommandCall -Pattern '^bicep(\.exe)?$')
        $bicepCalls.Count | Should -BeGreaterThan 0
        foreach ($call in $bicepCalls) { $call.Path | Should -Be 'Modules/iSOCDeployments/Private/Bicep/Invoke-iSOCBicep.ps1' -Because "bicep at $($call.Path):$($call.Line)" }
    }

    It 'makes a web request other than through Invoke-AzRestMethod only from Private/Http/' {
        foreach ($call in @(Get-CommandCall -Pattern '^(Invoke-RestMethod|Invoke-WebRequest|irm|iwr|curl|wget)$')) {
            $call.Path | Should -Be 'Modules/iSOCDeployments/Private/Http/Invoke-iSOCHttpRequest.ps1' -Because "$($call.Command) at $($call.Path):$($call.Line)"
        }
    }

    It 'writes to the console only through Write-iSOCLog' {
        foreach ($call in @(Get-CommandCall -Pattern '^Write-Host$')) {
            $call.Path | Should -Be 'Modules/iSOCDeployments/Private/Core/Write-iSOCLog.ps1'
        }
    }

    It 'never uses the member-name form of ForEach-Object, which returns nothing under -WhatIf' {
        $found = foreach ($file in $script:codeFiles) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            foreach ($call in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                if ($call.GetCommandName() -notin 'ForEach-Object', '%', 'foreach') { continue }
                $arguments = @($call.CommandElements | Select-Object -Skip 1)
                $memberName = @($arguments | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -like 'M*' })
                $bare = @($arguments | Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] })
                if ($memberName.Count -or $bare.Count) { "$($file.Name):$($call.Extent.StartLineNumber)" }
            }
        }
        @($found) | Should -BeNullOrEmpty
    }

    It 'never uses Sentinel.Common or its commands' {
        $text = ($script:codeFiles | ForEach-Object {
                $tokens = $null
                [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$null)
                $tokens | Where-Object Kind -ne 'Comment' | ForEach-Object Text
            }) -join ' '
        $text | Should -Not -Match 'Sentinel\.Common'
        @(Get-CommandCall -Pattern '^(Write-PipelineMessage|Invoke-SentinelApi|Connect-AzureEnvironment)$') | Should -BeNullOrEmpty
    }

    It 'never imports the iSOC Blueprint' {
        @(Get-CommandCall -Pattern '^Import-Module$' | Where-Object { (Get-Content -LiteralPath (Join-Path $script:repoRoot $_.Path))[$_.Line - 1] -match 'iSOCBlueprint' }) |
            Should -BeNullOrEmpty
    }
}

Describe 'Prerequisites' {
    BeforeAll {
        $script:requirements = @(InModuleScope iSOCDeployments { Get-iSOCRequirement })
    }

    It 'lists every step the command accepts, and only those' {
        $steps = @($script:requirements | ForEach-Object Step | Sort-Object -Unique)
        $accepted = (Get-Command Test-iSOCDeploymentPrerequisite).Parameters['Step'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
            ForEach-Object ValidValues
        @($accepted | Sort-Object) | Should -Be $steps
    }

    It 'returns one result per requirement with the documented properties' {
        $all = @(Test-iSOCDeploymentPrerequisite)
        $all.Count | Should -Be $script:requirements.Count
        foreach ($p in 'Name', 'Step', 'Required', 'Found', 'Version', 'Detail') { $all[0].PSObject.Properties.Name | Should -Contain $p }
    }

    It 'limits the list to the steps asked for' {
        $read = @(Test-iSOCDeploymentPrerequisite -Step Read)
        @($read | Where-Object Name -like 'powershell-yaml*').Count | Should -Be 1
        @($read | Where-Object Name -like 'Az.*').Count | Should -Be 0
        foreach ($r in $read) { $r.Step | Should -Be @('Read') }
    }

    It 'answers yes or no with -Quiet' {
        Test-iSOCDeploymentPrerequisite -Step Read -Quiet | Should -BeOfType [bool]
    }

    It 'pins powershell-yaml to the version the pipelines install' {
        ($script:requirements | Where-Object Name -eq 'powershell-yaml').MinimumVersion | Should -Be '0.4.12'
    }
}
