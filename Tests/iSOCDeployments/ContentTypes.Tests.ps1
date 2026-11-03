#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the content type registry and the handler contract.

.DESCRIPTION
    Deploy, export, compare, sync and the dependency manifest all walk the
    registry, so it is held to its contract: every type folder under
    Private/ContentTypes/ is registered and every registered type has a
    folder, every handler a type names lives in that folder in a file named
    after it, every capability has its handlers, and
    Test-iSOCContentTypeDefinition catches each way a definition can be
    wrong. The lookups, the file walk and the public Get-iSOCContentType
    are covered too.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/ContentTypes.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/ContentTypes.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.2.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    $types = @(InModuleScope iSOCDeployments { Get-iSOCContentTypeRegistry } | ForEach-Object { @{ Name = $_.Name } })
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:moduleRoot = Join-Path $script:repoRoot 'Modules/iSOCDeployments'
    Import-Module (Join-Path $script:moduleRoot 'iSOCDeployments.psd1') -Force
    $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'

    function Get-BrokenIssue {
        param([scriptblock] $Change)
        InModuleScope iSOCDeployments -Parameters @{ Change = $Change } {
            param($Change)
            $definition = Get-iSOCAnalyticsRuleDefinition
            & $Change $definition
            @(Test-iSOCContentTypeDefinition -Definition $definition)
        }
    }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Registry' {
    It 'registers every type folder, and has a folder for every type' {
        $folders = @(Get-ChildItem -LiteralPath (Join-Path $script:moduleRoot 'Private/ContentTypes') -Directory | ForEach-Object Name | Sort-Object)
        $registered = @(InModuleScope iSOCDeployments { Get-iSOCContentTypeRegistry } | ForEach-Object Name | Sort-Object)
        $registered | Should -Be $folders
    }

    It 'returns the types in deploy order, each name once' {
        $all = @(InModuleScope iSOCDeployments { Get-iSOCContentTypeRegistry })
        @($all.DeployOrder) | Should -Be @($all.DeployOrder | Sort-Object)
        @($all.Name | Sort-Object -Unique).Count | Should -Be $all.Count
    }

    It 'refuses to build when a definition is wrong' {
        Mock -ModuleName iSOCDeployments Test-iSOCContentTypeDefinition { 'missing Fields' }
        { InModuleScope iSOCDeployments { Get-iSOCContentTypeRegistry } } | Should -Throw -ExpectedMessage "*'Parser' is defined wrongly: missing Fields*"
    }
}

Describe 'Content type <Name>' -ForEach $types {
    BeforeAll {
        $script:type = InModuleScope iSOCDeployments -Parameters @{ N = $Name } { param($N) Get-iSOCContentTypeDefinition -Name $N }
        $script:definition = InModuleScope iSOCDeployments -Parameters @{ N = $Name } { param($N) & "Get-iSOC${N}Definition" }
    }

    It 'has a sound definition' {
        @(InModuleScope iSOCDeployments -Parameters @{ D = $script:definition } { param($D) Test-iSOCContentTypeDefinition -Definition $D }) | Should -BeNullOrEmpty
    }

    It 'keeps every handler in its own folder, in a file named after it' {
        foreach ($handler in $script:type.Handlers.Keys) {
            $command = $script:type.Handlers[$handler]
            Test-Path -LiteralPath (Join-Path $script:moduleRoot "Private/ContentTypes/$Name/$command.ps1") | Should -BeTrue -Because "$handler names $command"
        }
    }

    It 'has a folder in the repository it reads from' {
        Test-Path -LiteralPath (Join-Path $script:repoRoot $script:type.RepoFolder) -PathType Container | Should -BeTrue
    }

    It 'compares fields the request body has' {
        foreach ($field in $script:type.Fields) { $field.Name | Should -Match '^(kind|properties\.[A-Za-z]+(\.[A-Za-z]+)*|[A-Za-z]+)$' }
    }
}

Describe 'Test-iSOCContentTypeDefinition' {
    It 'finds nothing wrong with the analytics rule definition' {
        @(Get-BrokenIssue { param($d) }) | Should -BeNullOrEmpty
    }

    It 'reports <Case>' -ForEach @(
        @{ Case = 'a missing key'; Change = { param($d) $d.Remove('Fields') }; Message = 'missing Fields' }
        @{ Case = 'a layout it does not know'; Change = { param($d) $d.Layout = 'Zip' }; Message = "Layout 'Zip' is not one of*" }
        @{ Case = 'a scope it does not know'; Change = { param($d) $d.Scope = 'Galaxy' }; Message = "Scope 'Galaxy' is not one of*" }
        @{ Case = 'a folder outside Content/'; Change = { param($d) $d.RepoFolder = 'Rules' }; Message = "RepoFolder 'Rules'*" }
        @{ Case = 'a collection path without a slash'; Change = { param($d) $d.CollectionPath = 'providers/x' }; Message = "CollectionPath*does not start with '/'" }
        @{ Case = 'an API version not in the table'; Change = { param($d) $d.ApiVersion = 'SecurityInsightsNext' }; Message = "ApiVersion 'SecurityInsightsNext' is not in the API table" }
        @{ Case = 'a prerequisite not in the table'; Change = { param($d) $d.Prerequisites = @('Az.Magic') }; Message = "prerequisite 'Az.Magic'*" }
        @{ Case = 'a handler name it does not know'; Change = { param($d) $d.Handlers.Frobnicate = 'Get-iSOCApiVersion' }; Message = "unknown handler 'Frobnicate'" }
        @{ Case = 'a handler the module does not define'; Change = { param($d) $d.Handlers.ToRequest = 'ConvertTo-iSOCNothing' }; Message = "handler ToRequest names 'ConvertTo-iSOCNothing'*" }
        @{ Case = 'a capability without its handlers'; Change = { param($d) $d.Capabilities = @('Export') }; Message = 'capability Export needs a ReadWorkspace handler' }
        @{ Case = 'a capability it does not know'; Change = { param($d) $d.Capabilities = @('Teleport') }; Message = "unknown capability 'Teleport'" }
        @{ Case = 'a comparer it does not know'; Change = { param($d) $d.Fields = @(@{ Name = 'kind'; Comparer = 'Fuzzy' }) }; Message = "field kind uses unknown comparer 'Fuzzy'" }
        @{ Case = 'a field listed twice'; Change = { param($d) $d.Fields = @(@{ Name = 'kind'; Comparer = 'Exact' }, @{ Name = 'kind'; Comparer = 'Exact' }) }; Message = 'field kind is listed twice' }
        @{ Case = 'a deploy order that is not a whole number'; Change = { param($d) $d.DeployOrder = '30' }; Message = 'DeployOrder is not a whole number' }
        @{ Case = 'a name that is not one PascalCase word'; Change = { param($d) $d.Name = 'analytics rule' }; Message = "Name 'analytics rule'*" }
    ) {
        $issues = @(Get-BrokenIssue $Change)
        @($issues | Where-Object { $_ -like $Message }).Count | Should -Be 1 -Because "the issues were: $($issues -join '; ')"
    }
}

Describe 'Lookups' {
    It 'finds a type by name in any case, or by wildcard' {
        (InModuleScope iSOCDeployments { Get-iSOCContentTypeDefinition -Name analyticsrule }).Name | Should -Be 'AnalyticsRule'
        (InModuleScope iSOCDeployments { Get-iSOCContentTypeDefinition -Name 'Analytics*' }).Name | Should -Be 'AnalyticsRule'
    }

    It 'returns every type without a name' {
        @(InModuleScope iSOCDeployments { Get-iSOCContentTypeDefinition }).Count | Should -Be @(InModuleScope iSOCDeployments { Get-iSOCContentTypeRegistry }).Count
    }

    It 'names the types that exist when a name matches none' {
        { InModuleScope iSOCDeployments { Get-iSOCContentTypeDefinition -Name AnalyticRules } } | Should -Throw -ExpectedMessage "*No content type matches 'AnalyticRules'. Content types: Parser, Watchlist, AnalyticsRule, HuntingQuery.*"
    }

    It 'is what Get-iSOCContentType returns' {
        $public = Get-iSOCContentType -Name AnalyticsRule
        $public.PSObject.TypeNames | Should -Contain 'iSOCDeployments.ContentType'
        $public.RepoFolder | Should -Be 'Content/AnalyticalRules'
        @($public.Capabilities) | Should -Contain 'Dependencies'
    }
}

Describe 'Invoke-iSOCContentTypeHandler' {
    It 'calls the function the type names, with the parameters given' {
        Mock -ModuleName iSOCDeployments Get-iSOCAnalyticsRuleKql { "query of $($Item.Name)" }
        $result = InModuleScope iSOCDeployments {
            $type = Get-iSOCContentTypeDefinition -Name AnalyticsRule
            Invoke-iSOCContentTypeHandler -ContentType $type -Handler GetQuery -Parameters @{ Item = [pscustomobject]@{ Name = 'r1' } }
        }
        $result | Should -Be 'query of r1'
        Should -Invoke -ModuleName iSOCDeployments Get-iSOCAnalyticsRuleKql -Times 1 -Exactly
    }

    It 'says which handler a type does not have' {
        { InModuleScope iSOCDeployments { Invoke-iSOCContentTypeHandler -ContentType (Get-iSOCContentTypeDefinition -Name AnalyticsRule) -Handler ToRepoFile } } |
            Should -Throw -ExpectedMessage "*'AnalyticsRule' has no ToRepoFile handler*"
    }
}

Describe 'Get-iSOCContentFile' {
    It 'lists the files matching the patterns, through subfolders, in ordinal path order' {
        $files = @(InModuleScope iSOCDeployments -Parameters @{ R = $script:fixtureRepo } {
                param($R)
                Get-iSOCContentFile -RepoPath $R -ContentType (Get-iSOCContentTypeDefinition -Name AnalyticsRule)
            })
        $relative = @($files | ForEach-Object { [System.IO.Path]::GetRelativePath($script:fixtureRepo, $_.FullName).Replace('\', '/') })
        $relative | Should -Be @(
            'Content/AnalyticalRules/Broken.yaml'
            'Content/AnalyticalRules/Community/CommunityRule.yml'
            'Content/AnalyticalRules/Identity/NrtRule.yaml'
            'Content/AnalyticalRules/Identity/ScheduledRule.yaml'
            'Content/AnalyticalRules/MissingFields.yaml'
        )
    }

    It 'stays in the top folder when the type does not recurse' {
        $files = @(InModuleScope iSOCDeployments -Parameters @{ R = $script:fixtureRepo } {
                param($R)
                $type = Get-iSOCContentTypeDefinition -Name AnalyticsRule
                $type.Recurse = $false
                Get-iSOCContentFile -RepoPath $R -ContentType $type
            })
        @($files.Name) | Should -Be @('Broken.yaml', 'MissingFields.yaml')
    }

    It 'lists one folder per item for a folder layout' {
        $folders = @(InModuleScope iSOCDeployments -Parameters @{ R = $script:fixtureRepo } {
                param($R)
                $type = Get-iSOCContentTypeDefinition -Name AnalyticsRule
                $type.Layout = 'Folder'
                Get-iSOCContentFile -RepoPath $R -ContentType $type
            })
        @($folders.Name) | Should -Be @('Community', 'Identity')
        $folders[0] | Should -BeOfType [System.IO.DirectoryInfo]
    }

    It 'returns a type with one item as a list of one' {
        $repo = Join-Path $TestDrive 'one'
        New-Item -ItemType Directory -Path (Join-Path $repo 'Content/AnalyticalRules') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'Content/AnalyticalRules/Only.yaml') -Value 'id: x'
        $files = @(InModuleScope iSOCDeployments -Parameters @{ R = $repo } {
                param($R)
                Set-StrictMode -Version Latest
                Get-iSOCContentFile -RepoPath $R -ContentType (Get-iSOCContentTypeDefinition -Name AnalyticsRule)
            })
        $files.Count | Should -Be 1
        $files[0].Name | Should -Be 'Only.yaml'
    }

    It 'has no items when the type''s folder is not there' {
        @(InModuleScope iSOCDeployments -Parameters @{ R = $TestDrive } {
                param($R)
                Get-iSOCContentFile -RepoPath $R -ContentType (Get-iSOCContentTypeDefinition -Name AnalyticsRule)
            }).Count | Should -Be 0
    }
}
