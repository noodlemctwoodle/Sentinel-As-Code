#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the summary rule content type's handlers.

.DESCRIPTION
    The handlers are tested on the fixture repository: reading one item
    per file, validation (the messages Deploy-CustomContent.ps1 logged for
    missing fields, a bin size Log Analytics refuses and a destination
    table that is not custom), and the request body with and without its
    optional fields. Every rule under Content/SummaryRules/ in this
    repository is read through the ReadRepo handler, must pass
    Test-iSOCSummaryRule with no issues, and must build a request through
    the ToRequest handler. Parity with Deploy-CustomContent.ps1 was proven
    on release/26.11.0 before the script was removed.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/SummaryRule.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/SummaryRule.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.0
    Last Updated: 2026-11-05
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $ruleFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content/SummaryRules') -Filter '*.json' -Recurse -File) |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'

    function Get-RuleItem {
        param([string] $Repo = $script:fixtureRepo)
        InModuleScope iSOCDeployments -Parameters @{ R = $Repo } {
            param($R)
            $type = Get-iSOCContentTypeDefinition -Name SummaryRule
            Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $R; ContentType = $type }
        }
    }
    function Get-Request {
        param([psobject] $Item)
        InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) ConvertTo-iSOCSummaryRuleRequest -Item $I }
    }
    function Test-Item {
        param([psobject] $Item)
        @(InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) Test-iSOCSummaryRule -Item $I })
    }
    function New-RuleFile {
        param([string] $Json)
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $repo 'Content/SummaryRules') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'Content/SummaryRules/Rule.json') -Value $Json
        @(Get-RuleItem -Repo $repo)[0]
    }

    $script:items = @(Get-RuleItem)
    $script:summary = $script:items | Where-Object { $_.RelativePath -like '*FixtureSummary.json' }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Summary rule handlers' {
    It 'reads one item per file, named by its name in lower case' {
        @($script:items.RelativePath) | Should -Be @(
            'Content/SummaryRules/BadBinSize.json'
            'Content/SummaryRules/FixtureSummary.json'
            'Content/SummaryRules/NoSuffix.json'
        )
        $script:summary.Identity | Should -BeExactly 'fixturesummary'
        $script:summary.Name | Should -Be 'Fixture summary'
    }

    It 'passes a complete rule' {
        Test-Item $script:summary | Should -BeNullOrEmpty
    }

    It 'says what is wrong: <Case>' -ForEach @(
        @{ Case = 'a bin size Log Analytics refuses'; Leaf = 'BadBinSize.json'; Message = "invalid binSize '45'. Allowed values: 20, 30, 60, 120, 180, 360, 720, 1440." }
        @{ Case = 'a destination that is not a custom table'; Leaf = 'NoSuffix.json'; Message = "destinationTable must end with '_CL' suffix." }
    ) {
        Test-Item ($script:items | Where-Object { $_.RelativePath -like "*$Leaf" }) | Should -Be @($Message)
    }

    It 'says which fields a rule needs when one is missing' {
        $item = New-RuleFile -Json '{ "name": "x", "query": "T | count", "destinationTable": "X_CL" }'
        Test-Item $item | Should -Be @('missing required fields (name, query, binSize, destinationTable).')
    }

    It 'reports a file that does not parse as a parse error' {
        $item = New-RuleFile -Json '{ not json'
        @(Test-Item $item)[0] | Should -BeLike 'the JSON does not parse*'
    }

    It 'builds the body the deployer sends, with every optional field the file sets' {
        $request = Get-Request $script:summary
        $request.ResourceName | Should -BeExactly 'FixtureSummary'
        $p = $request.Body.properties
        $p.ruleType | Should -BeExactly 'User'
        $p.displayName | Should -Be 'Fixture summary'
        $p.description | Should -Be 'Hourly sign-ins.'
        $d = $p.ruleDefinition
        $d.query | Should -Be 'SigninLogs | summarize Count = count() by UserPrincipalName'
        $d.binSize | Should -BeOfType [int]
        $d.binSize | Should -Be 60
        $d.binDelay | Should -Be 10
        $d.binStartTime | Should -Not -BeNullOrEmpty
        $d.destinationTable | Should -Be 'FixtureSummary_CL'
    }

    It 'leaves out the optional fields a file does not set' {
        $item = New-RuleFile -Json '{ "name": "Bare", "query": "T | count", "binSize": 20, "destinationTable": "Bare_CL" }'
        $p = (Get-Request $item).Body.properties
        @($p.Keys | Sort-Object) | Should -Be @('ruleDefinition', 'ruleType')
        @($p.ruleDefinition.Keys | Sort-Object) | Should -Be @('binSize', 'destinationTable', 'query')
    }

    It 'sends a bin delay of 0' {
        $item = New-RuleFile -Json '{ "name": "Zero", "query": "T | count", "binSize": 20, "binDelay": 0, "destinationTable": "Zero_CL" }'
        (Get-Request $item).Body.properties.ruleDefinition.binDelay | Should -Be 0
    }
}

Describe 'Content/SummaryRules in this repository' {
    BeforeAll {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        $script:repoType = InModuleScope iSOCDeployments { Get-iSOCContentTypeDefinition -Name SummaryRule }
        function Invoke-RepoHandler {
            param([string] $Handler, [hashtable] $Parameters)
            InModuleScope iSOCDeployments -Parameters @{ T = $script:repoType; H = $Handler; P = $Parameters } {
                param($T, $H, $P)
                Invoke-iSOCContentTypeHandler -ContentType $T -Handler $H -Parameters $P
            }
        }
        $script:repoItems = @{}
        foreach ($item in Invoke-RepoHandler -Handler ReadRepo -Parameters @{ RepoPath = $script:repoRoot; ContentType = $script:repoType }) {
            $script:repoItems[$item.RelativePath] = $item
        }
    }

    It 'reads, validates and builds <Path>' -ForEach $ruleFiles {
        $item = $script:repoItems[$Path]
        $item | Should -Not -BeNullOrEmpty -Because 'the ReadRepo handler reads everything under Content/SummaryRules'
        Test-Item $item | Should -BeNullOrEmpty
        { $script:repoRequest = Invoke-RepoHandler -Handler ToRequest -Parameters @{ Item = $item } } | Should -Not -Throw
        $script:repoRequest.Body | Should -Not -BeNullOrEmpty
    }
}
