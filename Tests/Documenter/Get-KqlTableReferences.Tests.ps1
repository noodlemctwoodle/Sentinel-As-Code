#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }, Az.Accounts

<#
.SYNOPSIS
    Tests for the Documenter's table-reference builder, which maps analytics
    rules and rule templates to the tables they read.

.DESCRIPTION
    Imports Sentinel.Common (for Get-KqlBareIdentifiers), dot-sources
    Tools/Documenter/Private/Get-KqlTableReferences.ps1 and runs the builder
    over the fixture rules and templates. The expected output is the pair of
    hand-authored reference files in the fixture, so a change in either the
    extractor or the fixture shows up as a diff here rather than as a wrong
    gap finding later.

.EXAMPLE
    Invoke-Pester -Path Tests/Documenter/Get-KqlTableReferences.Tests.ps1 -Output Detailed

    Runs the suite with per-assertion output.

.NOTES
    File:         Tests/Documenter/Get-KqlTableReferences.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-09
    Version:      0.1.0
    Last Updated: 2026-10-09
    Requires:     PowerShell 7.2+, Pester 5+, Az.Accounts (Sentinel.Common import)
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'Modules/Sentinel.Common/Sentinel.Common.psd1') -Force -ErrorAction Stop
    . (Join-Path $repoRoot 'Tools/Documenter/Private/Get-KqlTableReferences.ps1')

    $raw = Join-Path $repoRoot 'Tests/Documenter/Fixtures/sample/_raw'
    $script:rules     = Get-Content (Join-Path $raw 'alert-rules.json') -Raw | ConvertFrom-Json
    $script:templates = Get-Content (Join-Path $raw 'alert-rule-templates.json') -Raw | ConvertFrom-Json
    $script:expectedRuleRefs     = Get-Content (Join-Path $raw 'rule-table-references.json') -Raw | ConvertFrom-Json
    $script:expectedTemplateRefs = Get-Content (Join-Path $raw 'template-table-references.json') -Raw | ConvertFrom-Json

    $script:ruleRefs     = Get-RuleTableReferences -AlertRules $script:rules
    $script:templateRefs = Get-TemplateTableReferences -Templates $script:templates -AlertRules $script:rules

    function Canonical($rows) { @($rows) | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 5 } }
}

Describe 'Resolve-KqlTableNames' {
    It 'keeps tables and drops ASIM parser names' {
        $q = "let recent = SigninLogs | where ResultType == 0;`nrecent | join kind=inner (AuditLogs | project UserPrincipalName) on UserPrincipalName | union imAuthentication"
        Resolve-KqlTableNames -Query $q | Should -Be @('AuditLogs', 'SigninLogs')
    }

    It 'drops _ASim and _Im_ functions' {
        Resolve-KqlTableNames -Query 'union _ASim_Dns, _Im_Dns, DnsEvents' | Should -Be @('DnsEvents')
    }

    It 'takes every operand of a comma-separated union' {
        Resolve-KqlTableNames -Query "union withsource=T SecurityEvent, WindowsEvent, Event`n| where EventID == 4688" | Should -Be @('Event', 'SecurityEvent', 'WindowsEvent')
    }

    It 'adds the first token of each connector data type' {
        Resolve-KqlTableNames -Query '' -DataTypes @('OfficeActivity (SharePoint)', 'SigninLogs') | Should -Be @('OfficeActivity', 'SigninLogs')
    }

    It 'returns an empty array for an empty query' {
        @(Resolve-KqlTableNames -Query '').Count | Should -Be 0
        @(Resolve-KqlTableNames -Query $null).Count | Should -Be 0
    }
}

Describe 'Get-RuleTableReferences' {
    It 'matches the hand-authored fixture reference file' {
        Canonical $ruleRefs | Should -Be (Canonical $expectedRuleRefs)
    }

    It 'gives a rule without a query an empty table list' {
        ($ruleRefs | Where-Object RuleId -like 'bbbbbbbb-*').Tables.Count | Should -Be 0
    }

    It 'returns an empty array for no rules' {
        @(Get-RuleTableReferences -AlertRules @()).Count | Should -Be 0
        @(Get-RuleTableReferences -AlertRules $null).Count | Should -Be 0
    }
}

Describe 'Get-TemplateTableReferences' {
    It 'matches the hand-authored fixture reference file' {
        Canonical $templateRefs | Should -Be (Canonical $expectedTemplateRefs)
    }

    It 'marks a template as deployed when a rule references it' {
        ($templateRefs | Where-Object TemplateId -eq 'tmpl-suspicious-signin').AlreadyDeployed | Should -BeTrue
        ($templateRefs | Where-Object TemplateId -eq 'tmpl-data-exfiltration').AlreadyDeployed | Should -BeFalse
    }

    It 'flags deprecated templates by display name' {
        ($templateRefs | Where-Object TemplateId -eq 'tmpl-deprecated-firewall').Deprecated | Should -BeTrue
        @($templateRefs | Where-Object { $_.Deprecated }).Count | Should -Be 1
    }

    It 'includes tables declared only through connector data types' {
        ($templateRefs | Where-Object TemplateId -eq 'tmpl-data-exfiltration').Tables | Should -Contain 'OfficeActivity'
    }
}
