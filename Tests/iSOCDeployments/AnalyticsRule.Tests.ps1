#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the analytics rule content type's handlers, and for
    parity with the deployer they were taken from.

.DESCRIPTION
    The handlers are tested on the fixture repository: reading (identity,
    name, Community source, unreadable files), validation (the messages
    Deploy-CustomContent.ps1 logs), the request body (every field the
    deployer sends, the operator map, the technique split, the enabled
    rules) and the query.

    The parity block lifts Deploy-CustomDetections out of
    Deploy/content/Deploy-CustomContent.ps1 by AST, runs it over every rule
    in Content/AnalyticalRules/ with the REST call captured, and holds each
    captured request (path, api-version and body) to the one the module
    builds for the same file.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/AnalyticsRule.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/AnalyticsRule.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml

    The parity block goes when Deploy-CustomContent.ps1 is removed at
    cut-over; its captured requests are kept as golden files first.
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $ruleFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content/AnalyticalRules') -Recurse -File -Include '*.yaml', '*.yml') |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '_helpers/Parity.psm1') -Force
    Import-Module powershell-yaml -ErrorAction Stop
    $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'

    function Get-FixtureItem {
        param([string] $Repo = $script:fixtureRepo)
        InModuleScope iSOCDeployments -Parameters @{ R = $Repo } {
            param($R)
            $type = Get-iSOCContentTypeDefinition -Name AnalyticsRule
            Read-iSOCAnalyticsRuleRepo -RepoPath $R -ContentType $type
        }
    }
    function Get-Item1 {
        param([string] $Leaf)
        $script:items | Where-Object { $_.RelativePath -like "*/$Leaf" }
    }
    function Get-Request {
        param([psobject] $Item, [switch] $Disabled)
        InModuleScope iSOCDeployments -Parameters @{ I = $Item; D = [bool]$Disabled } { param($I, $D) ConvertTo-iSOCAnalyticsRuleRequest -Item $I -Disabled:$D }
    }

    $script:items = @(Get-FixtureItem)
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Read-iSOCAnalyticsRuleRepo' {
    It 'reads every rule file, and nothing else' {
        $script:items.Count | Should -Be 5
        @($script:items | Where-Object { $_.RelativePath -like '*.md' }) | Should -BeNullOrEmpty
    }

    It 'names an item by its id in lower case, and keeps the file''s name and paths' {
        $item = Get-Item1 'ScheduledRule.yaml'
        $item.PSObject.TypeNames | Should -Contain 'iSOCDeployments.RepoItem'
        $item.ContentType | Should -Be 'AnalyticsRule'
        $item.Identity | Should -BeExactly '6f1c2a3b-0d4e-4f5a-9b8c-7d6e5f4a3b2c'
        $item.Name | Should -Be 'Fixture scheduled rule'
        $item.RelativePath | Should -BeExactly 'Content/AnalyticalRules/Identity/ScheduledRule.yaml'
        $item.Path | Should -Be (Join-Path $script:fixtureRepo 'Content/AnalyticalRules/Identity/ScheduledRule.yaml')
        $item.Data | Should -BeOfType [hashtable]
        $item.ParseError | Should -BeNullOrEmpty
    }

    It 'marks a rule under a Community folder as Community, and the rest as Custom' {
        (Get-Item1 'CommunityRule.yml').Source | Should -Be 'Community'
        (Get-Item1 'ScheduledRule.yaml').Source | Should -Be 'Custom'
    }

    It 'judges Community from the repository-relative path (MIGRATION.md edit E5)' {
        $copy = Join-Path $TestDrive 'Community/clone'
        New-Item -ItemType Directory -Path $copy -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:fixtureRepo 'Content') -Destination $copy -Recurse
        $items = @(Get-FixtureItem -Repo $copy)
        ($items | Where-Object { $_.RelativePath -like '*/ScheduledRule.yaml' }).Source | Should -Be 'Custom'
        ($items | Where-Object { $_.RelativePath -like '*/CommunityRule.yml' }).Source | Should -Be 'Community'
    }

    It 'keeps a file that does not parse, with the reason and the file name as its name' {
        $item = Get-Item1 'Broken.yaml'
        $item.ParseError | Should -Not -BeNullOrEmpty
        $item.Data | Should -BeNullOrEmpty
        $item.Identity | Should -BeNullOrEmpty
        $item.Name | Should -Be 'Broken'
    }
}

Describe 'Test-iSOCAnalyticsRule' {
    BeforeAll {
        function Test-Rule {
            param([psobject] $Item)
            @(InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) Test-iSOCAnalyticsRule -Item $I })
        }
        function New-Item1 {
            param([object] $Data)
            [pscustomobject]@{ ContentType = 'AnalyticsRule'; Identity = 'x'; Name = 'x'; Path = 'x'; RelativePath = 'x'; Source = 'Custom'; Data = $Data; ParseError = $null }
        }
    }

    It 'passes a complete <Leaf>' -ForEach @(@{ Leaf = 'ScheduledRule.yaml' }, @{ Leaf = 'NrtRule.yaml' }, @{ Leaf = 'CommunityRule.yml' }) {
        Test-Rule (Get-Item1 $Leaf) | Should -BeNullOrEmpty
    }

    It 'names the schedule fields a Scheduled rule is missing' {
        Test-Rule (Get-Item1 'MissingFields.yaml') | Should -Be @('Scheduled rule missing required fields: queryFrequency, queryPeriod, triggerOperator, triggerThreshold')
    }

    It 'names the required fields that are missing or blank' {
        Test-Rule (New-Item1 @{ id = 'a'; name = ' '; kind = 'NRT'; query = 'x' }) | Should -Be @('missing required fields: name, severity')
    }

    It 'says the file does not parse' {
        @(Test-Rule (Get-Item1 'Broken.yaml'))[0] | Should -BeLike 'YAML does not parse: *'
    }

    It 'says the file does not hold a mapping' {
        Test-Rule (New-Item1 @('a', 'b')) | Should -Be @('the file does not hold a YAML mapping')
    }
}

Describe 'ConvertTo-iSOCAnalyticsRuleRequest' {
    Context 'A Scheduled rule' {
        BeforeAll {
            $script:request = Get-Request (Get-Item1 'ScheduledRule.yaml')
            $script:p = $script:request.Body.properties
        }

        It 'is named by the id as written, and matched by the id in lower case' {
            $script:request.PSObject.TypeNames | Should -Contain 'iSOCDeployments.Request'
            $script:request.ResourceName | Should -BeExactly '6F1C2A3B-0D4E-4F5A-9B8C-7D6E5F4A3B2C'
            $script:request.Identity | Should -BeExactly '6f1c2a3b-0d4e-4f5a-9b8c-7d6e5f4a3b2c'
        }

        It 'carries the core fields' {
            $script:request.Body.kind | Should -Be 'Scheduled'
            $script:p.displayName | Should -Be 'Fixture scheduled rule'
            $script:p.description | Should -Match 'used by the iSOCDeployments tests'
            $script:p.severity | Should -Be 'Medium'
            $script:p.query | Should -Match '^SigninLogs'
            $script:p.enabled | Should -BeTrue
        }

        It 'defaults suppression off for five hours' {
            $script:p.suppressionEnabled | Should -BeFalse
            $script:p.suppressionDuration | Should -Be 'PT5H'
        }

        It 'carries the schedule, with the operator in the API spelling' {
            $script:p.queryFrequency | Should -Be 'PT1H'
            $script:p.queryPeriod | Should -Be 'PT24H'
            $script:p.triggerThreshold | Should -Be 0
            $script:p.triggerThreshold | Should -BeOfType [int]
            $script:p.triggerOperator | Should -BeExactly 'GreaterThan'
        }

        It 'splits techniques into parents and sub-techniques' {
            @($script:p.tactics) | Should -Be @('CredentialAccess', 'InitialAccess')
            @($script:p.techniques) | Should -Be @('T1110', 'T1078')
            @($script:p.subTechniques) | Should -Be @('T1110.003', 'T1078.004')
        }

        It 'passes the optional blocks through' {
            @($script:p.entityMappings).Count | Should -Be 2
            $script:p.customDetails.Failures | Should -Be 'Failures'
            $script:p.incidentConfiguration.createIncident | Should -BeTrue
            $script:p.ContainsKey('alertDetailsOverride') | Should -BeFalse
            $script:p.ContainsKey('eventGroupingSettings') | Should -BeFalse
        }

        It 'is sent disabled with -Disabled' {
            (Get-Request (Get-Item1 'ScheduledRule.yaml') -Disabled).Body.properties.enabled | Should -BeFalse
        }
    }

    Context 'An NRT rule' {
        BeforeAll {
            $script:p = (Get-Request (Get-Item1 'NrtRule.yaml')).Body.properties
        }

        It 'carries no schedule' {
            foreach ($key in 'queryFrequency', 'queryPeriod', 'triggerOperator', 'triggerThreshold') { $script:p.ContainsKey($key) | Should -BeFalse }
        }

        It 'keeps the file''s enabled and suppression settings' {
            $script:p.enabled | Should -BeFalse
            $script:p.suppressionEnabled | Should -BeTrue
            $script:p.suppressionDuration | Should -Be 'PT1H'
        }

        It 'sends no sub-techniques when it has none' {
            @($script:p.techniques) | Should -Be @('T1098')
            $script:p.ContainsKey('subTechniques') | Should -BeFalse
        }
    }

    Context 'A Community rule' {
        It 'is always sent disabled' {
            $p = (Get-Request (Get-Item1 'CommunityRule.yml')).Body.properties
            $p.enabled | Should -BeFalse
            $p.triggerOperator | Should -BeExactly 'GreaterThan'
            $p.description | Should -BeExactly ''
        }
    }

    It 'reads techniques from the key techniques when relevantTechniques is absent' {
        $item = [pscustomobject]@{ ContentType = 'AnalyticsRule'; Identity = 'r'; Source = 'Custom'; Data = @{ id = 'r'; name = 'n'; kind = 'NRT'; severity = 'Low'; query = 'q'; techniques = @('T1059.001') } }
        $p = (Get-Request $item).Body.properties
        @($p.techniques) | Should -Be @('T1059')
        @($p.subTechniques) | Should -Be @('T1059.001')
    }
}

Describe 'ConvertTo-iSOCTriggerOperator' {
    It 'maps <Value> to <Expected>' -ForEach @(
        @{ Value = 'gt'; Expected = 'GreaterThan' }, @{ Value = 'GT'; Expected = 'GreaterThan' }, @{ Value = 'greaterThan'; Expected = 'GreaterThan' }
        @{ Value = 'lt'; Expected = 'LessThan' }, @{ Value = 'eq'; Expected = 'Equal' }, @{ Value = 'ne'; Expected = 'NotEqual' }
        @{ Value = 'NotEqual'; Expected = 'NotEqual' }, @{ Value = 'GreaterThanOrEqual'; Expected = 'GreaterThanOrEqual' }
    ) {
        InModuleScope iSOCDeployments -Parameters @{ V = $Value } { param($V) ConvertTo-iSOCTriggerOperator $V } | Should -BeExactly $Expected
    }

    It 'returns nothing for an empty value' {
        InModuleScope iSOCDeployments { ConvertTo-iSOCTriggerOperator '' } | Should -BeNullOrEmpty
    }

    It 'agrees with Convert-TriggerOperator in the drift script' {
        Import-Module (Join-Path $script:repoRoot 'Tests/_helpers/Import-ScriptFunctions.psm1') -Force
        Import-ScriptFunctions -Path (Join-Path $script:repoRoot 'Tools/Test-SentinelRuleDrift.ps1')
        foreach ($value in 'gt', 'lt', 'eq', 'ne', 'GreaterThan', 'lessthan', 'Equal', 'NOTEQUAL', 'Other') {
            InModuleScope iSOCDeployments -Parameters @{ V = $value } { param($V) ConvertTo-iSOCTriggerOperator $V } | Should -BeExactly (Convert-TriggerOperator $value)
        }
    }
}

Describe 'Get-iSOCAnalyticsRuleQuery' {
    It 'returns the query, or nothing for a file without one' {
        InModuleScope iSOCDeployments -Parameters @{ I = (Get-Item1 'NrtRule.yaml') } { param($I) Get-iSOCAnalyticsRuleQuery -Item $I } | Should -Match '^AuditLogs'
        InModuleScope iSOCDeployments -Parameters @{ I = (Get-Item1 'Broken.yaml') } { param($I) Get-iSOCAnalyticsRuleQuery -Item $I } | Should -BeNullOrEmpty
    }
}

Describe 'Parity with Deploy-CustomContent.ps1' {
    BeforeAll {
        # Run the old deployer's rule step over the real repository with
        # everything around it stood in for, capturing each request.
        Import-Module (Join-Path $script:repoRoot 'Tests/_helpers/Import-ScriptFunctions.psm1') -Force
        Import-ScriptFunctions -Path (Join-Path $script:repoRoot 'Deploy/content/Deploy-CustomContent.ps1')
        function Write-PipelineMessage { param($Message, $Level) }
        # The deployer asks this once per file, just before it sends the file,
        # so it tags each captured request with the file it came from.
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
        $script:SkipCommunityDetections = $false
        $script:WhatIf = $false
        $script:BaseUri = "https://management.azure.com$($script:workspacePath)"
        $script:AuthHeader = @{}
        $script:AlertRuleApiVersion = '2025-07-01-preview'
        $script:legacyCalls = [System.Collections.Generic.List[object]]::new()
        $script:legacyCounters = Deploy-CustomDetections

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
        foreach ($item in Get-FixtureItem -Repo $script:repoRoot) { $script:moduleItems[$item.RelativePath] = $item }
    }

    It 'sent a request for every rule it read' {
        $script:legacyCounters.Failed | Should -Be 0
        $script:legacyCounters.Skipped | Should -Be 0
        $script:legacyCalls.Count | Should -Be $script:moduleItems.Count
    }

    It 'sends <Path> as Deploy-CustomContent.ps1 does' -ForEach $ruleFiles {
        $item = $script:moduleItems[$Path]
        $item | Should -Not -BeNullOrEmpty
        @(InModuleScope iSOCDeployments -Parameters @{ I = $item } { param($I) Test-iSOCAnalyticsRule -Item $I }) | Should -BeNullOrEmpty

        $request = Get-Request $item
        $legacy = @($script:legacyByFile[$Path])
        $legacy.Count | Should -Be 1 -Because 'the deployer sent one request for this file'

        $path = InModuleScope iSOCDeployments -Parameters @{ C = $script:context; N = $request.ResourceName } {
            param($C, $N)
            $type = Get-iSOCContentTypeDefinition -Name AnalyticsRule
            '{0}?api-version={1}' -f (Get-iSOCResourcePath -Context $C -ContentType $type -Name $N), (Get-iSOCApiVersion $type.ApiVersion)
        }
        "https://management.azure.com$path" | Should -BeExactly $legacy[0].Uri
        $legacy[0].Method | Should -Be 'Put'
        ConvertTo-ParityJson $request.Body | Should -BeExactly (ConvertTo-ParityJson $legacy[0].Body)
    }
}
