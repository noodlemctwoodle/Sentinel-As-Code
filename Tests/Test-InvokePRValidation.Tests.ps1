#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 tests for Tools/Invoke-PRValidation.ps1: the gate fails on every
    kind of Pester failure, not only a failed test.

.DESCRIPTION
    Pester counts three kinds of failure apart. A suite whose BeforeDiscovery
    or top-level code throws, or that does not parse, is a failed container:
    its tests are never discovered, so FailedCount stays 0. A failed AfterAll
    is a failed block, and the tests in it still pass. The gate read
    FailedCount alone, so a suite that could not load was skipped and the PR
    check passed.

    Each test writes a small repository under TestDrive with its own Tests/
    folder and runs the real script against it in a child PowerShell
    process, with -InstallModules:$false, so the gate's own exit code and
    output are what is checked, and the run never reaches this repository's
    Tests/ (which would run this suite again).

.EXAMPLE
    Invoke-Pester -Path Tests/Test-InvokePRValidation.Tests.ps1

    Runs the gate against each throwaway repository.

.NOTES
    File:         Tests/Test-InvokePRValidation.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+, powershell-yaml
#>

BeforeAll {
    $script:gate = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools/Invoke-PRValidation.ps1'
    $script:pwsh = (Get-Process -Id $PID).Path

    $script:suites = @{
        Passing    = "Describe 'passing' { It 'passes' { 1 | Should -Be 1 } }"
        Failing    = "Describe 'failing' { It 'fails' { 1 | Should -Be 2 } }"
        Discovery  = "BeforeDiscovery { throw 'discovery broke' }`nDescribe 'never discovered' { It 'never runs' { 1 | Should -Be 1 } }"
        Unparsable = "Describe 'unparsable' {`n    It 'never runs' { 1 | Should -Be 1"
        AfterAll   = "Describe 'teardown' {`n    AfterAll { throw 'teardown broke' }`n    It 'passes' { 1 | Should -Be 1 }`n}"
    }

    # Run the gate over a repository holding the named suites.
    function Invoke-Gate {
        <#
        .SYNOPSIS
            Runs the PR validation script against a throwaway repository holding the named test suites.
        .PARAMETER Suite
            Names of the suites to write into the temporary repository.
        #>
        param([string[]] $Suite)
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $repo 'Tests') -Force | Out-Null
        foreach ($name in $Suite) {
            Set-Content -LiteralPath (Join-Path $repo "Tests/$name.Tests.ps1") -Value $script:suites[$name]
        }
        $results = Join-Path $repo 'test-results/pester-results.xml'
        $output = & $script:pwsh -NoProfile -NonInteractive -File $script:gate -RepoPath $repo -TestResultsPath $results -InstallModules:$false 2>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output; Results = $results }
    }
}

Describe 'Invoke-PRValidation.ps1' {
    It 'passes when every suite passes' {
        $run = Invoke-Gate -Suite Passing
        $run.ExitCode | Should -Be 0
        $run.Output | Should -BeLike '*All Pester tests passed.*'
        $run.Output | Should -BeLike '*Suites that could not be loaded: 0*'
    }

    It 'fails, naming the test, when a test fails' {
        $run = Invoke-Gate -Suite Passing, Failing
        $run.ExitCode | Should -Be 1
        $run.Output | Should -BeLike '*##`[error`]One or more Pester tests failed.*'
        $run.Output | Should -BeLike '*##`[error`]  failing.fails*'
    }

    It 'fails, naming the file and the error, when a suite''s discovery throws' {
        $run = Invoke-Gate -Suite Passing, Discovery
        $run.ExitCode | Should -Be 1
        $run.Output | Should -BeLike '*Suites that could not be loaded: 1*'
        $run.Output | Should -BeLike '*##`[error`]One or more Pester suites could not be loaded, so none of their tests ran.*'
        $run.Output | Should -BeLike '*##`[error`]  *Discovery.Tests.ps1*'
        $run.Output | Should -BeLike '*##`[error`]    *discovery broke*'
        $run.Output | Should -Not -BeLike '*All Pester tests passed.*'
    }

    It 'fails when a suite does not parse' {
        $run = Invoke-Gate -Suite Passing, Unparsable
        $run.ExitCode | Should -Be 1
        $run.Output | Should -BeLike '*##`[error`]  *Unparsable.Tests.ps1*'
        $run.Output | Should -BeLike '*Missing closing*'
    }

    It 'fails, naming the block, when an AfterAll throws though its tests pass' {
        $run = Invoke-Gate -Suite Passing, AfterAll
        $run.ExitCode | Should -Be 1
        $run.Output | Should -BeLike '*Failed setup or teardown blocks: 1*'
        $run.Output | Should -BeLike '*##`[error`]One or more BeforeAll or AfterAll blocks failed.*'
        $run.Output | Should -BeLike '*##`[error`]  teardown (*AfterAll.Tests.ps1)*'
        $run.Output | Should -BeLike '*teardown broke*'
    }

    It 'writes the test report even when it fails' {
        $run = Invoke-Gate -Suite Discovery
        $run.ExitCode | Should -Be 1
        Test-Path -LiteralPath $run.Results | Should -BeTrue
    }
}
