#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for Tools/Migrate-ForkLayout.ps1: the partial-migration merge
    that brings a fork's stragglers onto the current layout.

.DESCRIPTION
    Each test builds a throwaway repository with content at an old path
    and the new path already present, runs the helper against it, and
    checks the tree it leaves:

      - customisations nested in a subfolder both sides have come across
      - a file both sides have is left in place, with a warning
      - old folders the merge empties are removed
      - -WhatIf touches nothing

.EXAMPLE
    Invoke-Pester -Path Tests/Test-MigrateForkLayout.Tests.ps1

.NOTES
    File:         Tests/Test-MigrateForkLayout.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.2
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+, Pester 5+, git
#>

BeforeAll {
    $script:migrate = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools/Migrate-ForkLayout.ps1'

    function New-ForkRepo {
        <#
        .SYNOPSIS
            Creates a temporary git repository laid out like a fork that still has the old Blueprint folders.
        #>
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('fork-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
        git -C $root init -q
        $files = [ordered]@{
            'Modules/iSOCBlueprint/Engine/Private/Existing.ps1' = 'new'
            'Modules/iSOCBlueprint/Engine/Deep/Kept.yaml'       = 'new'
            'Tools/Blueprint/Private/Existing.ps1'              = 'old'
            'Tools/Blueprint/Private/Custom.ps1'                = 'old'
            'Tools/Blueprint/Deep/Nested/Rule.yaml'             = 'old'
            'Tools/Blueprint/Top.ps1'                           = 'old'
        }
        foreach ($rel in $files.Keys) {
            $path = Join-Path $root $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            Set-Content -LiteralPath $path -Value $files[$rel] -NoNewline
        }
        $root
    }
}

Describe 'Migrate-ForkLayout merging a partial migration' {
    BeforeEach {
        $script:repo = New-ForkRepo
    }

    AfterEach {
        Remove-Item -LiteralPath $script:repo -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'brings customisations across from subfolders both sides have' {
        & $script:migrate -RepoPath $script:repo -AllowDirty -WarningAction SilentlyContinue 6>$null

        $engine = Join-Path $script:repo 'Modules/iSOCBlueprint/Engine'
        Get-Content -LiteralPath (Join-Path $engine 'Private/Custom.ps1') -Raw | Should -Be 'old'
        Get-Content -LiteralPath (Join-Path $engine 'Deep/Nested/Rule.yaml') -Raw | Should -Be 'old'
        Get-Content -LiteralPath (Join-Path $engine 'Deep/Kept.yaml') -Raw | Should -Be 'new'
        Get-Content -LiteralPath (Join-Path $engine 'Top.ps1') -Raw | Should -Be 'old'
    }

    It 'leaves a file both sides have in place and warns about it' {
        & $script:migrate -RepoPath $script:repo -AllowDirty -WarningVariable warnings -WarningAction SilentlyContinue 6>$null

        Get-Content -LiteralPath (Join-Path $script:repo 'Modules/iSOCBlueprint/Engine/Private/Existing.ps1') -Raw | Should -Be 'new'
        Get-Content -LiteralPath (Join-Path $script:repo 'Tools/Blueprint/Private/Existing.ps1') -Raw | Should -Be 'old'
        @($warnings | Where-Object { "$_" -match 'collision' }).Count | Should -Be 1
        ($warnings | Where-Object { "$_" -match 'collision' }) -join '' | Should -Match 'Existing\.ps1'
    }

    It 'removes old folders the merge empties and keeps those still holding a conflict' {
        & $script:migrate -RepoPath $script:repo -AllowDirty -WarningAction SilentlyContinue 6>$null

        Test-Path -LiteralPath (Join-Path $script:repo 'Tools/Blueprint/Deep') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:repo 'Tools/Blueprint/Private') | Should -BeTrue
        @(Get-ChildItem -LiteralPath (Join-Path $script:repo 'Tools/Blueprint/Private')).Name | Should -Be @('Existing.ps1')
    }

    It 'moves and removes nothing under -WhatIf' {
        & $script:migrate -RepoPath $script:repo -AllowDirty -WhatIf -WarningAction SilentlyContinue 6>$null

        Test-Path -LiteralPath (Join-Path $script:repo 'Tools/Blueprint/Deep/Nested/Rule.yaml') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:repo 'Tools/Blueprint/Private/Custom.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:repo 'Modules/iSOCBlueprint/Engine/Private/Custom.ps1') | Should -BeFalse
    }
}

Describe 'Migrate-ForkLayout moving the static files to Resources' {
    BeforeEach {
        $script:repo = Join-Path ([System.IO.Path]::GetTempPath()) ('fork-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:repo | Out-Null
        git -C $script:repo init -q
        $files = [ordered]@{
            'Tools/Blueprint/Private/Resources/best-practices.json'    = 'rules'
            'Tools/Blueprint/Schemas/section.schema.json'              = 'schema'
            'Tools/Blueprint/Report/templates/reference.docx'          = 'docx'
            'Tools/Blueprint/Report/Update-WordToc.py'                 = 'py'
            'Tools/Blueprint/SharePoint/templates/dashboard/01.html'   = 'html'
            'Tools/Blueprint/Blueprint.psd1'                           = 'psd1'
            'Tools/Blueprint/Private/Custom.ps1'                       = 'script'
            'Modules/iSOCBlueprint/Engine/Private/Resources/mine.json' = 'mine'
        }
        foreach ($rel in $files.Keys) {
            $path = Join-Path $script:repo $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            Set-Content -LiteralPath $path -Value $files[$rel] -NoNewline
        }
    }

    AfterEach {
        Remove-Item -LiteralPath $script:repo -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'puts each static file where the module reads it' {
        & $script:migrate -RepoPath $script:repo -AllowDirty -WarningAction SilentlyContinue 6>$null

        $resources = Join-Path $script:repo 'Modules/iSOCBlueprint/Resources'
        Get-Content -LiteralPath (Join-Path $resources 'Data/best-practices.json') -Raw | Should -Be 'rules'
        Get-Content -LiteralPath (Join-Path $resources 'Data/mine.json') -Raw | Should -Be 'mine'
        Get-Content -LiteralPath (Join-Path $resources 'Schemas/section.schema.json') -Raw | Should -Be 'schema'
        Get-Content -LiteralPath (Join-Path $resources 'Report/templates/reference.docx') -Raw | Should -Be 'docx'
        Get-Content -LiteralPath (Join-Path $resources 'Report/Update-WordToc.py') -Raw | Should -Be 'py'
        Get-Content -LiteralPath (Join-Path $resources 'SharePoint/templates/dashboard/01.html') -Raw | Should -Be 'html'
        Get-Content -LiteralPath (Join-Path $resources 'Blueprint.psd1') -Raw | Should -Be 'psd1'
    }

    It 'leaves a script of the fork''s own in Engine, where the module does not load it' {
        & $script:migrate -RepoPath $script:repo -AllowDirty -WarningAction SilentlyContinue 6>$null

        Get-Content -LiteralPath (Join-Path $script:repo 'Modules/iSOCBlueprint/Engine/Private/Custom.ps1') -Raw | Should -Be 'script'
        Test-Path -LiteralPath (Join-Path $script:repo 'Modules/iSOCBlueprint/Engine/Private/Resources') | Should -BeFalse
    }
}
