#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the dependency manifest commands and the code behind
    them.

.DESCRIPTION
    This repository first: the manifest the module builds for it must show
    no drift and be byte for byte the committed dependencies.json; and the
    comparison and serialisation must report and write explicit diff lines
    and JSON. Then the fixture repository: the inventory, the entries and
    missing watchlists, and the commands on a copy of it
    (Update-iSOCDependencyManifest writing, not rewriting an unchanged
    file, honouring -WhatIf; Test-iSOCDependencyManifest finding drift;
    Get-iSOCContentDependency on single files and from the pipeline).
    Parity with Tools/Build-DependencyManifest.ps1 was proven on
    release/26.11.0 before it was removed.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Manifest.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Manifest.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+, powershell-yaml
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'

    function New-FixtureCopy {
        $copy = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $copy | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:fixtureRepo 'Content') -Destination $copy -Recurse
        $copy
    }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'The manifest of this repository, its JSON and its comparison' {
    It 'builds this repository''s committed dependencies.json byte for byte, with no drift' {
        $state = InModuleScope iSOCDeployments -Parameters @{ R = $script:repoRoot } { param($R) Get-iSOCDependencyManifestState -RepoPath $R 6>$null 3>$null }
        $expected = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot 'dependencies.json'))
        ($state.Json.Replace("`r`n", "`n").TrimEnd("`n") + "`n") | Should -BeExactly $expected
        $state.HasDrift | Should -BeFalse
    }

    It 'writes the entries under version, description and dependencies, indented' {
        $entries = [ordered]@{ 'Content/A.yaml' = [ordered]@{ tables = @('T1', 'T2') }; 'Content/B.yaml' = [ordered]@{ watchlists = @('w') } }
        $new = InModuleScope iSOCDeployments -Parameters @{ E = $entries } { param($E) ConvertTo-iSOCManifestJson -Entries $E -Version '1.0' -Description 'd' }
        $expected = @(
            '{'
            '  "version": "1.0",'
            '  "description": "d",'
            '  "dependencies": {'
            '    "Content/A.yaml": {'
            '      "tables": ['
            '        "T1",'
            '        "T2"'
            '      ]'
            '    },'
            '    "Content/B.yaml": {'
            '      "watchlists": ['
            '        "w"'
            '      ]'
            '    }'
            '  }'
            '}'
        ) -join "`n"
        $new.Replace("`r`n", "`n") | Should -BeExactly $expected
    }

    It 'reports <Case>' -ForEach @(
        @{ Case = 'no change'; Disk = @{ 'a' = @{ tables = @('T') } }; Found = @{ 'a' = @{ tables = @('T') } }; HasDrift = $false; Diff = @() }
        @{ Case = 'an added entry'; Disk = @{}; Found = @{ 'a' = @{ tables = @('T') } }; HasDrift = $true; Diff = @('ADDED:    a') }
        @{ Case = 'a removed entry'; Disk = @{ 'a' = @{ tables = @('T') } }; Found = @{}; HasDrift = $true; Diff = @('REMOVED:  a') }
        @{
            Case = 'a changed bucket'; Disk = @{ 'a' = @{ tables = @('T'); functions = @('F') } }; Found = @{ 'a' = @{ tables = @('T', 'U') } }; HasDrift = $true
            Diff = @('CHANGED:  a', '    tables :  on-disk=[T]  discovered=[T,U]', '    functions :  on-disk=[F]  discovered=[]')
        }
        @{ Case = 'members in another order'; Disk = @{ 'a' = @{ tables = @('U', 'T') } }; Found = @{ 'a' = @{ tables = @('T', 'U') } }; HasDrift = $false; Diff = @() }
    ) {
        $new = InModuleScope iSOCDeployments -Parameters @{ F = $Found; D = $Disk } { param($F, $D) Compare-iSOCDependencyManifest -Discovered $F -OnDisk $D }
        $new.HasDrift | Should -Be $HasDrift
        @($new.Diff).Count | Should -Be $Diff.Count
        if ($Diff.Count) { @($new.Diff) | Should -BeExactly $Diff }
    }
}

Describe 'Inventory and entries on the fixture repository' {
    BeforeAll {
        $script:inventory = InModuleScope iSOCDeployments -Parameters @{ R = $script:fixtureRepo } { param($R) Get-iSOCDependencyInventory -RepoPath $R }
        $script:manifest = InModuleScope iSOCDeployments -Parameters @{ R = $script:fixtureRepo; I = $script:inventory } { param($R, $I) New-iSOCDependencyManifest -RepoPath $R -Inventory $I }
    }

    It 'knows the parser functions, leaving out a parser without an alias' {
        $script:inventory.Functions.Keys | Should -Be @('FixtureSignIns')
        $script:inventory.Functions['fixturesignins'] | Should -Be 'Content/Parsers/Identity/FixtureSignInParser.yaml'
    }

    It 'knows the watchlists that have a watchlist.json' {
        @($script:inventory.Watchlists.Keys | Sort-Object) | Should -Be @('noData', 'vipUsers')
    }

    It 'lists every item with a dependency, in path order, and nothing else' {
        @($script:manifest.Entries.Keys) | Should -Be @(
            'Content/AnalyticalRules/Community/CommunityRule.yml'
            'Content/AnalyticalRules/Identity/NrtRule.yaml'
            'Content/AnalyticalRules/Identity/ScheduledRule.yaml'
            'Content/AnalyticalRules/MissingFields.yaml'
            'Content/HuntingQueries/SigninLogs/FixtureHunt.yaml'
        )
    }

    It 'files a parser call under functions and watchlist reads under watchlists' {
        $entry = $script:manifest.Entries['Content/HuntingQueries/SigninLogs/FixtureHunt.yaml']
        @($entry.Keys) | Should -Be @('watchlists', 'functions')
        $entry.functions | Should -Be @('FixtureSignIns')
        $entry.watchlists | Should -Be @('notInRepo', 'vipUsers')
    }

    It 'gives a one-table entry a list, not a bare value' {
        , $script:manifest.Entries['Content/AnalyticalRules/Identity/NrtRule.yaml'].tables | Should -BeOfType [object[]]
    }

    It 'records the watchlists the repository does not have, with what reads them' {
        @($script:manifest.MissingWatchlists.Keys) | Should -Be @('notInRepo')
        $script:manifest.MissingWatchlists['notInRepo'] | Should -Be @('Content/HuntingQueries/SigninLogs/FixtureHunt.yaml')
    }
}

Describe 'Update-iSOCDependencyManifest and Test-iSOCDependencyManifest' {
    BeforeEach {
        $script:copy = New-FixtureCopy
        $script:manifestPath = Join-Path $script:copy 'dependencies.json'
    }

    It 'reports a missing manifest as drift, naming the command that writes it' {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        $result = Test-iSOCDependencyManifest -RepoPath $script:copy
        $result.PSObject.TypeNames | Should -Contain 'iSOCDeployments.ManifestResult'
        $result.Exists | Should -BeFalse
        $result.HasDrift | Should -BeTrue
        $result.Changed | Should -BeFalse
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Level -eq 'Error' -and $Message -match 'Run Update-iSOCDependencyManifest' }
        Test-Path -LiteralPath $script:manifestPath | Should -BeFalse
    }

    It 'writes the manifest as UTF-8 without a BOM, with LF line endings and one final newline' {
        $result = Update-iSOCDependencyManifest -RepoPath $script:copy 6>$null 3>$null
        $result.Changed | Should -BeTrue
        $result.Entries | Should -Be 5
        $bytes = [System.IO.File]::ReadAllBytes($script:manifestPath)
        $bytes[0..2] | Should -Not -Be @(0xEF, 0xBB, 0xBF)
        $text = [System.IO.File]::ReadAllText($script:manifestPath)
        $text | Should -Not -Match "`r"
        $text | Should -Match "\}`n$"
        $text | Should -Not -Match "`n`n$"
        ($text | ConvertFrom-Json).dependencies.'Content/HuntingQueries/SigninLogs/FixtureHunt.yaml'.functions | Should -Be @('FixtureSignIns')
    }

    It 'leaves an up-to-date manifest alone' {
        Update-iSOCDependencyManifest -RepoPath $script:copy 6>$null 3>$null | Out-Null
        $before = (Get-Item -LiteralPath $script:manifestPath).LastWriteTimeUtc
        Start-Sleep -Milliseconds 20
        $second = Update-iSOCDependencyManifest -RepoPath $script:copy 6>$null 3>$null
        $second.Changed | Should -BeFalse
        $second.HasDrift | Should -BeFalse
        (Get-Item -LiteralPath $script:manifestPath).LastWriteTimeUtc | Should -Be $before
        (Test-iSOCDependencyManifest -RepoPath $script:copy 6>$null 3>$null).HasDrift | Should -BeFalse
    }

    It 'finds drift when content changes, and writes the fix' {
        Update-iSOCDependencyManifest -RepoPath $script:copy 6>$null 3>$null | Out-Null
        $rule = Join-Path $script:copy 'Content/AnalyticalRules/Identity/NrtRule.yaml'
        (Get-Content -LiteralPath $rule -Raw).Replace('  AuditLogs', '  SecurityAlert') | Set-Content -LiteralPath $rule -NoNewline

        $check = Test-iSOCDependencyManifest -RepoPath $script:copy 6>$null 3>$null 2>$null
        $check.HasDrift | Should -BeTrue
        $check.Diff | Should -Contain 'CHANGED:  Content/AnalyticalRules/Identity/NrtRule.yaml'
        $check.Diff | Should -Contain '    tables :  on-disk=[AuditLogs]  discovered=[SecurityAlert]'

        (Update-iSOCDependencyManifest -RepoPath $script:copy 6>$null 3>$null).Changed | Should -BeTrue
        (Test-iSOCDependencyManifest -RepoPath $script:copy 6>$null 3>$null).HasDrift | Should -BeFalse
    }

    It 'writes nothing with -WhatIf' {
        $result = Update-iSOCDependencyManifest -RepoPath $script:copy -WhatIf 6>$null 3>$null
        $result.Changed | Should -BeFalse
        $result.HasDrift | Should -BeTrue
        Test-Path -LiteralPath $script:manifestPath | Should -BeFalse
    }

    It 'writes to another path with -ManifestPath, and reports it repository-relative' {
        $result = Update-iSOCDependencyManifest -RepoPath $script:copy -ManifestPath (Join-Path $script:copy 'out/deps.json') 6>$null 3>$null
        $result.ManifestPath | Should -Be 'out/deps.json'
        Test-Path -LiteralPath (Join-Path $script:copy 'out/deps.json') | Should -BeTrue
    }

    It 'warns about the watchlists the repository does not have' {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Test-iSOCDependencyManifest -RepoPath $script:copy | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Level -eq 'Warning' -and $Message -match 'notInRepo, used by: Content/HuntingQueries/SigninLogs/FixtureHunt.yaml' }
    }
}

Describe 'Get-iSOCContentDependency' {
    It 'lists what a file reads, with the repository''s parsers as functions' {
        $deps = Get-iSOCContentDependency -Path (Join-Path $script:fixtureRepo 'Content/HuntingQueries/SigninLogs/FixtureHunt.yaml') -RepoPath $script:fixtureRepo
        $deps.PSObject.TypeNames | Should -Contain 'iSOCDeployments.ContentDependency'
        $deps.Path | Should -Be 'Content/HuntingQueries/SigninLogs/FixtureHunt.yaml'
        $deps.Functions | Should -Be @('FixtureSignIns')
        $deps.Watchlists | Should -Be @('notInRepo', 'vipUsers')
        @($deps.Tables).Count | Should -Be 0
    }

    It 'gives empty lists, not a null member, for a file without a query' {
        $deps = Get-iSOCContentDependency -Path (Join-Path $script:fixtureRepo 'Content/HuntingQueries/SigninLogs/NoQuery.yaml') -RepoPath $script:fixtureRepo
        foreach ($bucket in 'Tables', 'Watchlists', 'Functions', 'ExternalData') { $deps.$bucket.Count | Should -Be 0 }
    }

    It 'takes files from the pipeline' {
        $all = @(Get-ChildItem -LiteralPath (Join-Path $script:fixtureRepo 'Content/AnalyticalRules/Identity') -File | Get-iSOCContentDependency -RepoPath $script:fixtureRepo)
        @($all.Path) | Should -Be @('Content/AnalyticalRules/Identity/NrtRule.yaml', 'Content/AnalyticalRules/Identity/ScheduledRule.yaml')
        $all[0].Tables | Should -Be @('AuditLogs')
    }

    It 'says when a file is not there' {
        { Get-iSOCContentDependency -Path (Join-Path $script:fixtureRepo 'Content/Nope.yaml') -RepoPath $script:fixtureRepo } | Should -Throw -ExpectedMessage '*was not found*'
    }
}
