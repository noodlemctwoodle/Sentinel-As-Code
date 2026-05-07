#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Self-test for Tests/_helpers/Import-ScriptFunctions.psm1, the AST
    extractor every Phase-B test suite depends on.

.DESCRIPTION
    A regression in the helper would break every script-test suite at
    once. These tests pin the contract using a synthetic source script
    written into $TestDrive, plus one real-repo round-trip against
    Scripts/Test-SentinelRuleDrift.ps1 to confirm the helper works on
    the original reference suite's source.
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
        $script:realScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'Scripts/Test-SentinelRuleDrift.ps1'
    }

    It 'does not throw when invoked against the real script' {
        # The drift script's Invoke-Main calls Connect-AzureEnvironment,
        # which would fail without auth. If Import-ScriptFunctions runs
        # the body of the script, this assertion would fail.
        { Import-ScriptFunctions -Path $script:realScript } | Should -Not -Throw
    }

    It 'imports the drift detector functions into the caller scope' {
        # Call Import outside `Should -Not -Throw` so the functions land in
        # this It-block's scope rather than the assertion's transient
        # scriptblock scope.
        Import-ScriptFunctions -Path $script:realScript

        Get-Command Compare-SentinelRule -ErrorAction SilentlyContinue   | Should -Not -BeNullOrEmpty
        Get-Command Update-RuleYamlFile -ErrorAction SilentlyContinue    | Should -Not -BeNullOrEmpty
        Get-Command Resolve-RuleSource -ErrorAction SilentlyContinue     | Should -Not -BeNullOrEmpty
    }
}
