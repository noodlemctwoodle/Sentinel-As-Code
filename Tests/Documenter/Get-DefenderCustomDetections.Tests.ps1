#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the Defender XDR custom-detection projection.

.DESCRIPTION
    Get-CustomDetectionTableReferences turns Graph detectionRule objects into
    the rows the gap engine, the renderer and the site build read. These
    tests feed it the fixture rules and compare with the hand-authored
    reference file, and check the empty and partial-object cases. The Graph
    call itself needs a tenant and is not exercised here.

.NOTES
    File:         Tests/Documenter/Get-DefenderCustomDetections.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-12
    Version:      0.1.0
    Last Updated: 2026-10-12
    Requires:     PowerShell 7.2+, Pester 5+, Az.Accounts (Sentinel.Common)
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'Modules/Sentinel.Common/Sentinel.Common.psd1') -Force -ErrorAction Stop
    . (Join-Path $repoRoot 'Tools/Documenter/Private/Get-KqlTableReferences.ps1')
    . (Join-Path $repoRoot 'Tools/Documenter/Private/Get-DefenderCustomDetections.ps1')
    $fixture = Join-Path $repoRoot 'Tests/Documenter/Fixtures/sample/_raw'
    $script:rules = Get-Content (Join-Path $fixture 'defender-custom-detections.json') -Raw | ConvertFrom-Json -Depth 32
    $script:expected = Get-Content (Join-Path $fixture 'custom-detection-table-references.json') -Raw | ConvertFrom-Json -Depth 32
}

Describe 'Get-CustomDetectionTableReferences' {
    It 'projects the fixture rules to the reference rows' {
        $rows = @(Get-CustomDetectionTableReferences -Detections $script:rules)
        $rows.Count | Should -Be @($script:expected).Count
        foreach ($e in $script:expected) {
            $r = $rows | Where-Object RuleId -eq $e.RuleId
            $r | Should -Not -BeNullOrEmpty
            $r.RuleName | Should -Be $e.RuleName
            $r.Enabled | Should -Be $e.Enabled
            $r.Severity | Should -Be $e.Severity
            $r.Period | Should -Be $e.Period
            @($r.Tables) | Should -Be @($e.Tables)
        }
    }

    It 'reads the tables out of a joined query' {
        $r = @(Get-CustomDetectionTableReferences -Detections $script:rules) | Where-Object RuleId -eq 'cd-0001'
        @($r.Tables) | Should -Contain 'DeviceProcessEvents'
        @($r.Tables) | Should -Contain 'EmailEvents'
    }

    It 'returns an empty array for no rules' {
        @(Get-CustomDetectionTableReferences -Detections $null).Count | Should -Be 0
        @(Get-CustomDetectionTableReferences -Detections @()).Count | Should -Be 0
    }

    It 'tolerates a rule without query, schedule or action' {
        $bare = [pscustomobject]@{ id = 'x'; displayName = 'Bare'; isEnabled = $true }
        $r = @(Get-CustomDetectionTableReferences -Detections @($bare))
        $r.Count | Should -Be 1
        $r[0].Enabled | Should -BeTrue
        @($r[0].Tables).Count | Should -Be 0
        $r[0].Severity | Should -Be ''
    }
}
