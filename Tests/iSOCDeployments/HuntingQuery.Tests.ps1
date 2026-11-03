#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the hunting query content type's handlers, and for
    parity with the deployer they were taken from.

.DESCRIPTION
    The handlers are tested on the fixture repository: reading, validation
    (the message Deploy-CustomContent.ps1 logs), the saved search body with
    its tags, and the query. The parity block lifts
    Deploy-CustomHuntingQueries out of Deploy/content/Deploy-CustomContent.ps1
    by AST, runs it over every query in Content/HuntingQueries/ with the
    REST call captured, and holds each captured request (path, api-version
    and body) to the one the module builds for the same file.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/HuntingQuery.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/HuntingQuery.Tests.ps1
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
    $queryFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content/HuntingQueries') -Recurse -File -Include '*.yaml', '*.yml') |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '_helpers/Parity.psm1') -Force
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

Describe 'Parity with Deploy-CustomContent.ps1' {
    BeforeAll {
        Import-Module (Join-Path $script:repoRoot 'Tests/_helpers/Import-ScriptFunctions.psm1') -Force
        Import-ScriptFunctions -Path (Join-Path $script:repoRoot 'Deploy/content/Deploy-CustomContent.ps1')
        function Write-PipelineMessage { param($Message, $Level) }
        function Test-ShouldDeployFile { param($FilePath) $script:legacyFile = $FilePath; $true }
        function Get-PrioritizedFiles { param($Files) $Files }
        function Test-ContentDependencies { param($ContentPath) @{ Passed = $true; Missing = @() } }
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
        $script:legacyCounters = Deploy-CustomHuntingQueries

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
        foreach ($item in Get-HuntingItem -Repo $script:repoRoot) { $script:moduleItems[$item.RelativePath] = $item }
    }

    It 'sent a request for every hunting query it read' {
        $script:legacyCounters.Failed | Should -Be 0
        $script:legacyCounters.Skipped | Should -Be 0
        $script:legacyCalls.Count | Should -Be $script:moduleItems.Count
    }

    It 'sends <Path> as Deploy-CustomContent.ps1 does' -ForEach $queryFiles {
        $item = $script:moduleItems[$Path]
        Test-Item $item | Should -BeNullOrEmpty
        $request = Get-Request $item
        $legacy = @($script:legacyByFile[$Path])
        $legacy.Count | Should -Be 1

        $path = InModuleScope iSOCDeployments -Parameters @{ C = $script:context; N = $request.ResourceName } {
            param($C, $N)
            $type = Get-iSOCContentTypeDefinition -Name HuntingQuery
            '{0}?api-version={1}' -f (Get-iSOCResourcePath -Context $C -ContentType $type -Name $N), (Get-iSOCApiVersion $type.ApiVersion)
        }
        "https://management.azure.com$path" | Should -BeExactly $legacy[0].Uri
        $legacy[0].Method | Should -Be 'Put'
        ConvertTo-ParityJson $request.Body | Should -BeExactly (ConvertTo-ParityJson $legacy[0].Body)
    }
}
