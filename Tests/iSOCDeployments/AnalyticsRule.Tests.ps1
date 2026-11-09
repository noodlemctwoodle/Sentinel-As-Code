#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the analytics rule content type's handlers.

.DESCRIPTION
    The handlers are tested on the fixture repository: reading (identity,
    name, Community source, unreadable files), validation (the messages
    Deploy-CustomContent.ps1 logged), the request body (every field the
    deployer sent, the operator map, the technique split, the enabled
    rules) and the query. The operator map is also held to the values the
    drift script's Convert-TriggerOperator returned. Every rule under
    Content/AnalyticalRules/ in this repository is read through the
    ReadRepo handler, must pass Test-iSOCAnalyticsRule with no issues, and
    must build a request through the ToRequest handler.

    Parity with Deploy-CustomContent.ps1 was proven on release/26.11.0
    before the script was removed.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/AnalyticsRule.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/AnalyticsRule.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+, powershell-yaml
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $ruleFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content/AnalyticalRules') -Recurse -File -Include '*.yaml', '*.yml') |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
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

    It 'returns what Convert-TriggerOperator in the drift script returned' {
        # What Convert-TriggerOperator in the drift script returned for each
        # value, run on release/26.11.0 before the script was removed.
        $expected = [ordered]@{
            'gt' = 'GreaterThan'; 'lt' = 'LessThan'; 'eq' = 'Equal'; 'ne' = 'NotEqual'; 'GreaterThan' = 'GreaterThan'
            'lessthan' = 'LessThan'; 'Equal' = 'Equal'; 'NOTEQUAL' = 'NotEqual'; 'Other' = 'Other'
        }
        foreach ($value in $expected.Keys) {
            InModuleScope iSOCDeployments -Parameters @{ V = $value } { param($V) ConvertTo-iSOCTriggerOperator $V } | Should -BeExactly $expected[$value] -Because $value
        }
    }
}

Describe 'Get-iSOCAnalyticsRuleKql' {
    It 'returns the query, or nothing for a file without one' {
        InModuleScope iSOCDeployments -Parameters @{ I = (Get-Item1 'NrtRule.yaml') } { param($I) Get-iSOCAnalyticsRuleKql -Item $I } | Should -Match '^AuditLogs'
        InModuleScope iSOCDeployments -Parameters @{ I = (Get-Item1 'Broken.yaml') } { param($I) Get-iSOCAnalyticsRuleKql -Item $I } | Should -BeNullOrEmpty
    }
}

Describe 'Content/AnalyticalRules in this repository' {
    BeforeAll {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        $script:repoType = InModuleScope iSOCDeployments { Get-iSOCContentTypeDefinition -Name AnalyticsRule }
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
        $item | Should -Not -BeNullOrEmpty -Because 'the ReadRepo handler reads everything under Content/AnalyticalRules'
        @(InModuleScope iSOCDeployments -Parameters @{ I = $item } { param($I) Test-iSOCAnalyticsRule -Item $I }) | Should -BeNullOrEmpty
        { $script:repoRequest = Invoke-RepoHandler -Handler ToRequest -Parameters @{ Item = $item } } | Should -Not -Throw
        $script:repoRequest.Body | Should -Not -BeNullOrEmpty
    }
}
