#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 unit tests for the helper functions inside
    Scripts/Export-SentinelWorkbooks.ps1.

.DESCRIPTION
    Uses the AST-extraction pattern (Tests/_helpers/Import-ScriptFunctions.psm1)
    to lift the script's nested function definitions into test scope without
    running its Main block (which would require an Azure context). Covers
    the two pure helpers:

      - ConvertTo-FolderName: PascalCase folder-name derivation matching the
        existing Workbooks/<Folder>/ naming convention.
      - Format-WorkbookJson:  pretty-printing parity with the existing
        Workbooks/*/workbook.json formatting.

    The Connect-AzureEnvironment / Invoke-SentinelApi orchestration that
    the rest of the script does is exercised at deploy-time (the matching
    Deploy-CustomWorkbooks function); a separate end-to-end test against a
    live workspace is out of scope here.
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Scripts/Export-SentinelWorkbooks.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop
    Import-ScriptFunctions -Path $scriptPath

    # Sentinel.Common is imported at the top of the script under test;
    # the AST extractor skips top-level statements, so import here so
    # extracted helpers can call Write-PipelineMessage at runtime.
    Import-Module "$repoRoot/Modules/Sentinel.Common/Sentinel.Common.psd1" -Force -ErrorAction Stop
}

Describe 'ConvertTo-FolderName' {

    # Per the user's instruction: folder name = workbook displayName
    # verbatim, with only filesystem-illegal characters replaced. No
    # PascalCase compaction, no case transformation.

    It 'returns the displayName verbatim when it has no illegal characters' {
        ConvertTo-FolderName -DisplayName 'Microsoft Sentinel Monitoring' |
            Should -Be 'Microsoft Sentinel Monitoring'
    }

    It 'preserves spaces in multi-word displayNames' {
        ConvertTo-FolderName -DisplayName 'Unifi Site Manager' |
            Should -Be 'Unifi Site Manager'
    }

    It 'preserves parentheses' {
        ConvertTo-FolderName -DisplayName 'Microsoft Sentinel Cost (GBP) v2' |
            Should -Be 'Microsoft Sentinel Cost (GBP) v2'
    }

    It 'preserves digits' {
        ConvertTo-FolderName -DisplayName 'Perimeter 81' | Should -Be 'Perimeter 81'
    }

    It 'preserves case exactly as the displayName provides it' {
        ConvertTo-FolderName -DisplayName 'pfSense Firewall' | Should -Be 'pfSense Firewall'
    }

    It 'replaces Windows-illegal characters with hyphens' {
        ConvertTo-FolderName -DisplayName 'Bad/Name:With*Illegal?Chars' |
            Should -Be 'Bad-Name-With-Illegal-Chars'
    }

    It 'replaces backslash and pipe' {
        ConvertTo-FolderName -DisplayName 'a\b|c' | Should -Be 'a-b-c'
    }

    It 'replaces angle brackets and quotes' {
        ConvertTo-FolderName -DisplayName 'a<b>c"d' | Should -Be 'a-b-c-d'
    }

    It 'trims trailing dots (Windows-illegal)' {
        ConvertTo-FolderName -DisplayName 'Workbook Name...' | Should -Be 'Workbook Name'
    }

    It 'trims trailing whitespace' {
        ConvertTo-FolderName -DisplayName 'Workbook Name   ' | Should -Be 'Workbook Name'
    }

    It 'collapses runs of whitespace to a single space' {
        ConvertTo-FolderName -DisplayName 'Foo   Bar' | Should -Be 'Foo Bar'
    }
}

Describe 'Remove-WorkspaceSuffix' {

    It 'strips a trailing " - <workspace>" suffix' {
        Remove-WorkspaceSuffix `
            -DisplayName  'Data Collection Rule Toolkit - stl-eus-siem-law' `
            -WorkspaceName 'stl-eus-siem-law' |
            Should -Be 'Data Collection Rule Toolkit'
    }

    It 'leaves the displayName unchanged when no suffix is present' {
        Remove-WorkspaceSuffix `
            -DisplayName  'Microsoft Sentinel Cost (GBP) v2' `
            -WorkspaceName 'stl-eus-siem-law' |
            Should -Be 'Microsoft Sentinel Cost (GBP) v2'
    }

    It 'is anchored to the end (does not strip a workspace name appearing mid-string)' {
        Remove-WorkspaceSuffix `
            -DisplayName  'A - stl-eus-siem-law - in middle' `
            -WorkspaceName 'stl-eus-siem-law' |
            Should -Be 'A - stl-eus-siem-law - in middle'
    }

    It 'requires the space-hyphen-space pattern (does not strip flush-prefixed)' {
        # 'Foo-stl-eus-siem-law' lacks the leading ' - ' so should
        # NOT match — that pattern is more likely the workspace
        # name baked into the workbook's actual name, not an
        # auto-attached suffix.
        Remove-WorkspaceSuffix `
            -DisplayName  'Foo-stl-eus-siem-law' `
            -WorkspaceName 'stl-eus-siem-law' |
            Should -Be 'Foo-stl-eus-siem-law'
    }

    It 'escapes regex metacharacters in the workspace name' {
        # If the workspace name contains characters with regex
        # meaning (dots, brackets, parens), the helper must escape
        # them so the match is literal.
        Remove-WorkspaceSuffix `
            -DisplayName  'My Workbook - law.with.dots' `
            -WorkspaceName 'law.with.dots' |
            Should -Be 'My Workbook'
    }

    It 'is case-sensitive (matches exact workspace name casing)' {
        # Workspace names in Azure are case-sensitive in URLs but
        # not in the portal. The strip is conservative — exact
        # match only — to avoid false positives if a workbook
        # legitimately ends with a similarly-cased phrase.
        Remove-WorkspaceSuffix `
            -DisplayName  'Foo - STL-EUS-SIEM-LAW' `
            -WorkspaceName 'stl-eus-siem-law' |
            Should -Be 'Foo - STL-EUS-SIEM-LAW'
    }
}

Describe 'Format-WorkbookJson' {

    It 'pretty-prints a hashtable as multi-line JSON' {
        $obj = @{ version = 'Notebook/1.0'; items = @() }
        $out = Format-WorkbookJson -JsonObject $obj
        $out | Should -Match '\n'
        $out | Should -Match '"version"'
        $out | Should -Match 'Notebook/1\.0'
    }

    It 'preserves nested structure to depth' {
        # Workbook gallery templates nest deeply (items > content > items).
        # Depth 32 is what the script uses; confirm it survives round-trip.
        $deep = @{
            items = @(
                @{
                    type    = 1
                    content = @{
                        json = "## Header"
                        nested = @{
                            inner = @{
                                deeper = @{ value = 'preserved' }
                            }
                        }
                    }
                }
            )
        }
        $out = Format-WorkbookJson -JsonObject $deep
        $out | Should -Match 'preserved'
    }

    It 'returns a string, not an object' {
        $obj = @{ version = 'Notebook/1.0' }
        $out = Format-WorkbookJson -JsonObject $obj
        $out | Should -BeOfType ([string])
    }
}
