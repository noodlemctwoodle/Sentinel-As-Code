#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 schema validation for every YAML in Content/DefenderCustomDetections/.

.DESCRIPTION
    Generates one It block per YAML file via -ForEach so per-file pass/fail
    surfaces directly in the PR check UI rather than collapsing into a
    single combined assertion.

    Each file must be in the current Graph detectionRule shape (the one in
    place after Microsoft removed isEnabled, schedule.period, category,
    mitreTechniques, impactedAssets and responseActions on 2026-10-01). The
    field rules come from the deployer itself: every file is run through
    Test-DetectionRule from Deploy/content/Deploy-DefenderDetections.ps1, so
    the CI gate and the deployer cannot disagree. On top of that, each file
    must:

    - carry a client-provided `id` (Graph requires one to create a rule) in
      lowercase kebab-case;
    - use none of the retired field names;
    - name only columns that its query mentions in its entity mappings,
      automated actions and custom details.

    Cross-file invariants: `displayName` is unique (the deployer matches
    existing rules by it) and `id` is unique.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-DefenderDetectionYaml.Tests.ps1

    Validates every Defender custom-detection YAML in the repo.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-DefenderDetectionYaml.Tests.ps1 -Output Detailed

    Runs with per-assertion output, for pinpointing which field of which
    detection failed.

.NOTES
    File:         Tests/Test-DefenderDetectionYaml.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-13
    Version:      0.2.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml (auto-installed if missing)

.LINK
    https://learn.microsoft.com/graph/api/resources/security-detectionrule?view=graph-rest-beta
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module -Name powershell-yaml -Force -Scope CurrentUser -AllowClobber | Out-Null
    }
    Import-Module powershell-yaml -ErrorAction Stop

    $script:defenderCases = @()
    $detectionsRoot = Join-Path $repoRoot 'Content/DefenderCustomDetections'
    if (Test-Path $detectionsRoot) {
        $script:defenderCases = @(Get-ChildItem -Path $detectionsRoot -Recurse -Filter '*.yaml' -File | ForEach-Object {
            $rel = ($_.FullName.Substring($repoRoot.Length + 1)) -replace '\\', '/'
            $yaml = $null
            $parseError = $null
            try {
                $raw = Get-Content -Path $_.FullName -Raw -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace($raw)) { throw 'File is empty' }
                $yaml = ConvertFrom-Yaml $raw
            }
            catch {
                $parseError = $_.Exception.Message
            }

            @{
                Path         = $_.FullName
                RelativePath = $rel
                Yaml         = $yaml
                ParseError   = $parseError
                ParseFailed  = ($null -ne $parseError) -or -not ($yaml -is [System.Collections.IDictionary])
            }
        })
    }
}

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop
    Import-ScriptFunctions -Path (Join-Path $repoRoot 'Deploy/content/Deploy-DefenderDetections.ps1')

    # Field paths Graph removed on 2026-10-01. The deployer still translates
    # them, but repo files must use the current names.
    $script:RetiredFieldPaths = @(
        'isEnabled', 'lastModifiedDateTime', 'queryCondition.lastModifiedDateTime', 'schedule.period',
        'detectionAction.alertTemplate.category', 'detectionAction.alertTemplate.mitreTechniques',
        'detectionAction.alertTemplate.impactedAssets', 'detectionAction.responseActions',
        'detectionAction.organizationalScope.scopeNames', 'detectionAction.organizationalScope.scopeType'
    )

    function Get-YamlPath {
        param([System.Collections.IDictionary]$Yaml, [string]$Path)
        $node = $Yaml
        foreach ($segment in $Path -split '\.') {
            if (-not ($node -is [System.Collections.IDictionary]) -or -not $node.Contains($segment)) { return $false }
            $node = $node[$segment]
        }
        return $true
    }
}

Describe 'Defender custom detection: <RelativePath>' -ForEach $script:defenderCases {

    It 'parses as valid YAML with a mapping at the root' {
        $ParseError | Should -BeNullOrEmpty
        $Yaml       | Should -Not -BeNullOrEmpty
        ($Yaml -is [System.Collections.IDictionary]) | Should -BeTrue -Because 'Defender detection YAML files must have a mapping at the root'
    }

    Context 'Current Graph shape' -Skip:$ParseFailed {
        It 'has a lowercase kebab-case id' {
            [string]$Yaml['id'] | Should -Match '^[a-z0-9]+(-[a-z0-9]+)*$' -Because 'Graph needs a client-provided id to create a rule (lowercase letters, digits and hyphens)'
        }

        It 'uses none of the retired field names' {
            $present = @($script:RetiredFieldPaths | Where-Object { Get-YamlPath -Yaml $Yaml -Path $_ })
            $present | Should -BeNullOrEmpty -Because 'Graph removed these fields on 2026-10-01; see Docs/Content/Defender-Custom-Detections.md for the current names'
        }

        It 'passes the deployer''s rule validation' {
            $issues = @(Test-DetectionRule -Rule $Yaml)
            $issues | Should -BeNullOrEmpty -Because 'Deploy-DefenderDetections.ps1 would skip this file'
        }

        It 'names only columns its query mentions' {
            $query = [string]$Yaml['queryCondition']['queryText']
            $unknown = @(Get-DetectionMappedColumn -Rule $Yaml | Where-Object { $query -cnotmatch "\b$([regex]::Escape($_))\b" })
            $unknown | Should -BeNullOrEmpty -Because 'entity mappings, automated actions and custom details name query result columns; each must be one the query returns'
        }
    }
}

Describe 'Defender custom detections: cross-file invariants' {
    BeforeAll {
        # Re-walk under our own BeforeAll so this Describe is self-contained
        # when run alongside other test files via Invoke-PRValidation.ps1
        # (script-scope state from BeforeDiscovery does not survive across
        # Describe boundaries reliably).
        if (-not (Get-Module -Name powershell-yaml)) {
            Import-Module powershell-yaml -ErrorAction Stop
        }
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $detectionsRoot = Join-Path $repoRoot 'Content/DefenderCustomDetections'
        $script:displayNameMap = @{}
        $script:idMap = @{}

        if (Test-Path $detectionsRoot) {
            Get-ChildItem -Path $detectionsRoot -Recurse -Filter '*.yaml' -File | ForEach-Object {
                try {
                    $yaml = ConvertFrom-Yaml (Get-Content $_.FullName -Raw)
                    if (-not ($yaml -is [System.Collections.IDictionary])) { return }
                    $rel = ($_.FullName.Substring($repoRoot.Length + 1)) -replace '\\', '/'
                    foreach ($pair in @(@{ Map = $script:displayNameMap; Key = 'displayName' }, @{ Map = $script:idMap; Key = 'id' })) {
                        if (-not $yaml.Contains($pair.Key)) { continue }
                        $value = [string]$yaml[$pair.Key]
                        if (-not $pair.Map.ContainsKey($value)) { $pair.Map[$value] = @() }
                        $pair.Map[$value] += $rel
                    }
                }
                catch {
                    # Per-file schema test owns parse errors; skip silently here.
                }
            }
        }

        function Format-Duplicate {
            param([hashtable]$Map)
            ($Map.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 } | ForEach-Object {
                "  '$($_.Key)' used by:`n    - $($_.Value -join "`n    - ")"
            }) -join "`n"
        }
    }

    It 'every Defender displayName is unique across the tree' {
        $report = Format-Duplicate -Map $script:displayNameMap
        if ($report) { throw "Duplicate Defender displayName values found (the deployer matches existing rules by displayName):`n$report" }
    }

    It 'every Defender id is unique across the tree' {
        $report = Format-Duplicate -Map $script:idMap
        if ($report) { throw "Duplicate Defender id values found (Graph rule ids must be unique):`n$report" }
    }
}
