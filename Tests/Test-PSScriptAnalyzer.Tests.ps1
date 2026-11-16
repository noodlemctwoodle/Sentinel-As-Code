#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 repository lint: every PowerShell file goes through
    PSScriptAnalyzer with the profiles in Tests/PSScriptAnalyzer.

.DESCRIPTION
    One test per .ps1, .psm1 and .psd1 in the repository (files git ignores
    are skipped). Source files use PSScriptAnalyzerSettings.psd1, files under
    Tests/ use PSScriptAnalyzerTestSettings.psd1, and every file also gets the
    PSScriptAnalyzerFormatting.psd1 pass (see Tests/_helpers/PSScriptAnalyzerLint.psm1).

    The gate is a ratchet. Tests/PSScriptAnalyzer/PSScriptAnalyzerBaseline.psd1
    records how many findings each existing file had when the lint was
    introduced. A file may not have more findings than its baseline (a file
    not listed, including every new file, must be clean), and when a file
    improves the test fails until the baseline is lowered with
    ./Tools/Update-PSScriptAnalyzerBaseline.ps1, so the improvement is kept.

    Skipped only on a workstation without PSScriptAnalyzer. In CI (Azure
    DevOps or GitHub Actions) a missing analyser fails every test, and any
    analyser error fails the file's test.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-PSScriptAnalyzer.Tests.ps1

    Lints every PowerShell file in the repository.

.NOTES
    File:         Tests/Test-PSScriptAnalyzer.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.2+, Pester 5+, PSScriptAnalyzer 1.25.0
#>

BeforeDiscovery {
    $repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '_helpers/PSScriptAnalyzerLint.psm1') -Force
    $script:lintFiles = @(Get-RepositoryPowerShellFile -RepositoryRoot $repositoryRoot | ForEach-Object -Process {
            @{ Path = $_.Path; FullName = $_.FullName; Settings = $_.Settings }
        })
    $script:hasAnalyzer = [bool](Get-Module -ListAvailable -Name 'PSScriptAnalyzer')
    $script:inCi = [bool]($env:TF_BUILD -or $env:GITHUB_ACTIONS)
}

BeforeAll {
    $script:repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '_helpers/PSScriptAnalyzerLint.psm1') -Force
    $script:baseline = Import-PowerShellDataFile -Path (Join-Path -Path $PSScriptRoot -ChildPath 'PSScriptAnalyzer/PSScriptAnalyzerBaseline.psd1')
    if (Get-Module -ListAvailable -Name 'PSScriptAnalyzer') {
        Initialize-RepositoryLint -RepositoryRoot $script:repositoryRoot
    }
}

Describe 'PSScriptAnalyzer repository lint' {
    It 'has no more findings than its baseline allows: <Path>' -ForEach $script:lintFiles -Skip:(-not $script:hasAnalyzer -and -not $script:inCi) {
        if (-not (Get-Module -ListAvailable -Name 'PSScriptAnalyzer')) {
            throw 'PSScriptAnalyzer is not installed on this CI agent; the PR pipelines install it (PSSA_VERSION).'
        }
        $file = [pscustomobject]@{ Path = $Path; FullName = $FullName; Settings = $Settings }
        $findings = @(Invoke-RepositoryLint -File $file -RepositoryRoot $script:repositoryRoot)
        $allowed = if ($script:baseline.ContainsKey($Path)) { [int]$script:baseline[$Path] } else { 0 }

        if ($findings.Count -gt $allowed) {
            $detail = ($findings | Select-Object -First 20 | ForEach-Object -Process { "line $($_.Line) $($_.RuleName): $($_.Message)" }) -join "`n"
            throw "$Path has $($findings.Count) PSScriptAnalyzer findings; $allowed allowed. Fix the new ones (first 20):`n$detail"
        }
        if ($findings.Count -lt $allowed) {
            throw "$Path improved to $($findings.Count) findings from a baseline of $allowed. Lower the baseline to keep the gain: ./Tools/Update-PSScriptAnalyzerBaseline.ps1"
        }
    }

    It 'runs the PSScriptAnalyzer version the baseline was generated with' -Skip:(-not $script:inCi) {
        # Counts differ between analyser versions, so CI must lint with the
        # pinned one; locally another version only produces a warning.
        (Get-Module -Name 'PSScriptAnalyzer').Version | Should -Be (Get-RepositoryLintVersion)
    }

    It 'lists only files that still exist in the baseline' {
        $existing = @(Get-RepositoryPowerShellFile -RepositoryRoot $script:repositoryRoot | ForEach-Object -Process { $_.Path })
        $stale = @($script:baseline.Keys | Where-Object -FilterScript { $existing -notcontains $_ })
        $stale -join "`n" | Should -BeNullOrEmpty -Because 'entries for removed files should be deleted with ./Tools/Update-PSScriptAnalyzerBaseline.ps1'
    }
}
