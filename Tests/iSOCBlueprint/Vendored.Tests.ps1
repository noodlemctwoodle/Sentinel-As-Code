#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests that the iSOCBlueprint module's vendored copies match
    their originals.

.DESCRIPTION
    The module ships its own copy of Blueprint-References.md from
    Docs/Modules/iSOCBlueprint (page 99 of every report), so it can run on
    its own. A copy that drifts from its original reintroduces the
    fix-in-one-place bug, so this suite fails until both sides match: fix
    the original first, then copy it across.

    The KQL helpers Remove-KqlComments and Get-KqlBareIdentifiers were a
    copy of Modules/Sentinel.Common's until that module retired in release
    26.11.0; they are the Blueprint's own code now, and the suite holds the
    vendor file to just those two.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Vendored.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCBlueprint/Vendored.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.3.3
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+, Pester 5+

    Version 0.1.0 was Engine-Copy.Tests.ps1, which also held the engine
    byte-identical to Tools/Blueprint until that folder was removed.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:vendorFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Private/Kql/Vendor') -Filter '*.ps1' -File)

    function Get-FunctionText {
        param([System.IO.FileInfo[]] $File, [string] $Name)
        foreach ($f in $File) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }, $false) |
                ForEach-Object { $_.Extent.Text }
        }
    }
}

Describe 'Vendored KQL helpers' {
    It 'defines <_> once' -ForEach @('Remove-KqlComments', 'Get-KqlBareIdentifiers') {
        @(Get-FunctionText -File $script:vendorFiles -Name $_).Count | Should -Be 1
    }

    It 'the vendor folder defines only the two helpers, one to a file' {
        $names = @($script:vendorFiles | ForEach-Object {
                [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null).FindAll({
                    param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $false) |
                    ForEach-Object { $_.Name }
            } | Sort-Object)
        @($script:vendorFiles).Count | Should -Be 2
        $names | Should -Be @('Get-KqlBareIdentifiers', 'Remove-KqlComments')
    }
}

Describe 'Vendored references page' {
    It 'Blueprint-References.md matches the docs copy' {
        $docs = Join-Path $script:repoRoot 'Docs/Modules/iSOCBlueprint/Blueprint-References.md'
        $shipped = Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Resources/Data/Blueprint-References.md'
        (Get-FileHash -LiteralPath $shipped).Hash | Should -Be (Get-FileHash -LiteralPath $docs).Hash
    }
}
