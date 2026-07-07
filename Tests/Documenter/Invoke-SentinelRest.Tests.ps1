#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for the URL construction inside Invoke-SentinelRest.

.DESCRIPTION
    The collector cannot run end-to-end without Azure auth, but URL
    construction is the single most failure-prone bit of the helper and the
    one that bit us in production: a stray backtick before 'a' was being
    parsed as the bell-character escape and Azure rejected every call with
    'MissingApiVersionParameter'. This test asserts the constructed URL
    contains a literal '?api-version=' or '&api-version=' (no control chars,
    no escape interpretation) and that the api-version is appended exactly
    once.

    To exercise the build logic without going to Azure we mock
    Invoke-AzRestMethod and capture the URL the helper would have sent.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'Tools/Documenter/Private/Invoke-SentinelRest.ps1')
}

Describe 'Invoke-SentinelRest URL construction' {

    BeforeEach {
        $script:capturedUrl = $null
        Mock -CommandName Invoke-AzRestMethod -MockWith {
            $script:capturedUrl = $Path
            [pscustomobject]@{ StatusCode = 200; Content = '{"value":[]}' }
        }
    }

    It 'appends ?api-version=<value> to a path with no query string' {
        Invoke-SentinelRest -Path '/subscriptions/abc/resourceGroups/rg' -ApiVersion '2025-02-01' | Out-Null
        $script:capturedUrl | Should -Be '/subscriptions/abc/resourceGroups/rg?api-version=2025-02-01'
    }

    It 'appends &api-version=<value> when the path already has a query string' {
        Invoke-SentinelRest -Path '/subscriptions/abc?$filter=foo' -ApiVersion '2025-02-01' | Out-Null
        $script:capturedUrl | Should -Be '/subscriptions/abc?$filter=foo&api-version=2025-02-01'
    }

    It 'does not double-append api-version if the path already contains it' {
        Invoke-SentinelRest -Path '/subscriptions/abc?api-version=2024-01-01' -ApiVersion '2025-02-01' | Out-Null
        $script:capturedUrl | Should -Be '/subscriptions/abc?api-version=2024-01-01'
    }

    It 'never produces a control character in the URL' {
        Invoke-SentinelRest -Path '/subscriptions/abc' -ApiVersion '2025-02-01' | Out-Null
        # Reject anything in the C0 control range — this is the regression
        # check for the `a → bell-character (0x07) bug that bit us in
        # production. Tab, LF, CR, and the bell character must NOT appear.
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($script:capturedUrl)
        $bytes | Where-Object { $_ -lt 32 } | Should -BeNullOrEmpty
    }

    It 'omits api-version entirely when caller passes nothing' {
        Invoke-SentinelRest -Path '/some/path' | Out-Null
        $script:capturedUrl | Should -Be '/some/path'
    }
}
