#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the module's YAML helpers: loading powershell-yaml,
    reading files and writing scalars and nested blocks.

.DESCRIPTION
    The writers are held to explicit text for a set of awkward values and
    a nested block, and every rule name in the repository must read back
    as itself. They were copied from Tools/Test-SentinelRuleDrift.ps1, and
    parity with that script was proven on release/26.11.0 before it was
    removed. The loader is tested for the module's rule that it never
    installs anything (MIGRATION.md edit E4).

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Yaml.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Yaml.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.2.0
    Last Updated: 2026-11-05
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module powershell-yaml -ErrorAction Stop

    $script:values = @(
        '', 'plain', 'with: colon', '# hash', '- dash', '?question', ' leading', 'trailing ', "it's", 'say "hi"',
        '100%', '@user', 'a, b', '[x]', '{y}', 'a | b', 'a > b', '*star', '&anchor', '!tag', 'back`tick', 'multi word value'
    )
    $script:values += @(Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'Content/AnalyticalRules') -Recurse -File -Include '*.yaml', '*.yml' |
            ForEach-Object { [string](ConvertFrom-Yaml (Get-Content -LiteralPath $_.FullName -Raw)).name })
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-iSOCYamlScalar' {
    It 'quotes <Value> as <Expected>' -ForEach @(
        @{ Value = 'plain'; Expected = 'plain' }
        @{ Value = 'with: colon'; Expected = "'with: colon'" }
        @{ Value = "it's: here"; Expected = "'it''s: here'" }
        @{ Value = '- dash'; Expected = "'- dash'" }
        @{ Value = ''; Expected = "''" }
    ) {
        InModuleScope iSOCDeployments -Parameters @{ V = $Value } { param($V) ConvertTo-iSOCYamlScalar $V } | Should -BeExactly $Expected
    }

    It 'writes the awkward value <Value> as <Expected>' -ForEach @(
        @{ Value = '# hash'; Expected = "'# hash'" }
        @{ Value = '?question'; Expected = "'?question'" }
        @{ Value = ' leading'; Expected = "' leading'" }
        @{ Value = 'trailing '; Expected = "'trailing '" }
        @{ Value = 'say "hi"'; Expected = '''say "hi"''' }
        @{ Value = '100%'; Expected = "'100%'" }
        @{ Value = '@user'; Expected = "'@user'" }
        @{ Value = '[x]'; Expected = "'[x]'" }
        @{ Value = 'a | b'; Expected = "'a | b'" }
        @{ Value = 'multi word value'; Expected = 'multi word value' }
    ) {
        InModuleScope iSOCDeployments -Parameters @{ V = $Value } { param($V) ConvertTo-iSOCYamlScalar $V } | Should -BeExactly $Expected
    }

    It 'writes a value that reads back as itself' {
        foreach ($value in $script:values | Where-Object { $_ }) {
            $yaml = "name: $(InModuleScope iSOCDeployments -Parameters @{ V = $value } { param($V) ConvertTo-iSOCYamlScalar $V })"
            (ConvertFrom-Yaml $yaml).name | Should -BeExactly $value -Because "the value was '$value'"
        }
    }
}

Describe 'ConvertTo-iSOCYamlSubtree' {
    BeforeAll {
        $script:tree = [ordered]@{
            entityMappings = @(
                [ordered]@{ entityType = 'Account'; fieldMappings = @([ordered]@{ identifier = 'FullName'; columnName = 'UserPrincipalName' }) }
            )
            grouping = [ordered]@{ enabled = $false; lookbackDuration = 'PT5H' }
        }
    }

    It 'indents every non-empty line and drops the trailing newline' {
        $text = InModuleScope iSOCDeployments -Parameters @{ T = $script:tree } { param($T) ConvertTo-iSOCYamlSubtree -Object $T -Indent 2 }
        $text | Should -Not -Match '\n$'
        foreach ($line in $text -split "`n" | Where-Object { $_ }) { $line | Should -Match '^  \S|^   ' }
    }

    It 'writes the block at <Indent> spaces' -ForEach @(@{ Indent = 0 }, @{ Indent = 2 }, @{ Indent = 4 }) {
        $prefix = ' ' * $Indent
        $expected = @(
            'entityMappings:'
            '- entityType: Account'
            '  fieldMappings:'
            '  - identifier: FullName'
            '    columnName: UserPrincipalName'
            'grouping:'
            '  enabled: false'
            '  lookbackDuration: PT5H'
        ) | ForEach-Object { "$prefix$_" }
        $new = InModuleScope iSOCDeployments -Parameters @{ T = $script:tree; I = $Indent } { param($T, $I) ConvertTo-iSOCYamlSubtree -Object $T -Indent $I }
        $new | Should -BeExactly ($expected -join "`n")
    }
}

Describe 'Read-iSOCYamlFile' {
    It 'reads a mapping as a hashtable, or keeps the key order with -Ordered' {
        $path = Join-Path $TestDrive 'rule.yaml'
        Set-Content -LiteralPath $path -Value "zeta: 1`nalpha: 2`nmiddle: 3"
        $plain = InModuleScope iSOCDeployments -Parameters @{ P = $path } { param($P) Read-iSOCYamlFile -Path $P }
        $plain | Should -BeOfType [hashtable]
        $ordered = InModuleScope iSOCDeployments -Parameters @{ P = $path } { param($P) Read-iSOCYamlFile -Path $P -Ordered }
        @($ordered.Keys) | Should -Be @('zeta', 'alpha', 'middle')
    }

    It 'returns nothing for an empty file' {
        $path = Join-Path $TestDrive 'empty.yaml'
        Set-Content -LiteralPath $path -Value ''
        InModuleScope iSOCDeployments -Parameters @{ P = $path } { param($P) Read-iSOCYamlFile -Path $P } | Should -BeNullOrEmpty
    }

    It 'throws the parser''s message for a file that does not parse' {
        $path = Join-Path $TestDrive 'broken.yaml'
        Set-Content -LiteralPath $path -Value "id: [unclosed`nname: x"
        { InModuleScope iSOCDeployments -Parameters @{ P = $path } { param($P) Read-iSOCYamlFile -Path $P } } | Should -Throw
    }
}

Describe 'Import-iSOCYamlModule' {
    It 'does nothing when ConvertFrom-Yaml is already there' {
        Mock -ModuleName iSOCDeployments Import-Module { }
        InModuleScope iSOCDeployments { Import-iSOCYamlModule }
        Should -Invoke -ModuleName iSOCDeployments Import-Module -Times 0 -Exactly
    }

    It 'loads the newest installed version at or above the minimum' {
        Mock -ModuleName iSOCDeployments Get-Command { } -ParameterFilter { $Name -eq 'ConvertFrom-Yaml' }
        Mock -ModuleName iSOCDeployments Get-Module {
            [pscustomobject]@{ Version = [version]'0.4.7'; Path = '/old/powershell-yaml.psd1' }
            [pscustomobject]@{ Version = [version]'0.4.12'; Path = '/new/powershell-yaml.psd1' }
        } -ParameterFilter { $ListAvailable -and $Name -eq 'powershell-yaml' }
        Mock -ModuleName iSOCDeployments Import-Module { }
        InModuleScope iSOCDeployments { Import-iSOCYamlModule }
        Should -Invoke -ModuleName iSOCDeployments Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq '/new/powershell-yaml.psd1' }
    }

    It 'says how to install it when no version is new enough, and installs nothing' {
        Mock -ModuleName iSOCDeployments Get-Command { } -ParameterFilter { $Name -eq 'ConvertFrom-Yaml' }
        Mock -ModuleName iSOCDeployments Get-Module { [pscustomobject]@{ Version = [version]'0.4.7'; Path = '/old/powershell-yaml.psd1' } } -ParameterFilter { $ListAvailable }
        Mock -ModuleName iSOCDeployments Import-Module { }
        { InModuleScope iSOCDeployments { Import-iSOCYamlModule } } | Should -Throw -ExpectedMessage '*powershell-yaml 0.4.12 or later*Install-Module powershell-yaml -RequiredVersion 0.4.12*'
        Should -Invoke -ModuleName iSOCDeployments Import-Module -Times 0 -Exactly
    }
}
