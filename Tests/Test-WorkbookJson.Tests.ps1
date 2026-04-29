#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 schema validation for every Workbooks/{Name}/workbook.json
    plus its sibling metadata.json.

.DESCRIPTION
    Sentinel workbook templates ship in TWO valid formats:

    1. **ARM deployment template** — the workbook.json is an ARM template
       wrapping a Microsoft.Insights/workbooks resource. Required:
       deploymentTemplate `$schema`, `resources` array containing at least
       one Microsoft.Insights/workbooks of kind "shared" with
       properties.{displayName,serializedData,sourceId}.

    2. **Gallery notebook** — the workbook.json IS the notebook itself
       (the export format from "Advanced Editor > Workbook (JSON)" in the
       Sentinel portal). Required: top-level `version` and `items` array.

    The deploy logic accepts both. The format is detected by inspecting
    top-level keys: presence of `resources` selects the ARM branch;
    presence of `items` (without `resources`) selects the gallery branch.

    Sibling metadata.json (where present) has displayName + sourceId so
    the gallery picker shows the workbook in the right category.

    Cross-file invariant: every ARM workbook resource GUID is unique
    across the tree (Sentinel uses it as the workbook resource name).

.NOTES
    Run all tests:
        Invoke-Pester -Path Tests/Test-WorkbookJson.Tests.ps1
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot

    $script:workbookCases = @()
    $workbookRoot = Join-Path $repoRoot 'Workbooks'
    if (Test-Path $workbookRoot) {
        $script:workbookCases = @(Get-ChildItem -Path $workbookRoot -Directory | ForEach-Object {
            $dir       = $_.FullName
            $relDir    = ($dir.Substring($repoRoot.Length + 1)) -replace '\\', '/'
            $jsonPath  = Join-Path $dir 'workbook.json'
            $metaPath  = Join-Path $dir 'metadata.json'

            $body = $null
            $bodyError = $null
            if (Test-Path $jsonPath) {
                try {
                    $body = Get-Content -Path $jsonPath -Raw -ErrorAction Stop |
                        ConvertFrom-Json -Depth 64 -AsHashtable -ErrorAction Stop
                }
                catch {
                    $bodyError = $_.Exception.Message
                }
            }

            # Format detection. ARM templates have `resources`; gallery
            # notebooks have `items` (and no `resources`).
            $format = 'unknown'
            if ($body -is [System.Collections.IDictionary]) {
                if ($body.ContainsKey('resources')) { $format = 'arm' }
                elseif ($body.ContainsKey('items')) { $format = 'notebook' }
            }

            $meta = $null
            if (Test-Path $metaPath) {
                try {
                    $meta = Get-Content -Path $metaPath -Raw -ErrorAction Stop |
                        ConvertFrom-Json -Depth 16 -AsHashtable -ErrorAction Stop
                }
                catch {
                    # Metadata schema test owns this.
                }
            }

            @{
                Directory     = $relDir
                JsonPath      = $jsonPath
                JsonExists    = (Test-Path $jsonPath)
                Body          = $body
                BodyError     = $bodyError
                ParseFailed   = ($null -ne $bodyError) -or ($null -eq $body)
                Format        = $format
                IsArm         = ($format -eq 'arm')
                IsNotebook    = ($format -eq 'notebook')
                MetaPath      = $metaPath
                MetaExists    = (Test-Path $metaPath)
                Meta          = $meta
            }
        })
    }
}

BeforeAll {
    $script:DeploymentTemplateSchema = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
    $script:WorkbookResourceType     = 'Microsoft.Insights/workbooks'
    $script:GuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
}

Describe 'Workbook: <Directory>' -ForEach $script:workbookCases {

    It 'has a workbook.json file' {
        $JsonExists | Should -BeTrue
    }

    It 'workbook.json parses as JSON with a mapping at the root' -Skip:(-not $JsonExists) {
        $BodyError | Should -BeNullOrEmpty
        $Body      | Should -Not -BeNullOrEmpty
        ($Body -is [System.Collections.IDictionary]) | Should -BeTrue
    }

    It 'matches a known workbook format (ARM or gallery notebook)' -Skip:$ParseFailed {
        $Format | Should -Not -Be 'unknown' -Because "workbook.json must be either an ARM deploymentTemplate (top-level 'resources') or a gallery notebook (top-level 'items'); neither was found"
    }

    Context 'ARM deployment template format' -Skip:(-not $IsArm) {
        It 'has the ARM deploymentTemplate schema URL' {
            $Body.ContainsKey('$schema') | Should -BeTrue
            [string]$Body.'$schema' | Should -Be $script:DeploymentTemplateSchema
        }

        It 'has at least one Microsoft.Insights/workbooks resource of kind: shared with required properties' {
            $workbookResources = @($Body.resources | Where-Object {
                $_ -is [System.Collections.IDictionary] -and
                [string]$_.type -eq $script:WorkbookResourceType
            })
            $workbookResources.Count | Should -BeGreaterOrEqual 1 -Because "ARM-format workbook must contain at least one $script:WorkbookResourceType resource"

            foreach ($wb in $workbookResources) {
                [string]$wb.kind | Should -Be 'shared' -Because 'Sentinel workbooks must deploy as kind: shared so they appear in the gallery'
                [string]$wb.name | Should -Match $script:GuidPattern -Because 'workbook resource name must be a GUID (used as the workbook ID)'
                $wb.ContainsKey('properties') | Should -BeTrue
                ($wb.properties -is [System.Collections.IDictionary]) | Should -BeTrue
                foreach ($field in @('displayName', 'serializedData', 'sourceId')) {
                    $wb.properties.ContainsKey($field) | Should -BeTrue -Because "workbook properties.$field is required"
                    ([string]$wb.properties[$field]).Trim() | Should -Not -BeNullOrEmpty -Because "workbook properties.$field must be non-empty"
                }
            }
        }

        It 'serializedData decodes to a workbook notebook' {
            foreach ($wb in @($Body.resources | Where-Object { [string]$_.type -eq $script:WorkbookResourceType })) {
                $serialized = [string]$wb.properties.serializedData
                { ConvertFrom-Json -InputObject $serialized -Depth 64 -ErrorAction Stop | Out-Null } | Should -Not -Throw -Because 'serializedData is itself a JSON-encoded string; if it does not parse, the workbook will fail to load'
                $notebook = ConvertFrom-Json -InputObject $serialized -Depth 64 -ErrorAction Stop
                $notebook.PSObject.Properties.Name | Should -Contain 'version' -Because 'serializedData must decode to a notebook with a version field'
                $notebook.PSObject.Properties.Name | Should -Contain 'items'   -Because 'serializedData must decode to a notebook with an items[] array'
            }
        }
    }

    Context 'Gallery notebook format' -Skip:(-not $IsNotebook) {
        It 'has a non-empty version field' {
            $Body.ContainsKey('version') | Should -BeTrue
            ([string]$Body.version).Trim() | Should -Not -BeNullOrEmpty
        }

        It 'has a non-empty items array' {
            $Body.ContainsKey('items') | Should -BeTrue
            ($Body.items -is [System.Collections.IEnumerable] -and
                -not ($Body.items -is [string]) -and
                -not ($Body.items -is [System.Collections.IDictionary])) | Should -BeTrue
            (@($Body.items).Count -gt 0) | Should -BeTrue -Because 'a gallery workbook with zero items has no content to render'
        }
    }

    Context 'Sibling metadata.json' -Skip:(-not $MetaExists) {
        It 'parses as JSON' {
            $Meta | Should -Not -BeNullOrEmpty
            ($Meta -is [System.Collections.IDictionary]) | Should -BeTrue
        }

        It 'has displayName and sourceId' -Skip:($null -eq $Meta) {
            $Meta.ContainsKey('displayName') | Should -BeTrue
            ([string]$Meta.displayName).Trim() | Should -Not -BeNullOrEmpty
            $Meta.ContainsKey('sourceId') | Should -BeTrue
            ([string]$Meta.sourceId).Trim() | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Workbooks: cross-directory invariants' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $workbookRoot = Join-Path $repoRoot 'Workbooks'

        # Only ARM-format workbooks have a resource GUID we can dedupe on.
        # Gallery notebooks don't expose one (the GUID lives in metadata.json
        # via sourceId, which we already enforce per-directory).
        $script:workbookGuidMap = @{}
        if (Test-Path $workbookRoot) {
            Get-ChildItem -Path $workbookRoot -Directory | ForEach-Object {
                $jsonPath = Join-Path $_.FullName 'workbook.json'
                if (-not (Test-Path $jsonPath)) { return }
                try {
                    $body = Get-Content $jsonPath -Raw | ConvertFrom-Json -Depth 64
                    if ($body.PSObject.Properties.Name -notcontains 'resources') { return }
                    foreach ($wb in @($body.resources)) {
                        if ([string]$wb.type -ne 'Microsoft.Insights/workbooks') { continue }
                        if (-not $wb.name) { continue }
                        $guid = ([string]$wb.name).ToLowerInvariant()
                        if (-not $script:workbookGuidMap.ContainsKey($guid)) { $script:workbookGuidMap[$guid] = @() }
                        $script:workbookGuidMap[$guid] += $_.Name
                    }
                }
                catch {
                    # Per-file test owns parse errors.
                }
            }
        }
    }

    It 'every ARM workbook resource GUID is unique across Workbooks/' {
        $duplicates = $script:workbookGuidMap.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
        if ($duplicates) {
            $report = ($duplicates | ForEach-Object {
                "  GUID $($_.Key) used by:`n    - $($_.Value -join "`n    - ")"
            }) -join "`n"
            throw "Duplicate ARM workbook resource GUIDs found (Sentinel uses the GUID as the resource name; collisions silently overwrite):`n$report"
        }
    }
}
