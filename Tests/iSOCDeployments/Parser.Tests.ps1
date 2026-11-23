#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the parser content type's handlers.

.DESCRIPTION
    The handlers are tested on the fixture repository: reading, validation
    (the message Deploy-CustomContent.ps1 logged) and the saved search
    body. Every parser under Content/Parsers/ in this repository is read
    through the ReadRepo handler, must pass Test-iSOCParser with no issues,
    and must build a request through the ToRequest handler. Parity with
    Deploy-CustomContent.ps1 was proven on release/26.11.0 before the
    script was removed.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Parser.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Parser.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+, powershell-yaml
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $parserFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content/Parsers') -Recurse -File -Include '*.yaml', '*.yml') |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module powershell-yaml -ErrorAction Stop
    $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'

    function Get-ParserItem {
        <#
        .SYNOPSIS
            Reads the parser items of a repository with the ReadRepo handler of the Parser content type.
        .PARAMETER Repo
            The repository path; the fixture repository by default.
        #>
        param([string] $Repo = $script:fixtureRepo)
        InModuleScope iSOCDeployments -Parameters @{ R = $Repo } {
            param($R)
            $type = Get-iSOCContentTypeDefinition -Name Parser
            Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $R; ContentType = $type }
        }
    }
    function Get-Request {
        <#
        .SYNOPSIS
            Returns the request the module builds for a parser item.
        .PARAMETER Item
            The parser item read from the repository.
        #>
        param([psobject] $Item)
        InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) ConvertTo-iSOCParserRequest -Item $I }
    }
    function Test-Item {
        <#
        .SYNOPSIS
            Returns the validation errors the module reports for a parser item.
        .PARAMETER Item
            The parser item read from the repository.
        #>
        param([psobject] $Item)
        @(InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) Test-iSOCParser -Item $I })
    }

    $script:items = @(Get-ParserItem)
    $script:parser = $script:items | Where-Object { $_.RelativePath -like '*/FixtureSignInParser.yaml' }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Parser handlers' {
    It 'reads each parser file, named by its id in lower case' {
        $script:items.Count | Should -Be 2
        $script:parser.Identity | Should -BeExactly '3c7a1e52-9b1d-4f0e-8a2b-6d5c4e3f2a10'
        $script:parser.Data['functionAlias'] | Should -Be 'FixtureSignIns'
    }

    It 'passes a complete parser and names the fields a parser is missing' {
        Test-Item $script:parser | Should -BeNullOrEmpty
        Test-Item ($script:items | Where-Object { $_.RelativePath -like '*/MissingAlias.yaml' }) | Should -Be @('missing required fields: functionAlias')
    }

    It 'builds the saved search the deployer sends' {
        $request = Get-Request $script:parser
        $request.ResourceName | Should -BeExactly '3c7a1e52-9b1d-4f0e-8a2b-6d5c4e3f2a10'
        $request.Body.etag | Should -Be '*'
        $p = $request.Body.properties
        $p.category | Should -Be 'Sentinel Parsers'
        $p.displayName | Should -Be 'Fixture sign-in parser'
        $p.functionAlias | Should -Be 'FixtureSignIns'
        $p.query | Should -Match '^SigninLogs'
        $p.version | Should -Be 2
        $p.functionParameters | Should -Be 'lookback:timespan = 1d'
    }

    It 'keeps the file''s category and leaves out blank function parameters' {
        $item = [pscustomobject]@{ ContentType = 'Parser'; Identity = 'p'; Data = @{ id = 'p'; name = 'n'; functionAlias = 'f'; query = 'q'; category = 'Custom'; functionParameters = ' ' } }
        $p = (Get-Request $item).Body.properties
        $p.category | Should -Be 'Custom'
        $p.ContainsKey('functionParameters') | Should -BeFalse
    }
}

Describe 'Content/Parsers in this repository' {
    BeforeAll {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        $script:repoType = InModuleScope iSOCDeployments { Get-iSOCContentTypeDefinition -Name Parser }
        function Invoke-RepoHandler {
            <#
            .SYNOPSIS
                Runs a handler of the repository content type under test.
            .PARAMETER Handler
                The name of the handler to run.
            .PARAMETER Parameters
                The parameters passed to the handler.
            #>
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

    It 'reads, validates and builds <Path>' -ForEach $parserFiles {
        $item = $script:repoItems[$Path]
        $item | Should -Not -BeNullOrEmpty -Because 'the ReadRepo handler reads everything under Content/Parsers'
        Test-Item $item | Should -BeNullOrEmpty
        { $script:repoRequest = Invoke-RepoHandler -Handler ToRequest -Parameters @{ Item = $item } } | Should -Not -Throw
        $script:repoRequest.Body | Should -Not -BeNullOrEmpty
    }
}
