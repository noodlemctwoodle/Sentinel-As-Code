#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests that Modules/iSOCDeployments/MIGRATION.md matches the
    repository.

.DESCRIPTION
    MIGRATION.md records where every script and function the module
    replaces goes. These tests hold it to the repository in both
    directions while the module is built beside the scripts:

    - a script that is not yet removed still exists, and one marked
      Removed does not;
    - every function row names an old function the source still defines
      (while the source exists) and a destination file that defines one
      function named after it, or (not ported) with the edit that says
      why;
    - every Sentinel.Common function has a row, since that module is
      absorbed whole;
    - every edit a row names is described, and every described edit is
      named by a row;
    - an unmerged source that has been ported (named by its commit) is
      read from its byte-for-byte copy under Fixtures/legacy/, whose git
      blob id is checked, since the commit is not on any remote.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Migration-Map.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Migration-Map.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.4.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $PSScriptRoot '_helpers/Migration.psm1') -Force
    $map = Get-iSOCDeploymentsMigrationMap -RepoRoot $repoRoot
    $scriptRows = @($map.Scripts | ForEach-Object { @{ Row = $_; Source = $_.Source } })
    $functionRows = @($map.Functions | ForEach-Object { @{ Row = $_; Label = "$($_.Function) to $([System.IO.Path]::GetFileNameWithoutExtension($_.Destination))" } })
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $PSScriptRoot '_helpers/Migration.psm1') -Force
    $script:map = Get-iSOCDeploymentsMigrationMap -RepoRoot $script:repoRoot

    # The ported unmerged sources, by the git blob id of the file at
    # their commit.
    $script:frozen = @{ '847ef86:Tools/Export-Playbooks.ps1' = 'b1bf8fa848640f2a3c4bc7daa86039d60323fd4f' }

    function Resolve-SourcePath {
        param([string] $Source)
        if ($Source -match '^[0-9a-f]{7,40}:(.+)$') { return Join-Path $script:repoRoot "Tests/iSOCDeployments/Fixtures/legacy/$(Split-Path -Leaf $Matches[1])" }
        Join-Path $script:repoRoot $Source
    }

    function Get-GitBlobId {
        param([string] $Path)
        $text = [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
        $sha = [System.Security.Cryptography.SHA1]::Create()
        try { -join ($sha.ComputeHash([byte[]]($header + $bytes)) | ForEach-Object { $_.ToString('x2') }) }
        finally { $sha.Dispose() }
    }

    function Get-DefinedFunction {
        param([string] $Path)
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) | ForEach-Object Name)
    }
}

Describe 'MIGRATION.md' {
    It 'has rows in all three tables' {
        $script:map.Scripts.Count | Should -BeGreaterThan 10
        $script:map.Functions.Count | Should -BeGreaterThan 10
        $script:map.Edits.Count | Should -BeGreaterThan 0
    }

    It 'lists each script once' {
        @($script:map.Scripts.Source | Group-Object | Where-Object Count -gt 1).Name | Should -BeNullOrEmpty
    }

    It 'maps every Sentinel.Common function' {
        $source = Join-Path $script:repoRoot 'Modules/Sentinel.Common/Sentinel.Common.psm1'
        if (-not (Test-Path -LiteralPath $source)) { Set-ItResult -Skipped -Because 'Sentinel.Common has been retired'; return }
        $mapped = @($script:map.Functions | Where-Object Source -eq 'Modules/Sentinel.Common/Sentinel.Common.psm1' | ForEach-Object Function | Sort-Object -Unique)
        @(Get-DefinedFunction $source | Sort-Object) | Should -Be $mapped
    }

    It 'describes every edit a row names' {
        $described = @($script:map.Edits.Id)
        foreach ($id in @($script:map.Functions | ForEach-Object Edits | Sort-Object -Unique)) {
            $described | Should -Contain $id
        }
    }

    It 'names every edit it describes in at least one row' {
        $named = @($script:map.Functions | ForEach-Object Edits | Sort-Object -Unique)
        foreach ($id in $script:map.Edits.Id) { $named | Should -Contain $id }
    }

    It 'numbers the edits E1, E2 and on, once each' {
        $ids = @($script:map.Edits.Id)
        $ids | Should -Be @(1..$ids.Count | ForEach-Object { "E$_" })
    }

    It 'sends no function row to the same destination twice from the same old function' {
        @($script:map.Functions | Group-Object Source, Function, Destination | Where-Object Count -gt 1).Name | Should -BeNullOrEmpty
    }
}

Describe 'Script <Source>' -ForEach $scriptRows {
    It 'has a known status' {
        $Row.Status | Should -BeIn @('Planned', 'In progress', 'Ported', 'Removed', 'Unmerged')
    }

    It 'is in the repository unless removed or unmerged' {
        $exists = Test-Path -LiteralPath (Resolve-SourcePath $Row.Source)
        switch ($Row.Status) {
            'Removed' { $exists | Should -BeFalse }
            'Unmerged' { $Row.Source | Should -Match '^[0-9a-f]{7,40}:' -Because 'an unmerged source names the commit it is on' }
            default { $exists | Should -BeTrue }
        }
    }

    It 'has a row for every function once ported' {
        if ($Row.Status -ne 'Ported') { Set-ItResult -Skipped -Because "it is $($Row.Status)"; return }
        $mapped = @($script:map.Functions | Where-Object { $_.Source -eq $Row.Source -and $_.Function -ne '(script)' } | ForEach-Object Function | Sort-Object -Unique)
        @(Get-DefinedFunction (Resolve-SourcePath $Row.Source) | Sort-Object) | Should -Be $mapped
    }

    It 'is read, when ported from a commit, from a copy that is that commit''s file' {
        if ($Row.Source -notmatch '^[0-9a-f]{7,40}:' -or $Row.Status -eq 'Unmerged') { Set-ItResult -Skipped -Because 'it is not a ported unmerged source'; return }
        $script:frozen.ContainsKey($Row.Source) | Should -BeTrue -Because 'the test records the blob id of every frozen copy'
        Get-GitBlobId (Resolve-SourcePath $Row.Source) | Should -Be $script:frozen[$Row.Source]
        $atCommit = & git -C $script:repoRoot rev-parse --verify --quiet $Row.Source 2>$null
        if ($LASTEXITCODE -eq 0 -and $atCommit) { $atCommit | Should -Be $script:frozen[$Row.Source] }
    }
}

Describe 'Function row <Label>' -ForEach $functionRows {
    It 'comes from a script the Scripts table lists' {
        $owners = @($script:map.Scripts.Source)
        $owners | Where-Object { $Row.Source -eq $_ -or $Row.Source.StartsWith("$_/") } | Should -Not -BeNullOrEmpty
    }

    It 'names a function the source still defines' {
        $source = Resolve-SourcePath $Row.Source
        if (-not (Test-Path -LiteralPath $source)) { Set-ItResult -Skipped -Because 'the source has been removed'; return }
        if ($Row.Function -eq '(script)') { Set-ItResult -Skipped -Because "it maps the script's top-level code"; return }
        Get-DefinedFunction $source | Should -Contain $Row.Function
    }

    It 'goes to a file that defines one function named after it' {
        if ($Row.Destination -eq '(not ported)') {
            @($Row.Edits).Count | Should -BeGreaterThan 0 -Because 'a function left behind needs the edit that says why'
            return
        }
        $destination = Join-Path $script:repoRoot $Row.Destination
        Test-Path -LiteralPath $destination | Should -BeTrue
        @(Get-DefinedFunction $destination) | Should -Be @([System.IO.Path]::GetFileNameWithoutExtension($Row.Destination))
    }
}
