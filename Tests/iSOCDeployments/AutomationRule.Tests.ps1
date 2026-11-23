#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the automation rule content type's handlers.

.DESCRIPTION
    The handlers are tested on the fixture repository: reading one item
    per file, validation (the message Deploy-CustomContent.ps1 logged, and
    a missing field reported rather than thrown, MIGRATION.md edit E9),
    and the request body. Every rule under Content/AutomationRules/ in
    this repository is read through the ReadRepo handler, must pass
    Test-iSOCAutomationRule with no issues, and must build a request
    through the ToRequest handler. Parity with Deploy-CustomContent.ps1
    was proven on release/26.11.0 before the script was removed.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/AutomationRule.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/AutomationRule.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $ruleFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content/AutomationRules') -Filter '*.json' -Recurse -File) |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'

    function Get-RuleItem {
        <#
        .SYNOPSIS
            Read the automation rule items from a repository, inside the module scope.
        .PARAMETER Repo
            Repository root to read; defaults to the fixture repository.
        #>
        param([string] $Repo = $script:fixtureRepo)
        InModuleScope iSOCDeployments -Parameters @{ R = $Repo } {
            param($R)
            $type = Get-iSOCContentTypeDefinition -Name AutomationRule
            Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $R; ContentType = $type }
        }
    }
    function Get-Request {
        <#
        .SYNOPSIS
            Build the deployment request for an automation rule item, inside the module scope.
        .PARAMETER Item
            Parsed content item to act on.
        #>
        param([psobject] $Item)
        InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) ConvertTo-iSOCAutomationRuleRequest -Item $I }
    }
    function Test-Item {
        <#
        .SYNOPSIS
            Validate an automation rule item with the module and return its findings.
        .PARAMETER Item
            Parsed content item to act on.
        #>
        param([psobject] $Item)
        @(InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) Test-iSOCAutomationRule -Item $I })
    }
    function New-RuleFile {
        <#
        .SYNOPSIS
            Write the given JSON as a rule file in a fresh repository and return its parsed item.
        .PARAMETER Json
            JSON text written to the rule file.
        #>
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

Describe 'Content/AutomationRules in this repository' {
    BeforeAll {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        $script:repoType = InModuleScope iSOCDeployments { Get-iSOCContentTypeDefinition -Name AutomationRule }
        function Invoke-RepoHandler {
            <#
            .SYNOPSIS
                Invoke a handler of the repository content type, inside the module scope.
            .PARAMETER Handler
                Name of the content-type handler to invoke.
            .PARAMETER Parameters
                Parameters passed to the command or handler.
            #>
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
        $item | Should -Not -BeNullOrEmpty -Because 'the ReadRepo handler reads everything under Content/AutomationRules'
        Test-Item $item | Should -BeNullOrEmpty
        { $script:repoRequest = Invoke-RepoHandler -Handler ToRequest -Parameters @{ Item = $item } } | Should -Not -Throw
        $script:repoRequest.Body | Should -Not -BeNullOrEmpty
    }
}
