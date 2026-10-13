#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests that the Blueprint's move into the iSOCBlueprint module
    stays complete.

.DESCRIPTION
    Modules/iSOCBlueprint/MIGRATION.md records where every file under the
    old Tools/Blueprint folder went. These tests hold the repository to
    it: no copied, moved or retired source path exists any more, every
    destination does, every vendored original is still there to be copied
    from, and the edits each row names are the ones the map documents. A
    file restored to the old folder, or a destination deleted, fails here.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Migration-Map.Tests.ps1

    Runs the whole suite.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Migration-Map.Tests.ps1 -Output Detailed

    Lists every row checked.

.NOTES
    File:         Tests/iSOCBlueprint/Migration-Map.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.2.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+, Pester 5+

    Version 0.1.0 checked the map against the old folder while it still
    existed (every file mapped, every edit still matching its source).
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $PSScriptRoot '_helpers/Migration.psm1') -Force
    $rows = @(Get-MigrationMap -RepoRoot $repoRoot | ForEach-Object { @{ Row = $_; Source = $_.Source } })
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $PSScriptRoot '_helpers/Migration.psm1') -Force
    $script:map = @(Get-MigrationMap -RepoRoot $script:repoRoot)
    $script:mapText = Get-Content -LiteralPath (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/MIGRATION.md') -Raw

    function Test-RepoPath {
        param([string] $Path)
        Test-Path -LiteralPath (Join-Path $script:repoRoot ($Path -replace '/\*\*$', ''))
    }
}

Describe 'The move out of Tools/Blueprint' {
    It 'reads every row from MIGRATION.md' {
        $script:map.Count | Should -BeGreaterThan 40
    }

    It 'left nothing in Tools/Blueprint' {
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'Tools/Blueprint') | Should -BeFalse
    }

    It '<Source> uses a known action' -ForEach $rows {
        $Row.Action | Should -BeIn @('Copy', 'Move', 'Retire', 'Vendor')
    }

    It '<Source> is where the map says' -ForEach $rows {
        switch ($Row.Action) {
            'Vendor' {
                Test-RepoPath $Row.Source | Should -BeTrue -Because 'the original is still the source of truth'
                Test-RepoPath $Row.Destination | Should -BeTrue
            }
            'Retire' {
                Test-RepoPath $Row.Source | Should -BeFalse
                $Row.Destination | Should -BeNullOrEmpty
            }
            default {
                Test-RepoPath $Row.Source | Should -BeFalse -Because 'the old copy is gone'
                Test-RepoPath $Row.Destination | Should -BeTrue
            }
        }
    }

    It '<Source> kept its place in the tree when copied' -ForEach $rows {
        if ($Row.Action -eq 'Copy') {
            $Row.Destination | Should -BeExactly ($Row.Source -replace '^Tools/Blueprint/', 'Modules/iSOCBlueprint/Engine/')
        }
    }

    It 'documents every edit a row names' {
        foreach ($id in @($script:map | ForEach-Object Edits | Where-Object { $_ } | Sort-Object -Unique)) {
            $script:mapText | Should -Match ("(?m)^\|\s*$id\s*\|") -Because "$id is named in the table"
        }
    }

    It 'sends no two rows to the same destination' {
        $dest = @($script:map | Where-Object { $_.Destination } | ForEach-Object Destination)
        @($dest | Group-Object | Where-Object Count -gt 1).Name | Should -BeNullOrEmpty
    }
}
