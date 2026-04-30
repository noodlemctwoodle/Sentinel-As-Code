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

    # Folder names are PascalCase, no spaces, no punctuation. Matches
    # the convention used by every existing Workbooks/<Folder>/ in
    # the repo. Acronyms (GBP, DNS) are TitleCased to match the
    # repo's style ('Gbp' not 'GBP'); user-curated camelCase
    # (pfSense, MicrosoftSentinel) is preserved.

    It 'compacts a multi-word displayName to PascalCase' {
        ConvertTo-FolderName -DisplayName 'Microsoft Sentinel Monitoring' |
            Should -Be 'MicrosoftSentinelMonitoring'
    }

    It 'compacts simple two-word names' {
        ConvertTo-FolderName -DisplayName 'Unifi Site Manager' |
            Should -Be 'UnifiSiteManager'
    }

    It 'TitleCases all-upper acronyms (GBP -> Gbp)' {
        ConvertTo-FolderName -DisplayName 'Microsoft Sentinel Cost (GBP) v2' |
            Should -Be 'MicrosoftSentinelCostGbpV2'
    }

    It 'preserves user-curated camelCase brands (pfSense)' {
        ConvertTo-FolderName -DisplayName 'pfSense Firewall' |
            Should -Be 'PfSenseFirewall'
    }

    It 'handles digits adjacent to letters' {
        ConvertTo-FolderName -DisplayName 'Perimeter 81' | Should -Be 'Perimeter81'
    }

    It 'TitleCases all-lowercase words' {
        ConvertTo-FolderName -DisplayName 'my custom workbook' | Should -Be 'MyCustomWorkbook'
    }

    It 'leaves an already-compact PascalCase identifier intact' {
        ConvertTo-FolderName -DisplayName 'MicrosoftSentinelMonitoring' |
            Should -Be 'MicrosoftSentinelMonitoring'
    }

    It 'treats every non-alphanumeric run as a word boundary' {
        ConvertTo-FolderName -DisplayName 'Bad/Name:With*Illegal?Chars' |
            Should -Be 'BadNameWithIllegalChars'
    }

    It 'collapses multiple spaces' {
        ConvertTo-FolderName -DisplayName 'Foo   Bar' | Should -Be 'FooBar'
    }

    It 'real-world: Summary Rules Workbook' {
        ConvertTo-FolderName -DisplayName 'Summary Rules Workbook' |
            Should -Be 'SummaryRulesWorkbook'
    }

    It 'real-world: Microsoft Sentinel Optimization Workbook' {
        ConvertTo-FolderName -DisplayName 'Microsoft Sentinel Optimization Workbook' |
            Should -Be 'MicrosoftSentinelOptimizationWorkbook'
    }

    It 'real-world: Data Collection Rule Toolkit' {
        ConvertTo-FolderName -DisplayName 'Data Collection Rule Toolkit' |
            Should -Be 'DataCollectionRuleToolkit'
    }

    It 'real-world: Sentinel Data Lake' {
        ConvertTo-FolderName -DisplayName 'Sentinel Data Lake' |
            Should -Be 'SentinelDataLake'
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

Describe 'Remove-WorkspaceArmId' {

    BeforeAll {
        $script:wsId = '/subscriptions/5305ccd2-977a-4630-843b-bad582e756a3/resourcegroups/stl-eus-siem-rg/providers/microsoft.operationalinsights/workspaces/stl-eus-siem-law'
        $script:placeholder = '/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/your-resource-group/providers/microsoft.operationalinsights/workspaces/your-workspace'
    }

    It 'replaces a literal occurrence of the workspace ARM ID with the placeholder' {
        $json = '"fallbackResourceIds": ["' + $wsId + '"]'
        $out = Remove-WorkspaceArmId -Json $json -WorkspaceResourceId $wsId
        $out | Should -Be ('"fallbackResourceIds": ["' + $placeholder + '"]')
    }

    It 'leaves unrelated content unchanged' {
        $json = '{"fallbackResourceIds": [""], "isLocked": true, "items": []}'
        Remove-WorkspaceArmId -Json $json -WorkspaceResourceId $wsId | Should -Be $json
    }

    It 'replaces every occurrence (multiple matches)' {
        $json = '"a": "' + $wsId + '", "b": "' + $wsId + '"'
        $out = Remove-WorkspaceArmId -Json $json -WorkspaceResourceId $wsId
        ($out -split [regex]::Escape($placeholder)).Count | Should -Be 3   # 2 splits = 3 segments
        $out | Should -Not -Match ([regex]::Escape($wsId))
    }

    It 'matches case-insensitively (real serialized data uses lowercase resource provider names)' {
        # Az PowerShell sometimes returns workspace IDs with mixed-case
        # resource provider segments (Microsoft.OperationalInsights),
        # while the serialized workbook data uses all-lowercase
        # (microsoft.operationalinsights). The case-insensitive
        # match covers both.
        $mixedCaseId = '/subscriptions/5305ccd2-977a-4630-843b-bad582e756a3/resourceGroups/stl-eus-siem-rg/providers/Microsoft.OperationalInsights/workspaces/stl-eus-siem-law'
        $allLowerJson = '"fallbackResourceIds": ["' + $wsId.ToLowerInvariant() + '"]'

        $out = Remove-WorkspaceArmId -Json $allLowerJson -WorkspaceResourceId $mixedCaseId
        $out | Should -Be ('"fallbackResourceIds": ["' + $placeholder + '"]')
    }

    It 'handles regex metacharacters in the workspace ID safely' {
        # Workspace ARM IDs contain dots, hyphens, slashes — all
        # regex metacharacters. The helper must escape them.
        $json = '"x": "' + $wsId + '"'
        $out = Remove-WorkspaceArmId -Json $json -WorkspaceResourceId $wsId
        $out | Should -Match ([regex]::Escape($placeholder))
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
