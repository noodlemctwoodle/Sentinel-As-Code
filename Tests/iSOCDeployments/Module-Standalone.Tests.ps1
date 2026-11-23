#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests that the iSOCDeployments module works away from this
    repository.

.DESCRIPTION
    The module is meant to be installed anywhere and pointed at any
    Sentinel-As-Code repository. This suite copies Modules/iSOCDeployments
    to a folder outside the repository, imports it from there, and reads
    the fixture repository through the registry: list the content types,
    read the rules, validate them, build their requests, read a query's
    dependencies, and write and check a dependency manifest. A step that
    still reached into this repository (the shared module, a path two
    folders up) would fail here.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Module-Standalone.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Module-Standalone.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+, powershell-yaml
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:copy = Join-Path $TestDrive 'modules/iSOCDeployments'
    New-Item -ItemType Directory -Path $script:copy -Force | Out-Null
    Copy-Item -Path (Join-Path $repoRoot 'Modules/iSOCDeployments/*') -Destination $script:copy -Recurse -Force

    $script:work = Join-Path $TestDrive 'work/repo'
    New-Item -ItemType Directory -Path $script:work -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Fixtures/repo/Content') -Destination $script:work -Recurse

    Remove-Module iSOCDeployments, Sentinel.Common -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:copy 'iSOCDeployments.psd1') -Force
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'iSOCDeployments outside the repository' {
    It 'is loaded from the copy, not the repository' {
        (Get-Module iSOCDeployments).ModuleBase | Should -Be $script:copy
    }

    It 'does not load Sentinel.Common' {
        Get-Module Sentinel.Common | Should -BeNullOrEmpty
    }

    It 'lists its content types' {
        @(Get-iSOCContentType).Name | Should -Contain 'AnalyticsRule'
    }

    It 'finds the repository from a folder inside it and reads, validates and builds every rule' {
        Push-Location (Join-Path $script:work 'Content/AnalyticalRules/Identity')
        try {
            $result = InModuleScope iSOCDeployments {
                $repo = Resolve-iSOCRepoPath
                $type = Get-iSOCContentTypeDefinition -Name AnalyticsRule
                $items = @(Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $repo; ContentType = $type })
                $valid = @($items | Where-Object { @(Invoke-iSOCContentTypeHandler -ContentType $type -Handler Validate -Parameters @{ Item = $_ }).Count -eq 0 })
                $requests = @($valid | ForEach-Object { Invoke-iSOCContentTypeHandler -ContentType $type -Handler ToRequest -Parameters @{ Item = $_ } })
                [pscustomobject]@{ Repo = $repo; Items = $items.Count; Valid = $valid.Count; Requests = $requests }
            }
        } finally { Pop-Location }
        $result.Repo | Should -Be ([System.IO.Path]::GetFullPath($script:work))
        $result.Items | Should -Be 5
        $result.Valid | Should -Be 3
        @($result.Requests.ResourceName) | Should -Contain '0a9b8c7d-6e5f-4a3b-2c1d-0e9f8a7b6c5d'
    }

    It 'reads a hunting query''s dependencies, with the parser the copied repository defines' {
        $deps = Get-iSOCContentDependency -Path (Join-Path $script:work 'Content/HuntingQueries/SigninLogs/FixtureHunt.yaml') -RepoPath $script:work
        $deps.Path | Should -Be 'Content/HuntingQueries/SigninLogs/FixtureHunt.yaml'
        $deps.Functions | Should -Be @('FixtureSignIns')
    }

    It 'runs a -WhatIf deploy of the copied repository' {
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { throw 'no request should be sent' } -ParameterFilter { $Method -ne 'GET' }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { } -ParameterFilter { $Method -eq 'GET' }
        $context = InModuleScope iSOCDeployments {
            New-iSOCContext -Value @{
                TenantId = 't'; SubscriptionId = 's'; ResourceGroup = 'rg'; WorkspaceName = 'ws'; WorkspaceResourceId = '/w'
                WorkspaceId = 'c'; Region = 'uksouth'; PlaybookResourceGroup = 'rg'; Environment = 'AzureCloud'; IsGov = $false
                ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'a'
            }
        }
        $run = Deploy-iSOCContent -Context $context -RepoPath $script:work -WhatIf 6>$null 3>$null 2>$null
        $run.WhatIf | Should -BeGreaterThan 0
        $run.Deployed | Should -Be 0
    }

    It 'writes and checks a dependency manifest for the copied repository' {
        (Update-iSOCDependencyManifest -RepoPath $script:work 6>$null).Changed | Should -BeTrue
        (Test-iSOCDependencyManifest -RepoPath $script:work 6>$null).HasDrift | Should -BeFalse
    }
}
