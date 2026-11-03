#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the deploy engine and Deploy-iSOCContent.

.DESCRIPTION
    The engine's parts one at a time (the configuration, the deployment
    state, smart deployment, deploy order, the dependency graph, the
    pre-flight reads and the dependency check), then Deploy-iSOCContent end
    to end over a copy of the fixture repository with the REST client and
    the Az.Resources wrappers mocked: outcomes per item for all nine
    types, deploy order, the wait after watchlists, the state file,
    -WhatIf, type and path selection, the Az.Resources check made only when
    there are playbooks, smart deployment, missing dependencies, an
    analytics rule retried disabled after a KQL error, and configuration
    exclusions. DeployParity.Tests.ps1 holds the engine to
    Deploy-CustomContent.ps1 over this repository.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Deploy.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Deploy.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.3.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'

    function New-FixtureCopy {
        $copy = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $copy | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:fixtureRepo 'Content') -Destination $copy -Recurse
        $copy
    }
    $script:context = InModuleScope iSOCDeployments {
        New-iSOCContext -Value @{
            TenantId = 't'; SubscriptionId = 's'; ResourceGroup = 'rg'; WorkspaceName = 'ws'; WorkspaceResourceId = '/w'
            WorkspaceId = 'c'; Region = 'uksouth'; PlaybookResourceGroup = 'rg'; Environment = 'AzureCloud'; IsGov = $false
            ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'a'
        }
    }
    function New-TestRun {
        param([string] $Repo, [string[]] $Changed, [hashtable] $Items = @{}, [string[]] $Excluded = @(), [string[]] $Prioritized = @(), [hashtable] $Graph = @{})
        InModuleScope iSOCDeployments -Parameters @{ C = $script:context; R = $Repo; Ch = $Changed; I = $Items; E = $Excluded; P = $Prioritized; G = $Graph } {
            param($C, $R, $Ch, $I, $E, $P, $G)
            $config = [pscustomobject]@{ Path = 'sentinel-deployment.config'; Prioritized = $P; Excluded = $E; ParameterFileMappings = $null }
            $state = [pscustomobject]@{ Path = (Join-Path $R 'deployment-state.json'); Items = $I }
            New-iSOCDeployRun -Context $C -RepoPath $R -Config $config -ChangedFiles $Ch -State $state -Graph $G
        }
    }
    function Get-Item1 {
        param([string] $Type, [string] $Leaf, [string] $Repo = $script:fixtureRepo)
        InModuleScope iSOCDeployments -Parameters @{ T = $Type; R = $Repo; L = $Leaf } {
            param($T, $R, $L)
            $type = Get-iSOCContentTypeDefinition -Name $T
            Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $R; ContentType = $type } | Where-Object { $_.RelativePath -like "*$L" }
        }
    }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Get-iSOCDeploymentConfig' {
    BeforeEach { Mock -ModuleName iSOCDeployments Write-iSOCLog { } }

    It 'reads the repository root first, then Deploy/content/' {
        $repo = New-FixtureCopy
        New-Item -ItemType Directory -Path (Join-Path $repo 'Deploy/content') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'Deploy/content/sentinel-deployment.config') -Value '{ "excludecontentfiles": ["Content/Legacy"] }'
        $legacy = InModuleScope iSOCDeployments -Parameters @{ R = $repo } { param($R) Get-iSOCDeploymentConfig -RepoPath $R }
        $legacy.Path | Should -Be 'Deploy/content/sentinel-deployment.config'
        $legacy.Excluded | Should -Be @('Content/Legacy')

        Set-Content -LiteralPath (Join-Path $repo 'sentinel-deployment.config') -Value '{ "excludecontentfiles": ["Content/Root"], "prioritizedcontentfiles": ["Content/Parsers/A.yaml"] }'
        $root = InModuleScope iSOCDeployments -Parameters @{ R = $repo } { param($R) Get-iSOCDeploymentConfig -RepoPath $R }
        $root.Path | Should -Be 'sentinel-deployment.config'
        $root.Excluded | Should -Be @('Content/Root')
        , $root.Prioritized | Should -BeOfType [object[]]
        $root.Prioritized.Count | Should -Be 1
    }

    It 'is empty without a file, and empty with a warning for one that does not parse' {
        $repo = New-FixtureCopy
        (InModuleScope iSOCDeployments -Parameters @{ R = $repo } { param($R) Get-iSOCDeploymentConfig -RepoPath $R }).Path | Should -BeNullOrEmpty
        Set-Content -LiteralPath (Join-Path $repo 'sentinel-deployment.config') -Value '{ broken'
        $config = InModuleScope iSOCDeployments -Parameters @{ R = $repo } { param($R) Get-iSOCDeploymentConfig -RepoPath $R }
        $config.Excluded.Count | Should -Be 0
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Level -eq 'Warning' -and $Message -like 'Failed to parse*' }
    }

    It 'reads the repository''s own config' {
        $config = InModuleScope iSOCDeployments -Parameters @{ R = $script:repoRoot } { param($R) Get-iSOCDeploymentConfig -RepoPath $R }
        $config.Excluded | Should -Contain 'Content/PromptBooks'
    }
}

Describe 'Deployment state' {
    BeforeEach { Mock -ModuleName iSOCDeployments Write-iSOCLog { } }

    It 'round-trips in the file format the script wrote' {
        $repo = New-FixtureCopy
        InModuleScope iSOCDeployments -Parameters @{ R = $repo } {
            param($R)
            $state = Read-iSOCDeploymentState -RepoPath $R
            $state.Items.Count | Should -Be 0
            Set-iSOCDeploymentItemState -State $state -Key 'Content/A.yaml' -Status success
            Set-iSOCDeploymentItemState -State $state -Key 'Content/B.yaml' -Status success
            Set-iSOCDeploymentItemState -State $state -Key 'Content/B.yaml' -Status failed
            Save-iSOCDeploymentState -State $state
            $raw = Get-Content -LiteralPath (Join-Path $R 'deployment-state.json') -Raw | ConvertFrom-Json
            $raw.deployedItems.'Content/A.yaml'.status | Should -Be 'success'
            $raw.deployedItems.PSObject.Properties['Content/B.yaml'] | Should -BeNullOrEmpty
            $again = Read-iSOCDeploymentState -RepoPath $R
            Test-iSOCDeployedSuccessfully -State $again -Key 'Content/A.yaml' | Should -BeTrue
            Test-iSOCDeployedSuccessfully -State $again -Key 'Content/B.yaml' | Should -BeFalse
        }
    }

    It 'reads the state a build artifact left in a deployment-state folder, without copying it' {
        $repo = New-FixtureCopy
        New-Item -ItemType Directory -Path (Join-Path $repo 'deployment-state') | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'deployment-state/deployment-state.json') -Value '{ "deployedItems": { "Content/A.yaml": { "lastDeployed": "2026-11-01T00:00:00Z", "status": "success" } } }'
        $state = InModuleScope iSOCDeployments -Parameters @{ R = $repo } { param($R) Read-iSOCDeploymentState -RepoPath $R }
        $state.Items.Count | Should -Be 1
        $state.Path | Should -Be (Join-Path $repo 'deployment-state.json')
        Test-Path -LiteralPath (Join-Path $repo 'deployment-state.json') | Should -BeFalse
    }

    It 'starts fresh from a file that does not parse' {
        $repo = New-FixtureCopy
        Set-Content -LiteralPath (Join-Path $repo 'deployment-state.json') -Value 'not json'
        (InModuleScope iSOCDeployments -Parameters @{ R = $repo } { param($R) Read-iSOCDeploymentState -RepoPath $R }).Items.Count | Should -Be 0
    }
}

Describe 'Test-iSOCShouldDeployItem' {
    BeforeAll {
        $script:rule = Get-Item1 AnalyticsRule 'Identity/NrtRule.yaml'
        $script:watchlist = Get-Item1 Watchlist 'vipUsers'
        function Test-Decision {
            param($Run, $Item)
            InModuleScope iSOCDeployments -Parameters @{ Run = $Run; I = $Item } { param($Run, $I) Test-iSOCShouldDeployItem -Run $Run -Item $I }
        }
    }

    It 'deploys everything without smart deployment' {
        (Test-Decision (New-TestRun -Repo $script:fixtureRepo) $script:rule).Reason | Should -Be 'Full'
    }

    It 'never deploys an excluded path' {
        $d = Test-Decision (New-TestRun -Repo $script:fixtureRepo -Excluded 'Content/AnalyticalRules/Identity') $script:rule
        $d.Deploy | Should -BeFalse
        $d.Reason | Should -Be 'Excluded'
    }

    It 'deploys a changed file under smart deployment: <Case>' -ForEach @(
        @{ Case = 'the file'; Changed = 'Content/AnalyticalRules/Identity/NrtRule.yaml' }
        @{ Case = 'a file in its folder'; Changed = 'Content/AnalyticalRules/Identity/Other.yaml' }
    ) {
        $items = @{ 'Content/AnalyticalRules/Identity/NrtRule.yaml' = @{ status = 'success' } }
        (Test-Decision (New-TestRun -Repo $script:fixtureRepo -Changed $Changed -Items $items) $script:rule).Reason | Should -Be 'Changed'
    }

    It 'retries an unchanged file whose last deployment did not succeed, and skips one that did' {
        (Test-Decision (New-TestRun -Repo $script:fixtureRepo -Changed 'README.md') $script:rule).Reason | Should -Be 'Retry'
        $items = @{ 'Content/AnalyticalRules/Identity/NrtRule.yaml' = @{ status = 'success' } }
        $d = Test-Decision (New-TestRun -Repo $script:fixtureRepo -Changed 'README.md' -Items $items) $script:rule
        $d.Deploy | Should -BeFalse
        $d.Reason | Should -Be 'Unchanged'
    }

    It 'deploys a watchlist when either of its files changed' {
        $items = @{ 'Content/Watchlists/vipUsers/watchlist.json' = @{ status = 'success' }; 'Content/Watchlists/vipUsers/data.csv' = @{ status = 'success' } }
        (Test-Decision (New-TestRun -Repo $script:fixtureRepo -Changed 'Content/Watchlists/vipUsers/data.csv' -Items $items) $script:watchlist).Deploy | Should -BeTrue
        (Test-Decision (New-TestRun -Repo $script:fixtureRepo -Changed 'README.md' -Items $items) $script:watchlist).Deploy | Should -BeFalse
    }
}

Describe 'Get-iSOCDeployOrder' {
    It 'puts custom before Community, and the prioritised first in each' {
        $items = @(
            [pscustomobject]@{ RelativePath = 'Content/A/a.yaml'; Source = 'Custom' }
            [pscustomobject]@{ RelativePath = 'Content/A/Community/b.yaml'; Source = 'Community' }
            [pscustomobject]@{ RelativePath = 'Content/A/c.yaml'; Source = 'Custom' }
            [pscustomobject]@{ RelativePath = 'Content/A/Community/d.yaml'; Source = 'Community' }
        )
        $run = New-TestRun -Repo $script:fixtureRepo -Prioritized 'Content/A/c.yaml', 'Content/A/Community/d.yaml'
        $ordered = InModuleScope iSOCDeployments -Parameters @{ Run = $run; I = $items } { param($Run, $I) Get-iSOCDeployOrder -Run $Run -Item $I }
        @($ordered.RelativePath) | Should -Be @('Content/A/c.yaml', 'Content/A/a.yaml', 'Content/A/Community/d.yaml', 'Content/A/Community/b.yaml')
    }

    It 'returns nothing for no items' {
        @(InModuleScope iSOCDeployments -Parameters @{ Run = (New-TestRun -Repo $script:fixtureRepo) } { param($Run) Get-iSOCDeployOrder -Run $Run -Item @() }).Count | Should -Be 0
    }
}

Describe 'Dependencies' {
    BeforeEach { Mock -ModuleName iSOCDeployments Write-iSOCLog { } }

    It 'reads the graph, and an empty one without dependencies.json or from one that does not parse' {
        $repo = New-FixtureCopy
        (InModuleScope iSOCDeployments -Parameters @{ R = $repo } { param($R) Read-iSOCDependencyGraph -RepoPath $R }).Count | Should -Be 0
        Set-Content -LiteralPath (Join-Path $repo 'dependencies.json') -Value '{ "dependencies": { "Content/A.yaml": { "tables": ["T"], "watchlists": ["w"] } } }'
        $graph = InModuleScope iSOCDeployments -Parameters @{ R = $repo } { param($R) Read-iSOCDependencyGraph -RepoPath $R }
        $graph['Content/A.yaml'].tables | Should -Be @('T')
        $graph['Content/A.yaml'].ContainsKey('functions') | Should -BeFalse
        Set-Content -LiteralPath (Join-Path $repo 'dependencies.json') -Value '{ broken'
        (InModuleScope iSOCDeployments -Parameters @{ R = $repo } { param($R) Read-iSOCDependencyGraph -RepoPath $R }).Count | Should -Be 0
    }

    Context 'Test-iSOCItemDependency' {
        BeforeAll {
            $script:hunt = Get-Item1 HuntingQuery 'FixtureHunt.yaml'
            $script:graph = @{ 'Content/HuntingQueries/SigninLogs/FixtureHunt.yaml' = @{ tables = @('SigninLogs'); watchlists = @('vipUsers', 'notInRepo'); functions = @('FixtureSignIns', 'ASimDns') } }
            function Test-Deps {
                param($Inventory, [hashtable] $Graph = $script:graph)
                $run = New-TestRun -Repo $script:fixtureRepo -Graph $Graph
                $run.Inventory = $Inventory
                InModuleScope iSOCDeployments -Parameters @{ Run = $run; I = $script:hunt } { param($Run, $I) Test-iSOCItemDependency -Run $Run -Item $I }
            }
        }

        It 'passes an item the graph does not list' {
            (Test-Deps ([pscustomobject]@{ Tables = @(); Watchlists = @(); Functions = @(); RepoFunctions = @(); RepoWatchlists = @() }) @{}).Passed | Should -BeTrue
        }

        It 'counts the repository''s own watchlists and functions as met, and names the rest' {
            $check = Test-Deps ([pscustomobject]@{ Tables = @('Other'); Watchlists = @(); Functions = @(); RepoFunctions = @('fixturesignins'); RepoWatchlists = @('vipUsers') })
            $check.Passed | Should -BeFalse
            @($check.Missing) | Should -Be @('table:SigninLogs', 'watchlist:notInRepo', 'function:ASimDns')
        }

        It 'counts the workspace''s watchlists and functions as met' {
            (Test-Deps ([pscustomobject]@{ Tables = @('SigninLogs'); Watchlists = @('vipUsers', 'notInRepo'); Functions = @('FixtureSignIns', 'ASimDns'); RepoFunctions = @(); RepoWatchlists = @() })).Passed | Should -BeTrue
        }

        It 'skips each check whose workspace list could not be read (MIGRATION.md edit E13)' {
            (Test-Deps ([pscustomobject]@{ Tables = $null; Watchlists = $null; Functions = $null; RepoFunctions = @(); RepoWatchlists = @() })).Passed | Should -BeTrue
        }

        It 'skips the table check for a workspace that lists no tables, as the script did' {
            (Test-Deps ([pscustomobject]@{ Tables = @(); Watchlists = @('vipUsers', 'notInRepo'); Functions = @('FixtureSignIns', 'ASimDns'); RepoFunctions = @(); RepoWatchlists = @() })).Passed | Should -BeTrue
        }
    }

    Context 'Get-iSOCWorkspaceInventory' {
        BeforeEach {
            Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
                switch -Wildcard ($Path) {
                    '*/tables' { [pscustomobject]@{ name = 'SigninLogs' }; [pscustomobject]@{ name = 'AuditLogs' } }
                    '*/watchlists' {
                        [pscustomobject]@{ properties = [pscustomobject]@{ watchlistAlias = 'live' } }
                        [pscustomobject]@{ properties = [pscustomobject]@{ watchlistAlias = 'gone'; isDeleted = $true } }
                    }
                    '*/savedSearches' { [pscustomobject]@{ properties = [pscustomobject]@{ functionAlias = 'WsFn' } }; [pscustomobject]@{ properties = [pscustomobject]@{ query = 'q' } } }
                    '*/alertRules' { }
                }
            }
        }

        It 'lists the workspace''s tables, live watchlists and functions, and the repository''s own' {
            $run = New-TestRun -Repo $script:fixtureRepo
            $inventory = InModuleScope iSOCDeployments -Parameters @{ Run = $run } { param($Run) Get-iSOCWorkspaceInventory -Run $Run }
            $inventory.Tables | Should -Be @('SigninLogs', 'AuditLogs')
            $inventory.Watchlists | Should -Be @('live')
            $inventory.Functions | Should -Be @('WsFn')
            $inventory.RepoFunctions | Should -Be @('FixtureSignIns')
            $inventory.RepoWatchlists | Should -Be @('noData', 'vipUsers')
        }

        It 'records a list it could not read as unknown' {
            Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { throw 'HTTP 403' } -ParameterFilter { $Path -like '*/watchlists' }
            $run = New-TestRun -Repo $script:fixtureRepo
            $inventory = InModuleScope iSOCDeployments -Parameters @{ Run = $run } { param($Run) Get-iSOCWorkspaceInventory -Run $Run }
            $inventory.Watchlists | Should -BeNullOrEmpty
            $null -eq $inventory.Watchlists | Should -BeTrue
            Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Message -like '*Dependency checks on watchlists will be skipped*' }
        }

        It 'resets a stale state: more than ten rules recorded, none in the workspace (MIGRATION.md edit E13)' {
            $items = @{}
            1..11 | ForEach-Object { $items["Content/AnalyticalRules/R$_.yaml"] = @{ status = 'success' } }
            $run = New-TestRun -Repo $script:fixtureRepo -Items $items
            InModuleScope iSOCDeployments -Parameters @{ Run = $run } { param($Run) Get-iSOCWorkspaceInventory -Run $Run } | Out-Null
            $run.State.Items.Count | Should -Be 0
        }

        It 'keeps the state when the workspace has rules' {
            Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { [pscustomobject]@{ name = 'r' } } -ParameterFilter { $Path -like '*/alertRules' }
            $items = @{}
            1..11 | ForEach-Object { $items["Content/AnalyticalRules/R$_.yaml"] = @{ status = 'success' } }
            $run = New-TestRun -Repo $script:fixtureRepo -Items $items
            InModuleScope iSOCDeployments -Parameters @{ Run = $run } { param($Run) Get-iSOCWorkspaceInventory -Run $Run } | Out-Null
            $run.State.Items.Count | Should -Be 11
        }
    }
}

Describe 'Deploy-iSOCContent' {
    BeforeEach {
        $script:copy = New-FixtureCopy
        $script:sent = [System.Collections.Generic.List[object]]::new()
        $script:deployments = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Start-Sleep { }
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            if ($Method -eq 'GET' -and $Path -eq '/security/rules/detectionRules') { return [pscustomobject]@{ id = 'tenant-rule-1'; displayName = 'Fixture: mail rule the tenant already has' } }
            if ($Method -in 'PUT', 'PATCH', 'POST') { $script:sent.Add([pscustomobject]@{ Method = $Method; Path = $Path; ApiVersion = $ApiVersion; Body = $Body }) }
        }
        Mock -ModuleName iSOCDeployments New-iSOCAzResourceGroupDeployment { $script:deployments.Add([pscustomobject]@{ Name = $Name; Parameters = $Parameters }) }
        Mock -ModuleName iSOCDeployments Test-iSOCAzResourceGroupDeployment { }
        function Get-Outcome { param($Run, [string] $Leaf) ($Run.Results | Where-Object { $_.RelativePath -like "*$Leaf" }).Outcome }
    }

    It 'deploys every type in order and reports each item' {
        $run = Deploy-iSOCContent -Context $script:context -RepoPath $script:copy
        $run.PSObject.TypeNames | Should -Contain 'iSOCDeployments.DeployRun'
        @($run.Results.ContentType | Select-Object -Unique) | Should -Be @('Parser', 'Watchlist', 'AnalyticsRule', 'HuntingQuery', 'Playbook', 'Workbook', 'AutomationRule', 'SummaryRule', 'DefenderDetection')
        Get-Outcome $run 'FixtureSignInParser.yaml' | Should -Be 'Deployed'
        Get-Outcome $run 'MissingAlias.yaml' | Should -Be 'Skipped'
        Get-Outcome $run 'emptyFolder' | Should -Be 'Skipped'
        Get-Outcome $run 'noData' | Should -Be 'Skipped'
        Get-Outcome $run 'vipUsers' | Should -Be 'Deployed'
        Get-Outcome $run 'Broken.yaml' | Should -Be 'Failed'
        Get-Outcome $run 'MissingFields.yaml' | Should -Be 'Skipped'
        Get-Outcome $run 'ScheduledRule.yaml' | Should -Be 'Deployed'
        Get-Outcome $run 'CommunityRule.yml' | Should -Be 'DeployedDisabled'
        Get-Outcome $run 'FixtureHunt.yaml' | Should -Be 'Deployed'
        Get-Outcome $run 'ZuluBase.json' | Should -Be 'Deployed'
        Get-Outcome $run 'AlphaCaller.json' | Should -Be 'Deployed'
        Get-Outcome $run 'FixtureIncident.json' | Should -Be 'Deployed'
        Get-Outcome $run 'NotArm.json' | Should -Be 'Skipped'
        Get-Outcome $run 'FixtureOverview' | Should -Be 'Deployed'
        Get-Outcome $run 'ArmWrapped' | Should -Be 'Deployed'
        Get-Outcome $run 'NoTemplate' | Should -Be 'Skipped'
        Get-Outcome $run 'FixtureAutoClose.json' | Should -Be 'Deployed'
        Get-Outcome $run 'MissingActions.json' | Should -Be 'Skipped'
        Get-Outcome $run 'FixtureSummary.json' | Should -Be 'Deployed'
        Get-Outcome $run 'BadBinSize.json' | Should -Be 'Skipped'
        Get-Outcome $run 'NoSuffix.json' | Should -Be 'Skipped'
        Get-Outcome $run 'FixtureExistingNoId.yaml' | Should -Be 'Deployed'
        Get-Outcome $run 'FixtureEncodedPowerShell.yaml' | Should -Be 'Deployed'
        Get-Outcome $run 'FixtureLegacySpray.yaml' | Should -Be 'Deployed'
        Get-Outcome $run 'InvalidFrequency.yaml' | Should -Be 'Skipped'
        $run.Deployed | Should -Be 16
        $run.Failed | Should -Be 1
        $run.ExitCode | Should -Be 1
    }

    It 'sends each request to its type''s collection with its api-version, Community rules last' {
        Deploy-iSOCContent -Context $script:context -RepoPath $script:copy | Out-Null
        $script:sent.Count | Should -Be 13
        $script:sent[0].Path | Should -BeExactly '/w/savedSearches/3c7a1e52-9b1d-4f0e-8a2b-6d5c4e3f2a10'
        $script:sent[0].ApiVersion | Should -Be '2025-07-01'
        $script:sent[1].Path | Should -BeExactly '/w/providers/Microsoft.SecurityInsights/watchlists/vipUsers'
        $script:sent[1].ApiVersion | Should -Be '2025-09-01'
        $script:sent[4].Path | Should -BeExactly '/w/providers/Microsoft.SecurityInsights/alertRules/11111111-2222-4333-8444-555555555555'
        $script:sent[4].ApiVersion | Should -Be '2025-07-01-preview'
        $script:sent[4].Body.properties.enabled | Should -BeFalse
        $expected = @(
            @{ Path = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Insights/workbooks/7d0f5a3e-2b1c-4e8f-9a6d-3c2b1a0f9e8d'; ApiVersion = '2022-04-01' }
            @{ Path = '/w/providers/Microsoft.SecurityInsights/automationRules/b3c4d5e6-f7a8-4901-b2c3-d4e5f6a7b8c9'; ApiVersion = '2025-09-01' }
            @{ Path = '/w/summarylogs/FixtureSummary'; ApiVersion = '2025-07-01' }
        )
        foreach ($e in $expected) { ($script:sent | Where-Object Path -CEQ $e.Path).ApiVersion | Should -Be $e.ApiVersion -Because $e.Path }
        $graph = @($script:sent | Select-Object -Last 3)
        @($graph | ForEach-Object { "$($_.Method) $($_.Path) $($_.ApiVersion)" }) | Should -Be @(
            'PATCH /security/rules/detectionRules/tenant-rule-1 beta'
            'POST /security/rules/detectionRules beta'
            'POST /security/rules/detectionRules beta'
        )
    }

    It 'deploys playbooks as resource group deployments, modules first in the order they call each other' {
        Deploy-iSOCContent -Context $script:context -RepoPath $script:copy | Out-Null
        @($script:deployments | ForEach-Object { Split-Path -Leaf $_.Parameters.TemplateFile }) | Should -Be @('ZuluBase.json', 'AlphaCaller.json', 'FixtureIncident.json')
        @($script:deployments.Name) | Should -Match '^Playbook-(ZuluBase|AlphaCaller|FixtureIncident)-\d{14}$'
        @($script:deployments.Parameters.ResourceGroupName | Select-Object -Unique) | Should -Be @('rg')
        @($script:sent | Where-Object { $_.Path -like '*Microsoft.Logic*' }) | Should -BeNullOrEmpty
    }

    It 'checks for Az.Resources only when there are playbooks to deploy' {
        Deploy-iSOCContent -Context $script:context -RepoPath $script:copy | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Assert-iSOCPrerequisite -Times 1 -Exactly -ParameterFilter { $Name -contains 'Az.Resources' -and $Purpose -eq 'deploying playbooks' }
        Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -ExcludeContentType Playbook | Out-Null
        Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -Exclude 'Content/Playbooks/*' | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Assert-iSOCPrerequisite -Times 1 -Exactly -ParameterFilter { $Name -contains 'Az.Resources' }
    }

    It 'stops before anything deploys when Az.Resources is missing and there are playbooks' {
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { throw 'This machine is missing what deploying playbooks needs.' } -ParameterFilter { $Name -contains 'Az.Resources' }
        { Deploy-iSOCContent -Context $script:context -RepoPath $script:copy } | Should -Throw -ExpectedMessage '*deploying playbooks*'
        $script:sent.Count | Should -Be 0
        $script:deployments.Count | Should -Be 0
    }

    It 'waits for watchlists to propagate once some were uploaded' {
        Deploy-iSOCContent -Context $script:context -RepoPath $script:copy | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 30 }
    }

    It 'records what deployed in deployment-state.json, both files of a watchlist' {
        Deploy-iSOCContent -Context $script:context -RepoPath $script:copy | Out-Null
        $state = Get-Content -LiteralPath (Join-Path $script:copy 'deployment-state.json') -Raw | ConvertFrom-Json
        $keys = @($state.deployedItems.PSObject.Properties.Name)
        $keys | Should -Contain 'Content/Watchlists/vipUsers/watchlist.json'
        $keys | Should -Contain 'Content/Watchlists/vipUsers/data.csv'
        $keys | Should -Contain 'Content/AnalyticalRules/Community/CommunityRule.yml'
        $keys | Should -Contain 'Content/Playbooks/Module/ZuluBase.json'
        $keys | Should -Contain 'Content/Workbooks/FixtureOverview/workbook.json'
        $keys | Should -Not -Contain 'Content/Workbooks/FixtureOverview/metadata.json'
        $keys | Should -Not -Contain 'Content/AnalyticalRules/Broken.yaml'
        $keys | Should -Not -Contain 'Content/Parsers/MissingAlias.yaml'
        $keys | Should -Contain 'Content/DefenderCustomDetections/Identity/FixtureLegacySpray.yaml'
        $keys | Should -Not -Contain 'Content/DefenderCustomDetections/Email/InvalidFrequency.yaml'
    }

    It 'changes nothing with -WhatIf: no request, no state file, no wait' {
        $run = Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -WhatIf
        $script:sent.Count | Should -Be 0
        $script:deployments.Count | Should -Be 0
        Should -Invoke -ModuleName iSOCDeployments Test-iSOCAzResourceGroupDeployment -Times 3 -Exactly
        Test-Path -LiteralPath (Join-Path $script:copy 'deployment-state.json') | Should -BeFalse
        Should -Invoke -ModuleName iSOCDeployments Start-Sleep -Times 0 -Exactly
        $run.WhatIf | Should -Be 16
        $run.Deployed | Should -Be 0
        Get-Outcome $run 'CommunityRule.yml' | Should -Be 'WhatIf'
    }

    It 'deploys only the types asked for, and leaves out excluded types and paths' {
        $run = Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -ContentType Analytics* -Exclude 'Content/AnalyticalRules/Community/*'
        @($run.Results.ContentType | Select-Object -Unique) | Should -Be @('AnalyticsRule')
        Get-Outcome $run 'CommunityRule.yml' | Should -BeNullOrEmpty
        $other = Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -ExcludeContentType Parser, Watchlist
        @($other.Results.ContentType | Select-Object -Unique) | Should -Be @('AnalyticsRule', 'HuntingQuery', 'Playbook', 'Workbook', 'AutomationRule', 'SummaryRule', 'DefenderDetection')
    }

    It 'refuses a content type it does not know' {
        { Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -ContentType Nonesuch } | Should -Throw -ExpectedMessage "*No content type matches 'Nonesuch'*"
    }

    It 'deploys only what changed, and retries what did not succeed, under -SmartDeployment' {
        Deploy-iSOCContent -Context $script:context -RepoPath $script:copy | Out-Null
        $script:sent.Clear()
        Mock -ModuleName iSOCDeployments Get-iSOCChangedFile { 'Content/HuntingQueries/SigninLogs/FixtureHunt.yaml' }
        $run = Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -SmartDeployment
        Get-Outcome $run 'FixtureHunt.yaml' | Should -Be 'Deployed'
        Get-Outcome $run 'ScheduledRule.yaml' | Should -Be 'Unchanged'
        Get-Outcome $run 'Broken.yaml' | Should -Be 'Failed'
        @($script:sent.Path) | Should -Be @('/w/savedSearches/5e9c3a74-1d3f-4b2a-8c4d-8f7e6a5b4c32')
    }

    It 'sends a rule disabled, and skips a hunting query, when a dependency is missing' {
        Update-iSOCDependencyManifest -RepoPath $script:copy | Out-Null
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { [pscustomobject]@{ name = 'SigninLogs' } } -ParameterFilter { $Method -eq 'GET' -and $Path -like '*/tables' }
        $run = Deploy-iSOCContent -Context $script:context -RepoPath $script:copy
        $nrt = $run.Results | Where-Object { $_.RelativePath -like '*NrtRule.yaml' }
        $nrt.Outcome | Should -Be 'DeployedDisabled'
        $nrt.Missing | Should -Be @('table:AuditLogs')
        ($script:sent | Where-Object { $_.Path -like '*0a9b8c7d-6e5f-4a3b-2c1d-0e9f8a7b6c5d' }).Body.properties.enabled | Should -BeFalse
        $hunt = $run.Results | Where-Object { $_.RelativePath -like '*FixtureHunt.yaml' }
        $hunt.Outcome | Should -Be 'Skipped'
        $hunt.Missing | Should -Be @('watchlist:notInRepo')
    }

    It 'resends a rule disabled when the service will not validate its query' {
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            $script:sent.Add([pscustomobject]@{ Path = $Path; ApiVersion = $ApiVersion; Body = $Body })
            if ($Body.properties.enabled) { throw [System.Net.Http.HttpRequestException]::new('HTTP 400 from PUT alertRules/x: BadRequest: Failed to run the analytics rule query.') }
        } -ParameterFilter { $Method -eq 'PUT' -and $Path -like '*6F1C2A3B*' }
        $run = Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -ContentType AnalyticsRule
        $result = $run.Results | Where-Object { $_.RelativePath -like '*ScheduledRule.yaml' }
        $result.Outcome | Should -Be 'DeployedDisabled'
        $result.Reason | Should -Be 'KQL validation'
        @($script:sent | Where-Object { $_.Path -like '*6F1C2A3B*' }).Count | Should -Be 2
    }

    It 'fails an item the service refuses for another reason, and forgets it in the state' {
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { throw 'HTTP 403 from PUT savedSearches/x: AuthorizationFailed' } -ParameterFilter { $Method -eq 'PUT' -and $Path -like '*/savedSearches/3c7a1e52*' }
        $run = Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -ContentType Parser
        $result = $run.Results | Where-Object { $_.RelativePath -like '*FixtureSignInParser.yaml' }
        $result.Outcome | Should -Be 'Failed'
        $result.Reason | Should -Match 'AuthorizationFailed'
        $state = Get-Content -LiteralPath (Join-Path $script:copy 'deployment-state.json') -Raw | ConvertFrom-Json
        $state.deployedItems.PSObject.Properties['Content/Parsers/Identity/FixtureSignInParser.yaml'] | Should -BeNullOrEmpty
    }

    It 'skips what sentinel-deployment.config excludes' {
        Set-Content -LiteralPath (Join-Path $script:copy 'sentinel-deployment.config') -Value '{ "excludecontentfiles": ["Content/Parsers"] }'
        $run = Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -ContentType Parser
        @($run.Results.Outcome | Select-Object -Unique) | Should -Be @('Skipped')
        @($run.Results.Reason | Select-Object -Unique) | Should -Be @('excluded by sentinel-deployment.config')
        $script:sent.Count | Should -Be 0
    }

    It 'needs a connected workspace' {
        InModuleScope iSOCDeployments { $script:iSOCContext = $null }
        { Deploy-iSOCContent -RepoPath $script:copy } | Should -Throw -ExpectedMessage '*Run Connect-iSOCWorkspace first*'
    }
}
