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

Describe 'Merge-WorkbookMetadata' {

    Context 'no existing metadata.json' {

        It 'returns API values verbatim' {
            $merged = Merge-WorkbookMetadata `
                -ApiDisplayName    'Foo Bar' `
                -ApiDescription    'API description' `
                -ApiCategory       'Sentinel' `
                -FolderName        'FooBar' `
                -WorkbookId        '12345' `
                -ExistingMetadata  $null

            $merged.displayName | Should -Be 'Foo Bar'
            $merged.description | Should -Be 'API description'
            $merged.category    | Should -Be 'Sentinel'
            $merged.sourceId    | Should -Be 'FooBar'
            $merged.workbookId  | Should -Be '12345'
        }

        It 'fills empty API category with the default sentinel' {
            $merged = Merge-WorkbookMetadata `
                -ApiDisplayName 'X' -ApiDescription '' -ApiCategory '' `
                -FolderName 'X' -WorkbookId 'g' -ExistingMetadata $null
            $merged.category | Should -Be 'sentinel'
        }
    }

    Context 'existing metadata.json with curated values' {

        BeforeAll {
            $script:curated = [pscustomobject]@{
                displayName = 'UniFi Site Manager'
                description = 'Multi-site management workbook for UniFi environments.'
                category    = 'Network'
                sourceId    = 'UnifiSiteManager'
            }
        }

        It 'preserves curated description when API returns empty' {
            $merged = Merge-WorkbookMetadata `
                -ApiDisplayName    'UniFi Site Manager' `
                -ApiDescription    '' `
                -ApiCategory       'sentinel' `
                -FolderName        'UnifiSiteManager' `
                -WorkbookId        'gid' `
                -ExistingMetadata  $curated
            $merged.description | Should -Be 'Multi-site management workbook for UniFi environments.'
        }

        It 'preserves curated category over the generic API default' {
            $merged = Merge-WorkbookMetadata `
                -ApiDisplayName    'UniFi Site Manager' `
                -ApiDescription    '' `
                -ApiCategory       'sentinel' `
                -FolderName        'UnifiSiteManager' `
                -WorkbookId        'gid' `
                -ExistingMetadata  $curated
            $merged.category | Should -Be 'Network'
        }

        It "preserves the author's displayName casing when names match case-insensitively" {
            # API returns 'Unifi Site Manager' (lowercase f), curated
            # has 'UniFi Site Manager' (capital F brand spelling) —
            # keep the curated case.
            $merged = Merge-WorkbookMetadata `
                -ApiDisplayName    'Unifi Site Manager' `
                -ApiDescription    '' `
                -ApiCategory       'sentinel' `
                -FolderName        'UnifiSiteManager' `
                -WorkbookId        'gid' `
                -ExistingMetadata  $curated
            $merged.displayName | Should -Be 'UniFi Site Manager'
        }

        It 'always overrides sourceId with the folder name (not the existing value)' {
            $stale = [pscustomobject]@{
                sourceId = '/subscriptions/old-arm-path/...'
            }
            $merged = Merge-WorkbookMetadata `
                -ApiDisplayName    'Foo' `
                -ApiDescription    '' `
                -ApiCategory       'sentinel' `
                -FolderName        'Foo' `
                -WorkbookId        'gid' `
                -ExistingMetadata  $stale
            $merged.sourceId | Should -Be 'Foo'
        }

        It 'always uses the API workbookId (resource GUID is canonical)' {
            $stale = [pscustomobject]@{
                workbookId = 'old-stale-guid'
            }
            $merged = Merge-WorkbookMetadata `
                -ApiDisplayName    'Foo' `
                -ApiDescription    '' `
                -ApiCategory       'sentinel' `
                -FolderName        'Foo' `
                -WorkbookId        'fresh-guid-from-api' `
                -ExistingMetadata  $stale
            $merged.workbookId | Should -Be 'fresh-guid-from-api'
        }

        It 'uses API displayName when names differ semantically (rename, not just casing)' {
            $renamed = [pscustomobject]@{
                displayName = 'Old Name'
                description = 'Whatever'
                category    = 'Network'
            }
            $merged = Merge-WorkbookMetadata `
                -ApiDisplayName    'New Name' `
                -ApiDescription    '' `
                -ApiCategory       'sentinel' `
                -FolderName        'NewName' `
                -WorkbookId        'gid' `
                -ExistingMetadata  $renamed
            $merged.displayName | Should -Be 'New Name'
        }

        It 'uses API description when API returns a non-empty value' {
            $merged = Merge-WorkbookMetadata `
                -ApiDisplayName    'Foo' `
                -ApiDescription    'API has a description now' `
                -ApiCategory       'sentinel' `
                -FolderName        'Foo' `
                -WorkbookId        'gid' `
                -ExistingMetadata  $curated
            $merged.description | Should -Be 'API has a description now'
        }
    }

    Context 'extra keys preserved' {

        It 'preserves keys this helper does not write (e.g. tags, custom annotations)' {
            $existing = [pscustomobject]@{
                displayName = 'Foo'
                description = 'desc'
                category    = 'Network'
                sourceId    = 'Foo'
                tags        = @('a', 'b')
                customNote  = 'do not delete'
            }
            $merged = Merge-WorkbookMetadata `
                -ApiDisplayName    'Foo' `
                -ApiDescription    '' `
                -ApiCategory       'sentinel' `
                -FolderName        'Foo' `
                -WorkbookId        'gid' `
                -ExistingMetadata  $existing
            $merged.Contains('tags')       | Should -BeTrue
            $merged.Contains('customNote') | Should -BeTrue
            $merged.customNote             | Should -Be 'do not delete'
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
