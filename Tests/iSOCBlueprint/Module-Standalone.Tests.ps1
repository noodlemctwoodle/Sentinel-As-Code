#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests that the iSOCBlueprint module works away from this
    repository.

.DESCRIPTION
    The module is meant to be usable on its own, installed anywhere. This
    suite copies Modules/iSOCBlueprint, less the web part source, to a
    folder outside the repository, imports it from there and runs the
    offline steps over the fixture inventory: render both formats, build the SharePoint bundle, and run
    the gap analysis and the maturity assessment. A step that still reached
    into the repository (the shared module, the docs, a relative path two
    folders up) would fail or produce a gap here, such as a missing page 99.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Module-Standalone.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCBlueprint/Module-Standalone.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.1
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml (the renderer)
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:copy = Join-Path $TestDrive 'modules/iSOCBlueprint'
    # Everything but the web part source, as an installed module would ship:
    # the module loads nothing from WebParts/, and a locally built
    # node_modules there would make the copy slow.
    New-Item -ItemType Directory -Path $script:copy -Force | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Modules/iSOCBlueprint') -Force |
        Where-Object Name -ne 'WebParts' |
        Copy-Item -Destination $script:copy -Recurse -Force

    Remove-Module iSOCBlueprint -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:copy 'iSOCBlueprint.psd1') -Force

    $script:work = Join-Path $TestDrive 'work'
    $script:ws = Join-Path $script:work 'SecurityDocs/law-standalone'
    New-Item -ItemType Directory -Path $script:ws -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'Tests/iSOCBlueprint/Fixtures/sample/_raw') -Destination $script:ws -Recurse

    Push-Location $script:work
    $script:report = ConvertTo-iSOCBlueprint -WorkspaceName law-standalone *>&1 | Where-Object { $_ -is [pscustomobject] }
    $script:bundle = New-iSOCBlueprintSite -Path SecurityDocs/law-standalone -SkipWhatsNew *>&1 | Where-Object { $_ -is [pscustomobject] }
    Pop-Location
}

AfterAll {
    Remove-Module iSOCBlueprint -ErrorAction SilentlyContinue
}

Describe 'iSOCBlueprint outside the repository' {
    It 'is loaded from the copy, not the repository' {
        (Get-Module iSOCBlueprint).ModuleBase | Should -Be $script:copy
    }

    It 'runs without the web part source beside it' {
        Test-Path -LiteralPath (Join-Path $script:copy 'WebParts') | Should -BeFalse
        @((Get-Module iSOCBlueprint).ExportedFunctions.Keys).Count | Should -Be 12
    }

    It 'renders the Markdown report and the section model from the default folder' {
        $script:report.Path | Should -Be $script:ws
        @(Get-ChildItem -LiteralPath $script:ws -Filter '*.md').Count | Should -BeGreaterThan 30
        Test-Path -LiteralPath (Join-Path $script:ws 'sections/index.json') | Should -BeTrue
    }

    It 'writes page 99 from the references the module ships' {
        $page = Join-Path $script:ws '99-references.md'
        Test-Path -LiteralPath $page | Should -BeTrue
        (Get-FileHash -LiteralPath $page).Hash |
            Should -Be (Get-FileHash -LiteralPath (Join-Path $script:copy 'Engine/Private/Resources/Blueprint-References.md')).Hash
    }

    It 'links the gap-analysis method to GitHub rather than a repository-relative path' {
        $page = Get-Content -LiteralPath (Join-Path $script:ws '90-gap-analysis.md') -Raw
        $page | Should -Match 'https://github\.com/noodlemctwoodle/Sentinel-As-Code/blob/main/Modules/iSOCBlueprint/Engine/Private/GapChecks\.ps1'
        $page | Should -Not -Match '\]\(\.\./\.\./'
    }

    It 'builds the SharePoint bundle offline' {
        $script:bundle.Path | Should -Be (Join-Path $script:ws 'sharepoint')
        foreach ($f in 'site.json', 'model.json', 'findings.json', 'index.html') {
            Test-Path -LiteralPath (Join-Path $script:bundle.Path $f) | Should -BeTrue -Because $f
        }
    }

    It 'finds every file the engine loads by a path relative to its own folder' {
        $engine = Join-Path $script:copy 'Engine'
        $rx = [regex]'Join-Path\s+(?:-Path\s+)?\$PSScriptRoot\s+(?:-ChildPath\s+)?[''"]([^''"$]+)[''"]'
        $checked = 0
        foreach ($file in Get-ChildItem -LiteralPath $engine -Recurse -Filter '*.ps1' -File) {
            foreach ($m in $rx.Matches((Get-Content -LiteralPath $file.FullName -Raw))) {
                $relative = $m.Groups[1].Value
                Test-Path -LiteralPath (Join-Path $file.DirectoryName $relative) | Should -BeTrue -Because "$($file.Name) loads $relative"
                $checked++
            }
        }
        $checked | Should -BeGreaterThan 40
    }

    It 'never climbs from the engine to the repository root' {
        $engine = Join-Path $script:copy 'Engine'
        foreach ($file in Get-ChildItem -LiteralPath $engine -Recurse -Filter '*.ps1' -File) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            $text | Should -Not -Match 'Split-Path -Parent \(Split-Path -Parent \$PSScriptRoot\)' -Because $file.Name
            $text | Should -Not -Match '\$PSScriptRoot\s+[''"]\.\./\.\./' -Because $file.Name
        }
    }

    It 'runs the gap analysis and the maturity assessment from the copy' {
        @(Get-iSOCBlueprintFinding -Path $script:ws 3>$null).Count | Should -BeGreaterThan 0
        (Get-iSOCBlueprintMaturity -Path $script:ws 3>$null).overall | Should -Not -BeNullOrEmpty
    }
}
