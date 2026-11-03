#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the parser content type's handlers, and for parity
    with the deployer they were taken from.

.DESCRIPTION
    The handlers are tested on the fixture repository: reading, validation
    (the message Deploy-CustomContent.ps1 logs) and the saved search body.
    The parity block lifts Deploy-CustomParsers out of
    Deploy/content/Deploy-CustomContent.ps1 by AST, runs it over every
    parser in Content/Parsers/ with the REST call captured, and holds each
    captured request (path, api-version and body) to the one the module
    builds for the same file.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Parser.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Parser.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml

    The parity block goes when Deploy-CustomContent.ps1 is removed at
    cut-over.
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $parserFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content/Parsers') -Recurse -File -Include '*.yaml', '*.yml') |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '_helpers/Parity.psm1') -Force
    Import-Module powershell-yaml -ErrorAction Stop
    $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'

    function Get-ParserItem {
        param([string] $Repo = $script:fixtureRepo)
        InModuleScope iSOCDeployments -Parameters @{ R = $Repo } {
            param($R)
            $type = Get-iSOCContentTypeDefinition -Name Parser
            Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $R; ContentType = $type }
        }
    }
    function Get-Request {
        param([psobject] $Item)
        InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) ConvertTo-iSOCParserRequest -Item $I }
    }
    function Test-Item {
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

Describe 'Parity with Deploy-CustomContent.ps1' {
    BeforeAll {
        Import-Module (Join-Path $script:repoRoot 'Tests/_helpers/Import-ScriptFunctions.psm1') -Force
        Import-ScriptFunctions -Path (Join-Path $script:repoRoot 'Deploy/content/Deploy-CustomContent.ps1')
        function Write-PipelineMessage { param($Message, $Level) }
        function Test-ShouldDeployFile { param($FilePath) $script:legacyFile = $FilePath; $true }
        function Get-PrioritizedFiles { param($Files) $Files }
        function Set-DeploymentItemState { param($FilePath, $Status) }
        function Invoke-SentinelApi {
            param($Uri, $Method, $Headers, $Body)
            $script:legacyCalls.Add([pscustomobject]@{ File = $script:legacyFile; Uri = $Uri; Method = $Method; Body = $Body })
        }

        $script:workspacePath = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/ws'
        $script:BasePath = $script:repoRoot
        $script:WhatIf = $false
        $script:ResourceGroup = 'rg'
        $script:Workspace = 'ws'
        $script:ServerUrl = 'https://management.azure.com'
        $script:SubscriptionId = '00000000-0000-0000-0000-000000000000'
        $script:SavedSearchApiVersion = '2025-07-01'
        $script:AuthHeader = @{}
        $script:legacyCalls = [System.Collections.Generic.List[object]]::new()
        $script:legacyCounters = Deploy-CustomParsers

        $script:legacyByFile = @{}
        foreach ($call in $script:legacyCalls) {
            $relative = [System.IO.Path]::GetRelativePath($script:repoRoot, $call.File).Replace('\', '/')
            if (-not $script:legacyByFile.ContainsKey($relative)) { $script:legacyByFile[$relative] = [System.Collections.Generic.List[object]]::new() }
            $script:legacyByFile[$relative].Add($call)
        }
        $script:context = InModuleScope iSOCDeployments -Parameters @{ W = $script:workspacePath } {
            param($W)
            New-iSOCContext -Value @{
                TenantId = 't'; SubscriptionId = '00000000-0000-0000-0000-000000000000'; ResourceGroup = 'rg'; WorkspaceName = 'ws'
                WorkspaceResourceId = $W; WorkspaceId = 'c'; Region = 'uksouth'; PlaybookResourceGroup = 'rg'; Environment = 'AzureCloud'
                IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'a'
            }
        }
        $script:moduleItems = @{}
        foreach ($item in Get-ParserItem -Repo $script:repoRoot) { $script:moduleItems[$item.RelativePath] = $item }
    }

    It 'sent a request for every parser it read' {
        $script:legacyCounters.Failed | Should -Be 0
        $script:legacyCounters.Skipped | Should -Be 0
        $script:legacyCalls.Count | Should -Be $script:moduleItems.Count
    }

    It 'sends <Path> as Deploy-CustomContent.ps1 does' -ForEach $parserFiles {
        $item = $script:moduleItems[$Path]
        Test-Item $item | Should -BeNullOrEmpty
        $request = Get-Request $item
        $legacy = @($script:legacyByFile[$Path])
        $legacy.Count | Should -Be 1

        $path = InModuleScope iSOCDeployments -Parameters @{ C = $script:context; N = $request.ResourceName } {
            param($C, $N)
            $type = Get-iSOCContentTypeDefinition -Name Parser
            '{0}?api-version={1}' -f (Get-iSOCResourcePath -Context $C -ContentType $type -Name $N), (Get-iSOCApiVersion $type.ApiVersion)
        }
        "https://management.azure.com$path" | Should -BeExactly $legacy[0].Uri
        $legacy[0].Method | Should -Be 'Put'
        ConvertTo-ParityJson $request.Body | Should -BeExactly (ConvertTo-ParityJson $legacy[0].Body)
    }
}
