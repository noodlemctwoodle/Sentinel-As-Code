#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the iSOCBlueprint migration map and engine edits.

.DESCRIPTION
    The Blueprint moves from Tools/Blueprint into the iSOCBlueprint module.
    Modules/iSOCBlueprint/MIGRATION.md maps every file to its destination
    and Tests/iSOCBlueprint/Engine-Edits.psd1 lists the only changes a
    copied file may carry. These tests fail when a file under
    Tools/Blueprint has no row, when a row names a file that does not
    exist, or when an edit no longer matches its source, so nothing is left
    behind and no edit goes stale.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Migration-Map.Tests.ps1

    Runs the whole suite.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Migration-Map.Tests.ps1 -Output Detailed

    Lists every file and edit checked.

.NOTES
    File:         Tests/iSOCBlueprint/Migration-Map.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $PSScriptRoot '_helpers/Migration.psm1') -Force
    $map = @(Get-MigrationMap -RepoRoot $repoRoot)
    $sourceFiles = @(Get-BlueprintSourceFile -RepoRoot $repoRoot -Map $map | ForEach-Object { @{ Path = $_ } })
    $rows = @($map | ForEach-Object { @{ Row = $_; Source = $_.Source } })
    $edits = Get-EngineEdit -RepoRoot $repoRoot
    $changes = @(foreach ($e in $edits.Edits) {
            $i = 0
            foreach ($c in $e.Changes) { $i++; @{ Id = $e.Id; File = $e.File; Index = $i; Find = $c.Find } }
        })
    $headerFiles = @($map | Where-Object { $_.Action -eq 'Copy' -and $_.Source -like '*.ps1' } | ForEach-Object { @{ Source = $_.Source } })
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $PSScriptRoot '_helpers/Migration.psm1') -Force
    $script:map = @(Get-MigrationMap -RepoRoot $script:repoRoot)
    $script:edits = Get-EngineEdit -RepoRoot $script:repoRoot
}

Describe 'Migration map coverage' {
    It 'reads rows from MIGRATION.md' {
        $script:map.Count | Should -BeGreaterThan 40
    }

    It 'has a row for <Path>' -ForEach $sourceFiles {
        Find-MigrationRow -Map $script:map -Path $Path | Should -Not -BeNullOrEmpty
    }
}

Describe 'Migration map rows' {
    It '<Source> names a file that exists' -ForEach $rows {
        $path = $Source -replace '/\*\*$', ''
        Test-Path -LiteralPath (Join-Path $script:repoRoot $path) | Should -BeTrue
    }

    It '<Source> uses a known action' -ForEach $rows {
        $Row.Action | Should -BeIn @('Copy', 'Move', 'Retire', 'Vendor')
    }

    It '<Source> has a destination unless it is retired' -ForEach $rows {
        if ($Row.Action -eq 'Retire') { $Row.Destination | Should -BeNullOrEmpty }
        else { $Row.Destination | Should -Not -BeNullOrEmpty }
    }

    It '<Source> keeps its place in the tree when copied' -ForEach $rows {
        if ($Row.Action -eq 'Copy') {
            $Row.Destination | Should -BeExactly ($Row.Source -replace '^Tools/Blueprint/', 'Modules/iSOCBlueprint/Engine/')
        }
    }

    It 'sends no two rows to the same destination' {
        $dest = @($script:map | Where-Object { $_.Destination } | ForEach-Object Destination)
        @($dest | Group-Object | Where-Object Count -gt 1).Name | Should -BeNullOrEmpty
    }
}

Describe 'Engine edits' {
    It 'names only edits that are defined' {
        $defined = @($script:edits.Edits | ForEach-Object Id)
        $named = @($script:map | ForEach-Object Edits | Where-Object { $_ })
        @($named | Where-Object { $_ -notin $defined }) | Should -BeNullOrEmpty
    }

    It 'lists each defined edit on the row of the file it changes' {
        foreach ($e in $script:edits.Edits) {
            $row = $script:map | Where-Object { $_.Source -eq "Tools/Blueprint/$($e.File)" }
            $row | Should -Not -BeNullOrEmpty -Because "$($e.Id) changes $($e.File)"
            $row.Action | Should -Be 'Copy'
            $row.Edits | Should -Contain $e.Id
        }
    }

    It 'gives every edit a reason' {
        foreach ($e in $script:edits.Edits) { $e.Why | Should -Not -BeNullOrEmpty -Because $e.Id }
    }

    It '<Id> change <Index> matches once in <File>' -ForEach $changes {
        $text = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot "Tools/Blueprint/$File"))
        Get-OrdinalCount -Text $text -Find $Find | Should -Be 1
    }

    It 'finds one File: header to repoint in <Source>' -ForEach $headerFiles {
        $text = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot $Source))
        [regex]::Matches($text, $script:edits.HeaderPath.Pattern).Count | Should -Be 1
    }
}
