#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 schema validation for every JSON in SummaryRules/.

.DESCRIPTION
    Schema follows Docs/Content/Summary-Rules.md. Validates required fields,
    binSize enum membership, destinationTable suffix, and the documented
    KQL restrictions (no time filters, no cross-resource functions, etc).

    KQL restrictions are enforced by string-pattern checks on the query
    body. These are not full KQL parsers but they catch the common
    accidental violations that cause Sentinel to silently produce empty
    bins or reject the query at deploy.

    Cross-file invariant: every rule's `name` is unique across the tree
    (Sentinel uses `name` as the resource name in the PUT URL).

.NOTES
    Run all tests:
        Invoke-Pester -Path Tests/Test-SummaryRuleJson.Tests.ps1
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot

    $script:summaryRuleCases = @()
    $rulesRoot = Join-Path $repoRoot 'SummaryRules'
    if (Test-Path $rulesRoot) {
        $script:summaryRuleCases = @(Get-ChildItem -Path $rulesRoot -Recurse -Filter '*.json' -File | ForEach-Object {
            $rel = ($_.FullName.Substring($repoRoot.Length + 1)) -replace '\\', '/'
            $json = $null
            $parseError = $null
            try {
                $raw = Get-Content -Path $_.FullName -Raw -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace($raw)) { throw 'File is empty' }
                $json = ConvertFrom-Json -InputObject $raw -Depth 32 -AsHashtable -ErrorAction Stop
            }
            catch {
                $parseError = $_.Exception.Message
            }

            @{
                Path         = $_.FullName
                RelativePath = $rel
                Json         = $json
                ParseError   = $parseError
                ParseFailed  = ($null -ne $parseError) -or ($null -eq $json)
            }
        })
    }
}

BeforeAll {
    # Per Docs/Content/Summary-Rules.md "Allowed binSize Values".
    $script:ValidBinSizes = @(20, 30, 60, 120, 180, 360, 720, 1440)

    $script:NameAllowedPattern    = '^[A-Za-z0-9-]+$'
    $script:DestSuffixPattern     = '_CL$'
    $script:BinDelayMaxMinutes    = 1440

    # Per Docs/Content/Summary-Rules.md "KQL Query Restrictions". Each entry
    # is a regex; if any matches, the query violates a documented restriction.
    # Patterns are case-insensitive (the (?i) flag is added at match time).
    $script:KqlForbiddenPatterns = @(
        @{ Name = 'time filter on TimeGenerated';        Pattern = '\bwhere\s+TimeGenerated\s*[<>]' }
        @{ Name = 'time filter via ago()';               Pattern = '\bwhere\s+\w+\s*[<>]\s*ago\s*\(' }
        @{ Name = 'cross-workspace workspaces() lookup'; Pattern = '\bworkspaces\s*\(' }
        @{ Name = 'cross-resource app() lookup';         Pattern = '\bapp\s*\(' }
        @{ Name = 'cross-resource resource() lookup';    Pattern = '\bresource\s*\(' }
        @{ Name = 'cross-resource adx() lookup';         Pattern = '\badx\s*\(' }
        @{ Name = 'pivot operator';                      Pattern = '\|\s*pivot\b' }
        @{ Name = 'bag_unpack plugin';                   Pattern = '\bbag_unpack\s*\(' }
        @{ Name = 'narrow plugin';                       Pattern = '\|\s*narrow\b' }
        @{ Name = 'union *';                             Pattern = '\bunion\s+\*' }
    )
}

Describe 'Summary rule schema: <RelativePath>' -ForEach $script:summaryRuleCases {

    It 'parses as JSON with a mapping at the root' {
        $ParseError | Should -BeNullOrEmpty
        $Json       | Should -Not -BeNullOrEmpty
        ($Json -is [System.Collections.IDictionary]) | Should -BeTrue
    }

    Context 'Required fields' -Skip:$ParseFailed {
        It 'has a name matching the allowed pattern' {
            $Json.ContainsKey('name') | Should -BeTrue
            ([string]$Json.name).Trim() | Should -Not -BeNullOrEmpty
            [string]$Json.name | Should -Match $script:NameAllowedPattern -Because 'summary-rule name is the resource name in the PUT URL; must be alphanumeric + hyphens only'
        }

        It 'has a non-empty query' {
            $Json.ContainsKey('query') | Should -BeTrue
            ([string]$Json.query).Trim() | Should -Not -BeNullOrEmpty
        }

        It 'has a valid binSize' {
            $Json.ContainsKey('binSize') | Should -BeTrue
            $script:ValidBinSizes | Should -Contain ([int]$Json.binSize) -Because "binSize must be one of $($script:ValidBinSizes -join ', ')"
        }

        It 'has a destinationTable ending with _CL' {
            $Json.ContainsKey('destinationTable') | Should -BeTrue
            ([string]$Json.destinationTable) | Should -Match $script:DestSuffixPattern -Because 'destinationTable must use the _CL custom-log suffix'
        }
    }

    Context 'Optional-field shape' -Skip:$ParseFailed {
        It 'binDelay is within the documented maximum when present' {
            if ($Json.ContainsKey('binDelay')) {
                ([int]$Json.binDelay) | Should -BeLessOrEqual $script:BinDelayMaxMinutes -Because "binDelay max is $script:BinDelayMaxMinutes minutes"
                ([int]$Json.binDelay) | Should -BeGreaterOrEqual 0
            }
        }

        It 'binStartTime is on an hour boundary when present' {
            if ($Json.ContainsKey('binStartTime')) {
                [string]$Json.binStartTime | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:00:00Z$' -Because 'binStartTime must fall on a whole hour boundary (YYYY-MM-DDTHH:00:00Z)'
            }
        }

        It 'displayName is non-empty when present' {
            if ($Json.ContainsKey('displayName')) {
                ([string]$Json.displayName).Trim() | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'KQL restrictions' -Skip:$ParseFailed {
        It 'query does not violate any documented KQL restriction' {
            $query = [string]$Json.query
            foreach ($rule in $script:KqlForbiddenPatterns) {
                $regex = [regex]::new($rule.Pattern, 'IgnoreCase')
                $regex.IsMatch($query) | Should -BeFalse -Because "summary-rule query contains a $($rule.Name) which is not supported (per Docs/Content/Summary-Rules.md 'KQL Query Restrictions')"
            }
        }
    }
}

Describe 'Summary rules: cross-file invariants' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $rulesRoot = Join-Path $repoRoot 'SummaryRules'

        $script:summaryNameMap = @{}
        if (Test-Path $rulesRoot) {
            Get-ChildItem -Path $rulesRoot -Recurse -Filter '*.json' -File | ForEach-Object {
                try {
                    $j = Get-Content $_.FullName -Raw | ConvertFrom-Json -Depth 32
                    if ($j.PSObject.Properties.Name -notcontains 'name') { return }
                    $name = [string]$j.name
                    if (-not $script:summaryNameMap.ContainsKey($name)) { $script:summaryNameMap[$name] = @() }
                    $rel = ($_.FullName.Substring($repoRoot.Length + 1)) -replace '\\', '/'
                    $script:summaryNameMap[$name] += $rel
                }
                catch {
                    # Per-file test owns parse errors.
                }
            }
        }
    }

    It 'every summary-rule name is unique across SummaryRules/' {
        $duplicates = $script:summaryNameMap.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
        if ($duplicates) {
            $report = ($duplicates | ForEach-Object {
                "  '$($_.Key)' used by:`n    - $($_.Value -join "`n    - ")"
            }) -join "`n"
            throw "Duplicate summary-rule name values found (Sentinel uses name as the resource name; collisions silently overwrite):`n$report"
        }
    }
}
