#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests that the iSOCBlueprint engine is an exact copy of
    Tools/Blueprint, apart from the listed edits.

.DESCRIPTION
    While Tools/Blueprint and Modules/iSOCBlueprint/Engine both exist, a
    fix made in one and not the other would split the Blueprint in two.
    For every file the migration map copies, this suite applies the edits
    in Engine-Edits.psd1 to the source and requires the result to equal the
    engine file byte for byte (binary files by hash). It also checks the
    engine holds nothing the map does not account for, and that the
    vendored files still match their originals: the two KQL helpers against
    Modules/Sentinel.Common and Blueprint-References.md against the docs.

    When this fails after a deliberate change, make the same change on the
    other side (or add an edit to Engine-Edits.psd1 when the difference is
    meant to stay).

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Engine-Copy.Tests.ps1

    Runs the whole suite.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Engine-Copy.Tests.ps1 -Output Detailed

    Lists every file compared.

.NOTES
    File:         Tests/iSOCBlueprint/Engine-Copy.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $PSScriptRoot '_helpers/Migration.psm1') -Force
    $copies = @(Get-MigrationMap -RepoRoot $repoRoot | Where-Object Action -eq 'Copy' | ForEach-Object {
            @{ Source = $_.Source; Destination = $_.Destination }
        })
    $vendored = @('Remove-KqlComments', 'Get-KqlBareIdentifiers' | ForEach-Object { @{ Name = $_ } })
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $PSScriptRoot '_helpers/Migration.psm1') -Force
    $script:map = @(Get-MigrationMap -RepoRoot $script:repoRoot)
    $script:edits = Get-EngineEdit -RepoRoot $script:repoRoot
    $script:textExtensions = '.ps1', '.psd1', '.py', '.json', '.html', '.md'

    function Get-FunctionText {
        param([string] $Path, [string] $Name)
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }, $false)
        @($fn | ForEach-Object { $_.Extent.Text })
    }
}

Describe 'Engine copy of Tools/Blueprint' {
    It '<Destination> exists' -ForEach $copies {
        Test-Path -LiteralPath (Join-Path $script:repoRoot $Destination) -PathType Leaf | Should -BeTrue
    }

    It '<Destination> equals its source with only the listed edits' -ForEach $copies {
        $src = Join-Path $script:repoRoot $Source
        $dst = Join-Path $script:repoRoot $Destination
        if ([System.IO.Path]::GetExtension($src).ToLowerInvariant() -in $script:textExtensions) {
            $relative = $Source -replace '^Tools/Blueprint/', ''
            $expected = Get-ExpectedEngineText -SourceText ([System.IO.File]::ReadAllText($src)) -RelativePath $relative -EditDocument $script:edits
            $actual = [System.IO.File]::ReadAllText($dst)
            if (-not [string]::Equals($actual, $expected, [StringComparison]::Ordinal)) {
                # Name the first line that differs rather than dumping the file.
                $e = $expected -split "`n"
                $a = $actual -split "`n"
                $i = 0
                while ($i -lt [Math]::Min($e.Count, $a.Count) -and [string]::Equals($e[$i], $a[$i], [StringComparison]::Ordinal)) { $i++ }
                $want = if ($i -lt $e.Count) { $e[$i] } else { '<end of file>' }
                $got = if ($i -lt $a.Count) { $a[$i] } else { '<end of file>' }
                $got | Should -BeExactly $want -Because "line $($i + 1) of $Destination must match its source after the listed edits"
            }
            [System.IO.File]::ReadAllBytes($dst)[0..2] -join ',' | Should -Not -Be '239,187,191' -Because 'copies are written without a byte-order mark, like their sources'
        }
        else {
            (Get-FileHash -LiteralPath $dst).Hash | Should -Be (Get-FileHash -LiteralPath $src).Hash
        }
    }

    It 'holds no file the migration map does not account for' {
        $engine = Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine'
        $known = @($script:map | Where-Object { $_.Action -in 'Copy', 'Vendor' } | ForEach-Object Destination)
        $stray = @(Get-ChildItem -LiteralPath $engine -Recurse -File -Force |
                Where-Object Name -ne '.DS_Store' |
                ForEach-Object { 'Modules/iSOCBlueprint/Engine/' + [System.IO.Path]::GetRelativePath($engine, $_.FullName).Replace('\', '/') } |
                Where-Object { $_ -notin $known })
        $stray | Should -BeNullOrEmpty
    }

    It 'does not carry the retired folder-to-Word converter' {
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Report/Convert-FolderToWordReport.ps1') | Should -BeFalse
    }
}

Describe 'Vendored files' {
    BeforeAll {
        $script:vendorFile = Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Private/Vendor/SentinelCommon.Kql.ps1'
        $script:commonFile = Join-Path $script:repoRoot 'Modules/Sentinel.Common/Sentinel.Common.psm1'
    }

    It '<Name> is identical to the Sentinel.Common original' -ForEach $vendored {
        $copy = @(Get-FunctionText -Path $script:vendorFile -Name $Name)
        $original = @(Get-FunctionText -Path $script:commonFile -Name $Name)
        $copy.Count | Should -Be 1
        $original.Count | Should -Be 1
        $copy[0] | Should -BeExactly $original[0]
    }

    It 'the vendor file defines only the two helpers' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:vendorFile, [ref]$null, [ref]$null)
        $names = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) | ForEach-Object Name | Sort-Object)
        $names | Should -Be @('Get-KqlBareIdentifiers', 'Remove-KqlComments')
    }

    It 'Blueprint-References.md matches the docs copy' {
        $row = $script:map | Where-Object { $_.Action -eq 'Vendor' -and $_.Destination -like '*Blueprint-References.md' }
        $row | Should -Not -BeNullOrEmpty
        (Get-FileHash -LiteralPath (Join-Path $script:repoRoot $row.Destination)).Hash |
            Should -Be (Get-FileHash -LiteralPath (Join-Path $script:repoRoot $row.Source)).Hash
    }
}
