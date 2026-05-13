#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 schema validation for every Watchlists/{Name}/watchlist.json
    plus its sibling data.csv. Verifies metadata correctness AND the
    JSON-to-CSV invariants the Sentinel deploy logic relies on.

.DESCRIPTION
    A watchlist's `itemsSearchKey` is the column name the deploy logic uses
    to identify each row. If the JSON declares a key that doesn't exist in
    the CSV header, the deploy still succeeds but every KQL query that
    `_GetWatchlist`'s the alias and joins on the key returns empty —
    silently. This suite catches that invariant pre-deploy.

    Per Docs/Content/Watchlists.md the required JSON fields are
    watchlistAlias, displayName, description, provider, itemsSearchKey.
    Provider must be 'Custom'. Watchlist aliases must be unique across the
    tree (Sentinel uses the alias as the resource name).

    Test cases generated per directory rather than per file so JSON-vs-CSV
    pairing checks live in the same test scope.

.NOTES
    Run all tests:
        Invoke-Pester -Path Tests/Test-WatchlistJson.Tests.ps1

    Verbose:
        Invoke-Pester -Path Tests/Test-WatchlistJson.Tests.ps1 -Output Detailed

    Prerequisites:
        - Pester 5+
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot

    $script:watchlistCases = @()
    $watchlistRoot = Join-Path $repoRoot 'Watchlists'
    if (Test-Path $watchlistRoot) {
        $script:watchlistCases = @(Get-ChildItem -Path $watchlistRoot -Directory | ForEach-Object {
            $dir       = $_.FullName
            $relDir    = ($dir.Substring($repoRoot.Length + 1)) -replace '\\', '/'
            $jsonPath  = Join-Path $dir 'watchlist.json'
            $csvPath   = Join-Path $dir 'data.csv'

            $json = $null
            $jsonError = $null
            if (Test-Path $jsonPath) {
                try {
                    $json = Get-Content -Path $jsonPath -Raw -ErrorAction Stop |
                        ConvertFrom-Json -Depth 16 -AsHashtable -ErrorAction Stop
                }
                catch {
                    $jsonError = $_.Exception.Message
                }
            }

            $csvHeaderRaw = ''
            $csvHeader    = @()
            $csvExists    = Test-Path $csvPath
            if ($csvExists) {
                try {
                    $csvHeaderRaw = (Get-Content -Path $csvPath -TotalCount 1 -ErrorAction Stop) ?? ''
                    # Strip surrounding double quotes from each header field
                    # (some CSVs are produced with quoted headers).
                    $csvHeader = @(($csvHeaderRaw -split ',') | ForEach-Object {
                        ($_ -replace '^[ \t]*"|"[ \t]*$', '').Trim()
                    } | Where-Object { $_ })
                }
                catch {
                    # Leave csvHeader empty; the header-resolution test will fail.
                }
            }

            @{
                Directory     = $relDir
                JsonPath      = $jsonPath
                JsonExists    = (Test-Path $jsonPath)
                Json          = $json
                JsonError     = $jsonError
                JsonParseFailed = ($null -ne $jsonError) -or ($null -eq $json)
                CsvPath       = $csvPath
                CsvExists     = $csvExists
                CsvHeader     = $csvHeader
            }
        })
    }
}

BeforeAll {
    $script:WatchlistRequiredFields = @(
        'watchlistAlias',
        'displayName',
        'description',
        'provider',
        'itemsSearchKey'
    )
    $script:WatchlistAliasPattern = '^[A-Za-z][A-Za-z0-9]*$'
}

Describe 'Watchlist: <Directory>' -ForEach $script:watchlistCases {

    It 'has a watchlist.json file' {
        $JsonExists | Should -BeTrue -Because "Watchlists/$Directory must contain a watchlist.json (deploy logic looks for it by name)"
    }

    It 'watchlist.json parses as JSON' -Skip:(-not $JsonExists) {
        $JsonError | Should -BeNullOrEmpty
        $Json      | Should -Not -BeNullOrEmpty
    }

    Context 'Required JSON fields' -Skip:$JsonParseFailed {
        It 'has every required field' {
            foreach ($field in $script:WatchlistRequiredFields) {
                $Json.ContainsKey($field) | Should -BeTrue -Because "watchlist.json must declare '$field' (per Docs/Content/Watchlists.md)"
                ([string]$Json[$field]).Trim() | Should -Not -BeNullOrEmpty -Because "watchlist.json '$field' must be non-empty"
            }
        }

        It 'watchlistAlias is a valid Sentinel resource name' {
            [string]$Json.watchlistAlias | Should -Match $script:WatchlistAliasPattern -Because 'watchlistAlias must start with a letter and contain only letters/digits (Sentinel uses it as the watchlist resource name)'
        }

        It 'provider is "Custom"' {
            [string]$Json.provider | Should -Be 'Custom' -Because 'Sentinel-As-Code only manages Custom-provider watchlists; Microsoft-provided watchlists ship via solutions'
        }
    }

    Context 'CSV pairing' -Skip:$JsonParseFailed {
        It 'has a sibling data.csv' {
            $CsvExists | Should -BeTrue -Because "Watchlists/$Directory must contain a data.csv (deploy uses it as the watchlist's initial content)"
        }

        It 'data.csv header contains the JSON itemsSearchKey column' -Skip:(-not $CsvExists) {
            $key = [string]$Json.itemsSearchKey
            $CsvHeader | Should -Contain $key -Because "watchlist.json declares itemsSearchKey '$key' but data.csv header is [$($CsvHeader -join ', ')]; KQL queries that join on the key will silently return empty if this mismatches"
        }

        It 'data.csv header has no duplicate column names' -Skip:(-not $CsvExists) {
            $unique = @($CsvHeader | Sort-Object -Unique)
            $unique.Count | Should -Be $CsvHeader.Count -Because 'duplicate column names in a watchlist CSV cause KQL ambiguity errors at query time'
        }
    }
}

Describe 'Watchlists: cross-directory invariants' {
    BeforeAll {
        # Self-contained walk so this Describe survives running alongside
        # other test files via Invoke-PRValidation.ps1.
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $watchlistRoot = Join-Path $repoRoot 'Watchlists'

        $script:wlAliasMap = @{}
        if (Test-Path $watchlistRoot) {
            Get-ChildItem -Path $watchlistRoot -Directory | ForEach-Object {
                $jsonPath = Join-Path $_.FullName 'watchlist.json'
                if (-not (Test-Path $jsonPath)) { return }
                try {
                    $j = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json -Depth 16
                    if ($j.PSObject.Properties.Name -contains 'watchlistAlias' -and $j.watchlistAlias) {
                        $alias = [string]$j.watchlistAlias
                        if (-not $script:wlAliasMap.ContainsKey($alias)) { $script:wlAliasMap[$alias] = @() }
                        $script:wlAliasMap[$alias] += $_.Name
                    }
                }
                catch {
                    # Per-directory test owns parse errors.
                }
            }
        }
    }

    It 'every watchlistAlias is unique across Watchlists/' {
        $duplicates = $script:wlAliasMap.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
        if ($duplicates) {
            $report = ($duplicates | ForEach-Object {
                "  alias '$($_.Key)' used by directories:`n    - $($_.Value -join "`n    - ")"
            }) -join "`n"
            throw "Duplicate watchlistAlias values found (Sentinel rejects duplicates at deploy time):`n$report"
        }
    }
}
