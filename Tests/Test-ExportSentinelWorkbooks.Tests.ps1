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

    It 'collapses a multi-word displayName to PascalCase' {
        ConvertTo-FolderName -DisplayName 'Microsoft Sentinel Monitoring' |
            Should -Be 'MicrosoftSentinelMonitoring'
    }

    It 'leaves a single-word PascalCase name unchanged' {
        ConvertTo-FolderName -DisplayName 'PfSense' | Should -Be 'PfSense'
    }

    It 'strips non-alphanumeric separators (hyphen, slash, dot)' {
        ConvertTo-FolderName -DisplayName 'Security/Operations-Dashboard.v2' |
            Should -Be 'SecurityOperationsDashboardV2'
    }

    It 'preserves digits' {
        ConvertTo-FolderName -DisplayName 'Perimeter 81' | Should -Be 'Perimeter81'
    }

    It 'capitalises the first letter of a lowercase word' {
        ConvertTo-FolderName -DisplayName 'my custom workbook' | Should -Be 'MyCustomWorkbook'
    }

    It 'handles already-compact PascalCase input' {
        ConvertTo-FolderName -DisplayName 'SecurityOverview' | Should -Be 'SecurityOverview'
    }

    It 'handles input with multiple spaces' {
        ConvertTo-FolderName -DisplayName 'Foo   Bar' | Should -Be 'FooBar'
    }

    It 'matches the convention used by every existing Workbooks/<Folder>' {
        # Confirms parity with the on-disk folder names so a redeploy
        # round-trips without spawning a "fresh" folder for the same
        # workbook.
        $workbooksRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'Workbooks'
        if (Test-Path $workbooksRoot) {
            $folders = @(Get-ChildItem -Path $workbooksRoot -Directory)
            foreach ($folder in $folders) {
                # ConvertTo-FolderName applied to the folder name itself
                # should be idempotent.
                ConvertTo-FolderName -DisplayName $folder.Name |
                    Should -Be $folder.Name -Because "round-trip on existing folder '$($folder.Name)' must be idempotent"
            }
        }
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
