#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 schema validation for every YAML in AnalyticalRules/ and
    HuntingQueries/. Wired into the PR-validation workflow as a required
    check so PRs are blocked when a rule YAML is malformed or breaks the
    repo's schema rules.

.DESCRIPTION
    Generates one It block per YAML file via -ForEach so the per-file
    pass/fail status surfaces in the GitHub / ADO test report rather than
    collapsing into a single combined assertion.

    YAML parsing happens in BeforeDiscovery so the parsed document is
    embedded in the test case data and -Skip switches can branch on
    properties of that data without racing BeforeAll initialisation.

    Schema rules are deliberately strict so the same YAML deploys cleanly
    through Deploy-CustomContent.ps1 without triggering its own validation
    fallbacks (which would otherwise produce 'enabled: false' deployments
    for fixable input errors).

    Also performs cross-file checks: every analytical rule's `id:` GUID
    must be unique across the entire AnalyticalRules tree.

.NOTES
    Run all tests:
        Invoke-Pester -Path Tests/Test-AnalyticalRuleYaml.Tests.ps1

    Run a focused subset:
        Invoke-Pester -Path Tests/Test-AnalyticalRuleYaml.Tests.ps1 -FullName '*Analytical rule schema*'

    Verbose:
        Invoke-Pester -Path Tests/Test-AnalyticalRuleYaml.Tests.ps1 -Output Detailed

    Prerequisites:
        - Pester 5+ (Install-Module Pester -Force -SkipPublisherCheck)
        - powershell-yaml (auto-installed by the harness if missing)
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module -Name powershell-yaml -Force -Scope CurrentUser -AllowClobber | Out-Null
    }
    Import-Module powershell-yaml -ErrorAction Stop

    function Get-YamlCases {
        param([string]$Subdirectory)
        $path = Join-Path $repoRoot $Subdirectory
        if (-not (Test-Path $path)) { return @() }
        Get-ChildItem -Path $path -Recurse -Filter '*.yaml' -File | ForEach-Object {
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

            $kind = ''
            if ($yaml -and $yaml.ContainsKey('kind')) { $kind = [string]$yaml.kind }

            $isCommunity = ($rel -match '(?i)/Community/')

            @{
                Path         = $_.FullName
                RelativePath = $rel
                Yaml         = $yaml
                ParseError   = $parseError
                Kind         = $kind
                ParseFailed  = ($null -ne $parseError)
                IsScheduled  = ($kind -eq 'Scheduled')
                IsNRT        = ($kind -eq 'NRT')
                IsCommunity  = $isCommunity
            }
        }
    }

    $script:analyticalRuleCases = @(Get-YamlCases -Subdirectory 'AnalyticalRules')
    $script:huntingQueryCases   = @(Get-YamlCases -Subdirectory 'HuntingQueries')
}

BeforeAll {
    # Schema constants. Keep these in sync with Docs/Content/Analytical-Rules.md
    # and the deployer's own tolerances in Scripts/Deploy-CustomContent.ps1.
    $script:ValidSeverities       = @('High', 'Medium', 'Low', 'Informational')
    $script:ValidKinds            = @('Scheduled', 'NRT')
    # Repo style is the short YAML form. Deploy-CustomContent.ps1 expands these
    # to long API form (gt -> GreaterThan etc.) at deploy time. Accepting long
    # forms here would let a YAML drift from the documented schema in
    # Docs/Content/Analytical-Rules.md without the gate noticing.
    $script:ValidTriggerOperators = @('gt', 'lt', 'eq', 'ne')

    # GUID matcher - case-insensitive, 8-4-4-4-12 hex layout.
    $script:GuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

    # ISO-8601 duration matcher. Accepts the common Sentinel forms (PT5M, PT1H,
    # P1D, P1DT12H) without insisting on every section being present, but:
    #   - requires at least one duration component overall (rejects bare 'P')
    #   - rejects a trailing T with no time components (rejects 'PT', 'P1DT')
    $script:IsoDurationPattern = '^P(?=.*\d+[YMWDHS])(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(?!$)(\d+H)?(\d+M)?(\d+S)?)?$'

    # SemVer (just X.Y.Z; no pre-release / build metadata to keep YAML simple).
    $script:SemVerPattern = '^\d+\.\d+\.\d+$'
}

Describe 'Analytical rule schema: <RelativePath>' -ForEach $script:analyticalRuleCases {

    It 'parses as valid YAML with a mapping at the root' {
        $ParseError | Should -BeNullOrEmpty
        $Yaml       | Should -Not -BeNullOrEmpty
        # Required-field assertions below all use $Yaml.ContainsKey(...). If
        # the YAML root parsed to a list or scalar instead of a mapping, those
        # would throw a method-not-found error. Catch that here with a clear
        # assertion message so the failure points at the structural issue.
        ($Yaml -is [System.Collections.IDictionary]) | Should -BeTrue -Because 'analytical rule YAML files must have a mapping at the root so required-field checks can use ContainsKey()'
    }

    Context 'Required fields' -Skip:$ParseFailed {
        It 'has an id field' {
            $Yaml.ContainsKey('id') | Should -BeTrue
            [string]$Yaml.id | Should -Not -BeNullOrEmpty
        }

        It 'has a GUID-format id' -Skip:$IsCommunity {
            # Community rules under AnalyticalRules/Community/ are imported from
            # third-party repos that use deliberately-non-GUID identifiers
            # (e.g. 'a1b2c3d4-0011-4a5b-8c9d-dns011certutil'). The deployer
            # force-disables every community rule and they are opt-in via the
            # SkipCommunityDetections pipeline parameter, so an upstream
            # ID-format quirk should not block the PR gate.
            [string]$Yaml.id | Should -Match $script:GuidPattern
        }

        It 'has a non-empty name' {
            $Yaml.ContainsKey('name') | Should -BeTrue
            ([string]$Yaml.name).Trim() | Should -Not -BeNullOrEmpty
        }

        It 'has a non-empty description' {
            $Yaml.ContainsKey('description') | Should -BeTrue
            ([string]$Yaml.description).Trim() | Should -Not -BeNullOrEmpty
        }

        It 'has a non-empty query' {
            $Yaml.ContainsKey('query') | Should -BeTrue
            ([string]$Yaml.query).Trim() | Should -Not -BeNullOrEmpty
        }

        It 'has a severity from the allowed set' {
            $Yaml.ContainsKey('severity') | Should -BeTrue
            $script:ValidSeverities | Should -Contain ([string]$Yaml.severity)
        }

        It 'has a kind from the allowed set' {
            $Yaml.ContainsKey('kind') | Should -BeTrue
            $script:ValidKinds | Should -Contain ([string]$Yaml.kind)
        }

        It 'has a SemVer-format version' {
            $Yaml.ContainsKey('version') | Should -BeTrue
            [string]$Yaml.version | Should -Match $script:SemVerPattern
        }
    }

    Context 'Scheduled-rule fields' -Skip:(-not $IsScheduled) {
        It 'has a queryFrequency in ISO-8601 duration format' {
            $Yaml.ContainsKey('queryFrequency') | Should -BeTrue
            [string]$Yaml.queryFrequency | Should -Match $script:IsoDurationPattern
        }

        It 'has a queryPeriod in ISO-8601 duration format' {
            $Yaml.ContainsKey('queryPeriod') | Should -BeTrue
            [string]$Yaml.queryPeriod | Should -Match $script:IsoDurationPattern
        }

        It 'has a triggerOperator from the allowed set' {
            $Yaml.ContainsKey('triggerOperator') | Should -BeTrue
            $script:ValidTriggerOperators | Should -Contain ([string]$Yaml.triggerOperator)
        }

        It 'has a non-negative integer triggerThreshold' {
            $Yaml.ContainsKey('triggerThreshold') | Should -BeTrue
            $threshold = $Yaml.triggerThreshold
            ($threshold -as [int]) | Should -Not -BeNullOrEmpty
            [int]$threshold | Should -BeGreaterOrEqual 0
        }
    }

    Context 'NRT-rule fields' -Skip:(-not $IsNRT) {
        It 'does not include scheduling fields' {
            # NRT rules execute on a fixed Microsoft-managed cadence, so any
            # scheduling field in the YAML is rejected by the API on deploy.
            $Yaml.ContainsKey('queryFrequency')   | Should -BeFalse
            $Yaml.ContainsKey('queryPeriod')      | Should -BeFalse
            $Yaml.ContainsKey('triggerOperator')  | Should -BeFalse
            $Yaml.ContainsKey('triggerThreshold') | Should -BeFalse
        }
    }

    Context 'Optional-but-shaped fields' -Skip:$ParseFailed {
        It 'tactics is a list when present' {
            if ($Yaml.ContainsKey('tactics')) {
                # ConvertFrom-Yaml deserialises a YAML list as System.Object[]
                # OR System.Collections.Generic.List[Object] depending on shape.
                # Accept either; reject scalars and hashtables/dictionaries
                # (IDictionary is also IEnumerable so we have to exclude it
                # explicitly, otherwise `tactics: {a: b}` would pass).
                ($Yaml.tactics -is [System.Collections.IEnumerable] -and
                    -not ($Yaml.tactics -is [string]) -and
                    -not ($Yaml.tactics -is [System.Collections.IDictionary])) | Should -BeTrue -Because 'tactics must be a YAML list'
            }
        }

        It 'relevantTechniques is a list when present' {
            if ($Yaml.ContainsKey('relevantTechniques')) {
                ($Yaml.relevantTechniques -is [System.Collections.IEnumerable] -and
                    -not ($Yaml.relevantTechniques -is [string]) -and
                    -not ($Yaml.relevantTechniques -is [System.Collections.IDictionary])) | Should -BeTrue -Because 'relevantTechniques must be a YAML list'
            }
        }

        It 'enabled is boolean when present' {
            if ($Yaml.ContainsKey('enabled')) {
                $Yaml.enabled | Should -BeOfType ([bool])
            }
        }
    }
}

Describe 'Analytical rules: cross-file invariants' {
    BeforeAll {
        # Re-walk the filesystem here rather than relying on script-scope state
        # from BeforeDiscovery. When multiple test files run in a single
        # Invoke-Pester session (e.g. via Invoke-PRValidation.ps1) the
        # $script:analyticalRuleCases variable is not guaranteed to survive
        # across Describe boundaries.
        if (-not (Get-Module -Name powershell-yaml)) {
            Import-Module powershell-yaml -ErrorAction Stop
        }
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $rulesPath = Join-Path $repoRoot 'AnalyticalRules'

        # Community rules under AnalyticalRules/Community/ are imported from
        # third-party repos. David's upstream deliberately reuses ids across
        # categories. Since community rules are opt-in and force-disabled at
        # deploy, an upstream id collision should not block our PR gate.
        # Scope the uniqueness check to in-house rules only.
        $script:idMap = @{}
        if (Test-Path $rulesPath) {
            Get-ChildItem -Path $rulesPath -Recurse -Filter '*.yaml' -File |
                Where-Object { $_.FullName -notmatch '[/\\]Community[/\\]' } |
                ForEach-Object {
                    try {
                        $yaml = ConvertFrom-Yaml (Get-Content $_.FullName -Raw)
                        if (-not $yaml -or -not $yaml.ContainsKey('id')) { return }
                        $id = ([string]$yaml.id).ToLowerInvariant()
                        if (-not $script:idMap.ContainsKey($id)) { $script:idMap[$id] = @() }
                        $rel = ($_.FullName.Substring($repoRoot.Length + 1)) -replace '\\', '/'
                        $script:idMap[$id] += $rel
                    }
                    catch {
                        # Schema tests catch parse errors; skip silently here.
                    }
                }
        }
    }

    It 'every rule id is unique across in-house AnalyticalRules/ (excluding Community/)' {
        $duplicates = $script:idMap.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
        if ($duplicates) {
            $report = ($duplicates | ForEach-Object {
                "  id $($_.Key) used by:`n    - $($_.Value -join "`n    - ")"
            }) -join "`n"
            throw "Duplicate analytical-rule ids found:`n$report"
        }
    }
}

Describe 'Hunting query schema: <RelativePath>' -ForEach $script:huntingQueryCases {

    It 'parses as valid YAML' {
        $ParseError | Should -BeNullOrEmpty
        $Yaml       | Should -Not -BeNullOrEmpty
    }

    Context 'Required fields' -Skip:$ParseFailed {
        It 'has an id field' {
            $Yaml.ContainsKey('id') | Should -BeTrue
            [string]$Yaml.id | Should -Not -BeNullOrEmpty
        }

        It 'has a GUID-format id' {
            [string]$Yaml.id | Should -Match $script:GuidPattern
        }

        It 'has a non-empty name' {
            $Yaml.ContainsKey('name') | Should -BeTrue
            ([string]$Yaml.name).Trim() | Should -Not -BeNullOrEmpty
        }

        It 'has a non-empty description' {
            $Yaml.ContainsKey('description') | Should -BeTrue
            ([string]$Yaml.description).Trim() | Should -Not -BeNullOrEmpty
        }

        It 'has a non-empty query' {
            $Yaml.ContainsKey('query') | Should -BeTrue
            ([string]$Yaml.query).Trim() | Should -Not -BeNullOrEmpty
        }
    }
}
