#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the access token age check in the SharePoint publisher.

.DESCRIPTION
    An -AccessToken cannot be refreshed, so Invoke-iSOCBlueprintSitePublish stops
    before a stage once the token has been in use for -TokenLifetimeMinutes.
    These tests drive Assert-TokenFresh with the script variables the publish
    sets (the parameter set, the limit and the time it connected) and check
    that the entry point sets them. The check once never fired, because the
    function read its own parameter set instead of the publish's.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Publish-TokenFresh.Tests.ps1

    Runs the token age check tests.

.NOTES
    File:         Tests/iSOCBlueprint/Publish-TokenFresh.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.1
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:publishRoot = Join-Path $repoRoot 'Modules/iSOCBlueprint/Private/Publish'
    . (Join-Path $script:publishRoot 'Helpers/Assert-TokenFresh.ps1')
}

Describe 'Assert-TokenFresh' {
    BeforeEach {
        $script:PublishParameterSet = 'Token'
        $script:PublishTokenLifetimeMinutes = 50
        $script:ConnectedAt = (Get-Date).AddMinutes(-10)
    }

    It 'lets a stage start while the token is within its lifetime' {
        { Assert-TokenFresh -Step 'assets' } | Should -Not -Throw
    }

    It 'stops a stage once the token has been in use past the limit, naming the stage and the age' {
        $script:ConnectedAt = (Get-Date).AddMinutes(-61)
        { Assert-TokenFresh -Step 'assets' } | Should -Throw -ExpectedMessage "Stopping before 'assets': the access token has been in use for 61 minutes (limit 50)*"
    }

    It 'uses the limit it was given' {
        $script:PublishTokenLifetimeMinutes = 5
        { Assert-TokenFresh -Step 'pages' } | Should -Throw -ExpectedMessage "Stopping before 'pages'*"
        $script:PublishTokenLifetimeMinutes = 90
        { Assert-TokenFresh -Step 'pages' } | Should -Not -Throw
    }

    It 'does not check an interactive sign-in, which refreshes itself' {
        $script:PublishParameterSet = 'Interactive'
        $script:ConnectedAt = (Get-Date).AddHours(-5)
        { Assert-TokenFresh -Step 'assets' } | Should -Not -Throw
    }

    It 'does nothing before the publish has connected' {
        $script:ConnectedAt = $null
        { Assert-TokenFresh -Step 'assets' } | Should -Not -Throw
    }
}

Describe 'The publish sets what the token check reads' {
    BeforeAll {
        $script:entry = Get-Content -LiteralPath (Join-Path $script:publishRoot 'Invoke-iSOCBlueprintSitePublish.ps1') -Raw
        $script:connect = Get-Content -LiteralPath (Join-Path $script:publishRoot 'Steps/Connect-PublishSite.ps1') -Raw
    }

    It 'records the parameter set and the limit in the entry point' {
        $script:entry | Should -Match '\$script:PublishParameterSet = \$PSCmdlet\.ParameterSetName'
        $script:entry | Should -Match '\$script:PublishTokenLifetimeMinutes = \$TokenLifetimeMinutes'
    }

    It 'records the time it connected' {
        $script:connect | Should -Match '\$script:ConnectedAt = Get-Date'
    }

    It 'checks the token before the app package, the assets, each page, the dashboard, the findings, the navigation and each removal' {
        $steps = Get-ChildItem -LiteralPath (Join-Path $script:publishRoot 'Steps') -Filter '*.ps1' -File |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
        $joined = $steps -join "`n"
        foreach ($stage in 'app package', 'assets', 'dashboard', 'findings', 'navigation') {
            $joined | Should -Match ("Assert-TokenFresh '" + [regex]::Escape($stage) + "'") -Because $stage
        }
        $joined | Should -Match 'Assert-TokenFresh "page \$\(\$step\.Name\)"'
        $joined | Should -Match 'Assert-TokenFresh "remove page \$\(\$step\.Name\)"'
    }
}
