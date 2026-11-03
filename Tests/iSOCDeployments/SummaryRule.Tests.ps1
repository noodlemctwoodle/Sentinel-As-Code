#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the summary rule content type's handlers, and for
    parity with the deployer they were taken from.

.DESCRIPTION
    The handlers are tested on the fixture repository: reading one item
    per file, validation (the messages Deploy-CustomContent.ps1 logs for
    missing fields, a bin size Log Analytics refuses and a destination
    table that is not custom), and the request body with and without its
    optional fields. The parity block lifts Deploy-CustomSummaryRules out
    of Deploy/content/Deploy-CustomContent.ps1 by AST, runs it over every
    summary rule in Content/SummaryRules/ with the REST call captured, and
    holds each captured request (path, api-version and body) to the one
    the module builds for the same file.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/SummaryRule.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/SummaryRule.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+, Pester 5+

    The parity block goes when Deploy-CustomContent.ps1 is removed at
    cut-over.
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $ruleFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content/SummaryRules') -Filter '*.json' -Recurse -File) |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '_helpers/Parity.psm1') -Force
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

Describe 'Parity with Deploy-CustomContent.ps1' {
    BeforeAll {
        Import-Module (Join-Path $script:repoRoot 'Tests/_helpers/Import-ScriptFunctions.psm1') -Force
        Import-ScriptFunctions -Path (Join-Path $script:repoRoot 'Deploy/content/Deploy-CustomContent.ps1')
        function Write-PipelineMessage { param($Message, $Level) }
        function Test-ShouldDeployFile { param($FilePath) $script:legacyFile = $FilePath; $true }
        function Test-ContentDependencies { param($ContentPath) @{ Passed = $true; Missing = @() } }
        function Set-DeploymentItemState { param($FilePath, $Status) }
        function Invoke-SentinelApi {
            param($Uri, $Method, $Headers, $Body)
            $script:legacyCalls.Add([pscustomobject]@{ File = $script:legacyFile; Uri = $Uri; Method = $Method; Body = $Body })
        }

        $script:workspacePath = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/ws'
        $script:BasePath = $script:repoRoot
        $script:WhatIf = $false
        $script:ServerUrl = 'https://management.azure.com'
        $script:SubscriptionId = '00000000-0000-0000-0000-000000000000'
        $script:ResourceGroup = 'rg'
        $script:Workspace = 'ws'
        $script:SummaryRuleApiVersion = '2025-07-01'
        $script:AuthHeader = @{}
        $script:legacyCalls = [System.Collections.Generic.List[object]]::new()
        $script:legacyCounters = Deploy-CustomSummaryRules

        $script:legacyByFile = @{}
        foreach ($call in $script:legacyCalls) {
            $script:legacyByFile[[System.IO.Path]::GetRelativePath($script:repoRoot, $call.File).Replace('\', '/')] = $call
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
        foreach ($item in Get-RuleItem -Repo $script:repoRoot) { $script:moduleItems[$item.RelativePath] = $item }
    }

    It 'sent a request for every summary rule it read' {
        $script:legacyCounters.Failed | Should -Be 0
        $script:legacyCounters.Skipped | Should -Be 0
        $script:legacyCalls.Count | Should -Be $script:moduleItems.Count
    }

    It 'sends <Path> as Deploy-CustomContent.ps1 does' -ForEach $ruleFiles {
        $item = $script:moduleItems[$Path]
        Test-Item $item | Should -BeNullOrEmpty
        $request = Get-Request $item
        $legacy = $script:legacyByFile[$Path]

        $path = InModuleScope iSOCDeployments -Parameters @{ C = $script:context; N = $request.ResourceName } {
            param($C, $N)
            $type = Get-iSOCContentTypeDefinition -Name SummaryRule
            '{0}?api-version={1}' -f (Get-iSOCResourcePath -Context $C -ContentType $type -Name $N), (Get-iSOCApiVersion $type.ApiVersion)
        }
        "https://management.azure.com$path" | Should -BeExactly $legacy.Uri
        $legacy.Method | Should -Be 'Put'
        ConvertTo-ParityJson $request.Body | Should -BeExactly (ConvertTo-ParityJson $legacy.Body)
    }
}
