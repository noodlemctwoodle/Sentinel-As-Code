#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for how the Word conversion stops when it cannot go on.

.DESCRIPTION
    The conversion used to be a script whose steps called exit. Run inside
    the module, exit would end the whole PowerShell session, so a step that
    cannot go on now throws, saying why, and a folder with no Markdown stops
    quietly with a warning. These tests drive Export-iSOCBlueprintWord
    through each stopping point, with pandoc present or absent as the test
    needs, and, when pandoc is installed, through one real conversion.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Word-Conversion.Tests.ps1

    Runs the Word conversion tests.

.NOTES
    File:         Tests/iSOCBlueprint/Word-Conversion.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeDiscovery {
    $script:pandocInstalled = [bool](Get-Command pandoc -ErrorAction SilentlyContinue)
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/iSOCBlueprint.psd1') -Force
}

AfterAll {
    Remove-Module iSOCBlueprint -ErrorAction SilentlyContinue
}

Describe 'Export-iSOCBlueprintWord when it cannot go on' {
    BeforeAll {
        $script:folder = Join-Path $TestDrive 'ws'
        New-Item -ItemType Directory -Path $script:folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:folder '00-overview.md') -Value "# Overview`n`nText.`n"
        $script:empty = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $script:empty -Force | Out-Null
        $script:file = Join-Path $TestDrive 'a-file.md'
        Set-Content -LiteralPath $script:file -Value '# A file'
    }

    Context 'with pandoc missing' {
        BeforeAll {
            Mock -ModuleName iSOCBlueprint Get-Command { $null } -ParameterFilter { $Name -eq 'pandoc' }
        }

        It 'throws, with how to install it, instead of ending the session' {
            { Export-iSOCBlueprintWord -Path $script:folder } | Should -Throw '*pandoc was not found on PATH*brew install pandoc*'
        }
    }

    Context 'with pandoc present' {
        BeforeAll {
            Mock -ModuleName iSOCBlueprint Get-Command { [pscustomobject]@{ Name = 'pandoc' } } -ParameterFilter { $Name -eq 'pandoc' }
        }

        It 'throws when the source folder does not exist' {
            { Export-iSOCBlueprintWord -Path (Join-Path $TestDrive 'nowhere') } | Should -Throw '*Source path does not exist*'
        }

        It 'throws when the source is a file' {
            { Export-iSOCBlueprintWord -Path $script:file } | Should -Throw '*Source must be a folder, not a file*'
        }

        It 'throws when the reference document is missing' {
            { Export-iSOCBlueprintWord -Path $script:folder -ReferenceDoc (Join-Path $TestDrive 'missing.docx') } | Should -Throw '*Reference document not found*'
        }

        It 'stops with a warning, and writes nothing, when the folder holds no Markdown' {
            $document = Join-Path $TestDrive 'empty.docx'
            $out = Export-iSOCBlueprintWord -Path $script:empty -OutputPath $document 6>&1 | Out-String
            $out | Should -Match 'No \.md files found under'
            $document | Should -Not -Exist
        }
    }
}

Describe 'Export-iSOCBlueprintWord with pandoc installed' -Skip:(-not $script:pandocInstalled) {
    BeforeAll {
        $script:folder = Join-Path $TestDrive 'real'
        New-Item -ItemType Directory -Path $script:folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:folder '00-overview.md') -Value "# Overview`n`nA paragraph.`n`n| A | B |`n| - | - |`n| 1 | 2 |`n"
    }

    It 'writes the document and returns it' {
        $document = Join-Path $TestDrive 'real.docx'
        $result = Export-iSOCBlueprintWord -Path $script:folder -OutputPath $document -Toc Styled 6> $null
        $document | Should -Exist
        $result.FullName | Should -Be $document
        (Get-Item -LiteralPath $document).Length | Should -BeGreaterThan 0
    }

    It 'writes nothing under -WhatIf' {
        $document = Join-Path $TestDrive 'whatif.docx'
        Export-iSOCBlueprintWord -Path $script:folder -OutputPath $document -Toc Styled -WhatIf 6> $null | Out-Null
        $document | Should -Not -Exist
    }
}
