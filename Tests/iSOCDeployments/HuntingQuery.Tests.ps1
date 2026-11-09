#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the hunting query content type's handlers.

.DESCRIPTION
    The handlers are tested on the fixture repository: reading, validation
    (the message Deploy-CustomContent.ps1 logged), the saved search body
    with its tags, and the query. Every query under Content/HuntingQueries/
    in this repository is read through the ReadRepo handler, must pass
    Test-iSOCHuntingQuery with no issues, and must build a request through
    the ToRequest handler. Parity with Deploy-CustomContent.ps1 was proven
    on release/26.11.0 before the script was removed.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/HuntingQuery.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/HuntingQuery.Tests.ps1
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
    $queryFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content/HuntingQueries') -Recurse -File -Include '*.yaml', '*.yml') |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module powershell-yaml -ErrorAction Stop
    $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'

    function Get-HuntingItem {
        param([string] $Repo = $script:fixtureRepo)
        InModuleScope iSOCDeployments -Parameters @{ R = $Repo } {
            param($R)
            $type = Get-iSOCContentTypeDefinition -Name HuntingQuery
            Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $R; ContentType = $type }
        }
    }
    function Get-Request {
        param([psobject] $Item)
        InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) ConvertTo-iSOCHuntingQueryRequest -Item $I }
    }
    function Test-Item {
        param([psobject] $Item)
        @(InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) Test-iSOCHuntingQuery -Item $I })
    }

    $script:items = @(Get-HuntingItem)
    $script:hunt = $script:items | Where-Object { $_.RelativePath -like '*/FixtureHunt.yaml' }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Hunting query handlers' {
    It 'reads each query file, named by its id in lower case' {
        $script:items.Count | Should -Be 2
        $script:hunt.Identity | Should -BeExactly '5e9c3a74-1d3f-4b2a-8c4d-8f7e6a5b4c32'
        $script:hunt.RelativePath | Should -BeExactly 'Content/HuntingQueries/SigninLogs/FixtureHunt.yaml'
    }

    It 'passes a complete query and names the fields a query is missing' {
        Test-Item $script:hunt | Should -BeNullOrEmpty
        Test-Item ($script:items | Where-Object { $_.RelativePath -like '*/NoQuery.yaml' }) | Should -Be @('missing required fields: query')
    }

    It 'builds the saved search the deployer sends' {
        $request = Get-Request $script:hunt
        $request.ResourceName | Should -BeExactly '5e9c3a74-1d3f-4b2a-8c4d-8f7e6a5b4c32'
        $p = $request.Body.properties
        $p.category | Should -Be 'Hunting Queries'
        $p.displayName | Should -Be 'Fixture hunting query'
        $p.query | Should -Match '^FixtureSignIns'
    }

    It 'turns the description, tactics, techniques and the file''s own tags into saved search tags' {
        $tags = @((Get-Request $script:hunt).Body.properties.tags)
        ($tags | Where-Object name -eq 'description').value | Should -Match 'used by the iSOCDeployments tests'
        ($tags | Where-Object name -eq 'tactics').value | Should -BeExactly 'CredentialAccess,InitialAccess'
        ($tags | Where-Object name -eq 'techniques').value | Should -BeExactly 'T1110'
        ($tags | Where-Object name -eq 'subTechniques').value | Should -BeExactly 'T1110.003'
        ($tags | Where-Object name -eq 'owner').value | Should -Be 'soc'
    }

    It 'sends no tags when the file has none to give' {
        $item = [pscustomobject]@{ ContentType = 'HuntingQuery'; Identity = 'h'; Data = @{ id = 'h'; name = 'n'; query = 'q' } }
        (Get-Request $item).Body.properties.ContainsKey('tags') | Should -BeFalse
    }

    It 'returns the query, or nothing for a file without one' {
        InModuleScope iSOCDeployments -Parameters @{ I = $script:hunt } { param($I) Get-iSOCHuntingQueryKql -Item $I } | Should -Match '^FixtureSignIns'
        InModuleScope iSOCDeployments -Parameters @{ I = ($script:items | Where-Object { $_.RelativePath -like '*/NoQuery.yaml' }) } { param($I) Get-iSOCHuntingQueryKql -Item $I } | Should -BeNullOrEmpty
    }
}

Describe 'Content/HuntingQueries in this repository' {
    BeforeAll {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        $script:repoType = InModuleScope iSOCDeployments { Get-iSOCContentTypeDefinition -Name HuntingQuery }
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

    It 'reads, validates and builds <Path>' -ForEach $queryFiles {
        $item = $script:repoItems[$Path]
        $item | Should -Not -BeNullOrEmpty -Because 'the ReadRepo handler reads everything under Content/HuntingQueries'
        Test-Item $item | Should -BeNullOrEmpty
        { $script:repoRequest = Invoke-RepoHandler -Handler ToRequest -Parameters @{ Item = $item } } | Should -Not -Throw
        $script:repoRequest.Body | Should -Not -BeNullOrEmpty
    }
}
