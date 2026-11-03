#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the automation rule content type's handlers, and for
    parity with the deployer they were taken from.

.DESCRIPTION
    The handlers are tested on the fixture repository: reading one item
    per file, validation (the message Deploy-CustomContent.ps1 logs, and a
    missing field reported rather than thrown, MIGRATION.md edit E9), and
    the request body. The parity block lifts Deploy-CustomAutomationRules
    out of Deploy/content/Deploy-CustomContent.ps1 by AST, runs it over
    every automation rule in Content/AutomationRules/ with the REST call
    captured, and holds each captured request (path, api-version and body)
    to the one the module builds for the same file.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/AutomationRule.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/AutomationRule.Tests.ps1
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
    $ruleFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content/AutomationRules') -Filter '*.json' -Recurse -File) |
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
            $type = Get-iSOCContentTypeDefinition -Name AutomationRule
            Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $R; ContentType = $type }
        }
    }
    function Get-Request {
        param([psobject] $Item)
        InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) ConvertTo-iSOCAutomationRuleRequest -Item $I }
    }
    function Test-Item {
        param([psobject] $Item)
        @(InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) Test-iSOCAutomationRule -Item $I })
    }
    function New-RuleFile {
        param([string] $Json)
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $repo 'Content/AutomationRules') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'Content/AutomationRules/Rule.json') -Value $Json
        @(Get-RuleItem -Repo $repo)[0]
    }

    $script:items = @(Get-RuleItem)
    $script:close = $script:items | Where-Object { $_.RelativePath -like '*FixtureAutoClose.json' }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Automation rule handlers' {
    It 'reads one item per file, named by its automationRuleId in lower case' {
        @($script:items.RelativePath) | Should -Be @('Content/AutomationRules/FixtureAutoClose.json', 'Content/AutomationRules/MissingActions.json')
        $script:close.Identity | Should -BeExactly 'b3c4d5e6-f7a8-4901-b2c3-d4e5f6a7b8c9'
        $script:close.Name | Should -Be 'Fixture: close informational incidents'
        $script:close.ParseError | Should -BeNullOrEmpty
    }

    It 'passes a complete rule' {
        Test-Item $script:close | Should -BeNullOrEmpty
    }

    It 'says which fields a rule needs when one is missing' {
        $missing = $script:items | Where-Object { $_.RelativePath -like '*MissingActions.json' }
        Test-Item $missing | Should -Be @('missing required fields (automationRuleId, displayName, order, triggeringLogic, actions).')
    }

    It 'accepts order 0' {
        $script:close.Data.order | Should -Be 0
        Test-Item $script:close | Should -BeNullOrEmpty
    }

    It 'reports a file that does not parse as a parse error' {
        $item = New-RuleFile -Json '{ not json'
        $item.ParseError | Should -BeLike 'the JSON does not parse*'
        @(Test-Item $item)[0] | Should -BeExactly $item.ParseError
        $item.Identity | Should -BeNullOrEmpty
        $item.Name | Should -Be 'Rule'
    }

    It 'builds the body the deployer sends' {
        $request = Get-Request $script:close
        $request.ResourceName | Should -BeExactly 'b3c4d5e6-f7a8-4901-b2c3-d4e5f6a7b8c9'
        $p = $request.Body.properties
        @($p.Keys | Sort-Object) | Should -Be @('actions', 'displayName', 'order', 'triggeringLogic')
        $p.displayName | Should -Be 'Fixture: close informational incidents'
        $p.order | Should -BeOfType [int]
        $p.triggeringLogic.triggersOn | Should -BeExactly 'Incidents'
        $p.actions.Count | Should -Be 1
        $p.actions[0].actionType | Should -BeExactly 'ModifyProperties'
    }

    It 'keeps a single action as a list' {
        $json = '{ "automationRuleId": "x", "displayName": "X", "order": 1, "triggeringLogic": { "isEnabled": true }, "actions": { "order": 1, "actionType": "RunPlaybook" } }'
        $body = (Get-Request (New-RuleFile -Json $json)).Body
        ConvertTo-Json -InputObject $body -Depth 10 -Compress | Should -BeLike '*"actions":`[{*'
    }
}

Describe 'Parity with Deploy-CustomContent.ps1' {
    BeforeAll {
        Import-Module (Join-Path $script:repoRoot 'Tests/_helpers/Import-ScriptFunctions.psm1') -Force
        Import-ScriptFunctions -Path (Join-Path $script:repoRoot 'Deploy/content/Deploy-CustomContent.ps1')
        function Write-PipelineMessage { param($Message, $Level) }
        # The file the deployer asks about names each captured request.
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
        $script:BaseUri = "https://management.azure.com$($script:workspacePath)"
        $script:SentinelApiVersion = '2025-09-01'
        $script:AuthHeader = @{}
        $script:legacyCalls = [System.Collections.Generic.List[object]]::new()
        $script:legacyCounters = Deploy-CustomAutomationRules

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

    It 'sent a request for every automation rule it read' {
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
            $type = Get-iSOCContentTypeDefinition -Name AutomationRule
            '{0}?api-version={1}' -f (Get-iSOCResourcePath -Context $C -ContentType $type -Name $N), (Get-iSOCApiVersion $type.ApiVersion)
        }
        "https://management.azure.com$path" | Should -BeExactly $legacy.Uri
        $legacy.Method | Should -Be 'Put'
        ConvertTo-ParityJson $request.Body | Should -BeExactly (ConvertTo-ParityJson $legacy.Body)
    }
}
