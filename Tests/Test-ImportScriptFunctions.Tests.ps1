#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Self-test for Tests/_helpers/Import-ScriptFunctions.psm1, the AST
    extractor every Phase-B test suite depends on.

.DESCRIPTION
    A regression in the helper would break every script-test suite at
    once. These tests pin the contract using a synthetic source script
    written into $TestDrive, plus one real-repo round-trip against
    Tools/Test-PullRequestTemplate.ps1 to confirm the helper works on a
    script whose body exits.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-ImportScriptFunctions.Tests.ps1

    Runs the AST-extractor self-test. Run this first when several script
    test suites fail at once, since the helper is their common dependency.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-ImportScriptFunctions.Tests.ps1 -Output Detailed

    Runs with per-assertion output, for diagnosing an extraction failure.

.NOTES
    File:         Tests/Test-ImportScriptFunctions.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-13
    Version:      0.1.2
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeAll {
    $helperPath = Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1'
    Import-Module $helperPath -Force -ErrorAction Stop
}

Describe 'Import-ScriptFunctions: synthetic source' {
    BeforeAll {
        # Build a fake script with a function, a param block, a #Requires
        # directive, and a top-level Main call that would throw if invoked.
        # If the helper accidentally executes any of those, the test fails.
        $script:fakeScript = Join-Path $TestDrive 'fake-script.ps1'
        $fakeContent = @'
#Requires -Modules NonExistentModuleThatWouldFailIfRequired

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$WouldExplodeIfBound
)

function Add-Two {
    param([int]$x, [int]$y)
    return $x + $y
}

function ConvertTo-Upper {
    param([string]$value)
    return $value.ToUpper()
}

# Top-level call that would explode if the script were dot-sourced normally.
throw "If you see this, Import-ScriptFunctions executed top-level code."
'@
        Set-Content -Path $script:fakeScript -Value $fakeContent -Encoding UTF8
    }

    It 'imports declared functions into the caller scope without running param/#Requires/top-level code' {
        Import-ScriptFunctions -Path $script:fakeScript
        # If the throw line ran, we never reach this assertion.
        Get-Command Add-Two -ErrorAction SilentlyContinue        | Should -Not -BeNullOrEmpty
        Get-Command ConvertTo-Upper -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'extracted functions execute correctly' {
        Import-ScriptFunctions -Path $script:fakeScript
        Add-Two -x 2 -y 3        | Should -Be 5
        ConvertTo-Upper -value 'a' | Should -Be 'A'
    }

    It 'throws a clear error when the path does not exist' {
        { Import-ScriptFunctions -Path (Join-Path $TestDrive 'nope.ps1') } |
            Should -Throw -ExpectedMessage '*file not found*'
    }

    It 'throws a clear error when the script has parser errors' {
        $broken = Join-Path $TestDrive 'broken.ps1'
        Set-Content -Path $broken -Value 'function Bad { param('   # unclosed param block
        { Import-ScriptFunctions -Path $broken } | Should -Throw -ExpectedMessage '*parser errors*'
    }
}

Describe 'Import-ScriptFunctions: real repo round-trip' {
    BeforeAll {
        $script:realScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools/Test-PullRequestTemplate.ps1'
    }

    It 'does not throw when invoked against the real script' {
        # The script's body validates a PR description and exits. If
        # Import-ScriptFunctions ran the body, this assertion would fail.
        { Import-ScriptFunctions -Path $script:realScript } | Should -Not -Throw
    }

    It 'imports the script''s functions into the caller scope' {
        # Call Import outside `Should -Not -Throw` so the functions land in
        # this It-block's scope rather than the assertion's transient
        # scriptblock scope.
        Import-ScriptFunctions -Path $script:realScript

        Get-Command Remove-MarkdownComment -ErrorAction SilentlyContinue      | Should -Not -BeNullOrEmpty
        Get-Command Get-PullRequestSection -ErrorAction SilentlyContinue      | Should -Not -BeNullOrEmpty
        Get-Command Test-PullRequestTemplateBody -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}
