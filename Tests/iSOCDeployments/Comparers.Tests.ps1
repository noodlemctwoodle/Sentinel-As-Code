#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the comparers a content type's field list names, the
    canonical JSON they rest on and the duration canonicaliser.

.DESCRIPTION
    Compare-iSOCFieldValue decides drift for every field of every content
    type, so each comparer is held to what it promises: what counts as
    equal, what does not, and that an unset value on both sides is equal.
    ConvertTo-iSOCCanonicalDuration is held to explicit spellings; it was
    copied from ConvertTo-NormalisedDuration in
    Tools/Test-SentinelRuleDrift.ps1, and parity with that script was
    proven on release/26.11.0 before it was removed.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Comparers.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Comparers.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force

    function Test-Field {
        param([string] $Comparer, $Expected, $Actual)
        InModuleScope iSOCDeployments -Parameters @{ C = $Comparer; E = $Expected; A = $Actual } { param($C, $E, $A) Compare-iSOCFieldValue -Comparer $C -Expected $E -Actual $A }
    }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Compare-iSOCFieldValue' {
    It '<Comparer> finds <Expected> and <Actual> equal' -ForEach @(
        @{ Comparer = 'Exact'; Expected = 'Rule'; Actual = 'Rule' }
        @{ Comparer = 'Exact'; Expected = $true; Actual = $true }
        @{ Comparer = 'CaseInsensitive'; Expected = 'high'; Actual = 'High' }
        @{ Comparer = 'Whitespace'; Expected = "SigninLogs`n| take 1"; Actual = '  SigninLogs   | take 1 ' }
        @{ Comparer = 'Number'; Expected = 5; Actual = '5.0' }
        @{ Comparer = 'Duration'; Expected = 'PT24H'; Actual = 'P1D' }
        @{ Comparer = 'Duration'; Expected = 'pt1h'; Actual = 'PT60M' }
        @{ Comparer = 'Set'; Expected = @('a', 'b'); Actual = @('b', 'a', 'a') }
        @{ Comparer = 'OrderedList'; Expected = @('a', 'b'); Actual = @('a', 'b') }
        @{ Comparer = 'Ignore'; Expected = 'x'; Actual = 'y' }
    ) {
        Test-Field $Comparer $Expected $Actual | Should -BeTrue
    }

    It '<Comparer> finds <Expected> and <Actual> different' -ForEach @(
        @{ Comparer = 'Exact'; Expected = 'Rule'; Actual = 'rule' }
        @{ Comparer = 'CaseInsensitive'; Expected = 'high'; Actual = 'Medium' }
        @{ Comparer = 'Whitespace'; Expected = "where x == 'Admin'"; Actual = "where x == 'admin'" }
        @{ Comparer = 'Number'; Expected = 5; Actual = 6 }
        @{ Comparer = 'Duration'; Expected = 'PT1H'; Actual = 'PT2H' }
        @{ Comparer = 'Set'; Expected = @('a', 'b'); Actual = @('a', 'c') }
        @{ Comparer = 'Set'; Expected = @('A'); Actual = @('a') }
        @{ Comparer = 'OrderedList'; Expected = @('a', 'b'); Actual = @('b', 'a') }
    ) {
        Test-Field $Comparer $Expected $Actual | Should -BeFalse
    }

    It 'Json compares structure with keys in any order' {
        $repo = @{ b = @{ y = 2; x = 1 }; a = @(1, 2) }
        $workspace = [pscustomobject]@{ a = @(1, 2); b = [pscustomobject]@{ x = 1; y = 2 } }
        Test-Field Json $repo $workspace | Should -BeTrue
        Test-Field Json $repo ([pscustomobject]@{ a = @(2, 1); b = [pscustomobject]@{ x = 1; y = 2 } }) | Should -BeFalse
    }

    It '<Comparer> treats missing, empty text, an empty list and an empty mapping as the same unset value' -ForEach @(
        @{ Comparer = 'Exact' }, @{ Comparer = 'Whitespace' }, @{ Comparer = 'Number' }, @{ Comparer = 'Duration' }, @{ Comparer = 'Set' }, @{ Comparer = 'Json' }
    ) {
        Test-Field $Comparer $null '' | Should -BeTrue
        Test-Field $Comparer @() $null | Should -BeTrue
        Test-Field $Comparer @{} ([pscustomobject]@{}) | Should -BeTrue
        Test-Field $Comparer $null 'value' | Should -BeFalse
        Test-Field $Comparer 'value' @() | Should -BeFalse
    }

    It 'rejects an unknown comparer' {
        { Test-Field 'Fuzzy' 'a' 'a' } | Should -Throw
    }
}

Describe 'ConvertTo-iSOCCanonicalJson' {
    It 'sorts keys at every depth and keeps list order' {
        InModuleScope iSOCDeployments { ConvertTo-iSOCCanonicalJson @{ b = @(1, @(2, 3), $null, @{ z = 1; a = @() }); a = 'x' } } |
            Should -BeExactly '{"a":"x","b":[1,[2,3],null,{"a":[],"z":1}]}'
    }

    It 'writes a dictionary and an object with the same members the same way' {
        $fromYaml = InModuleScope iSOCDeployments { ConvertTo-iSOCCanonicalJson ([ordered]@{ kind = 'NRT'; properties = [ordered]@{ severity = 'High'; enabled = $true } }) }
        $fromApi = InModuleScope iSOCDeployments { ConvertTo-iSOCCanonicalJson ('{"properties":{"enabled":true,"severity":"High"},"kind":"NRT"}' | ConvertFrom-Json) }
        $fromYaml | Should -BeExactly $fromApi
    }

    It 'keeps a one-member list a list' {
        InModuleScope iSOCDeployments { ConvertTo-iSOCCanonicalJson @{ tactics = @('Execution') } } | Should -BeExactly '{"tactics":["Execution"]}'
    }
}

Describe 'ConvertTo-iSOCCanonicalDuration' {
    It 'writes <Value> as <Expected>' -ForEach @(
        @{ Value = 'PT24H'; Expected = 'P1D' }
        @{ Value = 'P1D'; Expected = 'P1D' }
        @{ Value = 'PT5M'; Expected = 'PT5M' }
        @{ Value = 'PT90M'; Expected = 'PT1H30M' }
        @{ Value = 'pt1h'; Expected = 'PT1H' }
        @{ Value = ' PT1H '; Expected = 'PT1H' }
        @{ Value = '5h'; Expected = '5h' }
    ) {
        $new = InModuleScope iSOCDeployments -Parameters @{ V = $Value } { param($V) ConvertTo-iSOCCanonicalDuration $V }
        $new | Should -BeExactly $Expected
    }

    It 'returns nothing for an empty value' {
        InModuleScope iSOCDeployments { ConvertTo-iSOCCanonicalDuration '' } | Should -BeNullOrEmpty
        InModuleScope iSOCDeployments { ConvertTo-iSOCCanonicalDuration $null } | Should -BeNullOrEmpty
    }
}
