#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 validation for the repo-root dependencies.json manifest and the
    cross-content invariants it implies.

.DESCRIPTION
    `dependencies.json` is the single declarative manifest of which Sentinel
    content depends on which prerequisites (tables, watchlists, parser
    functions, external data feeds). The deploy script reads it before every
    deploy run to decide whether each item can deploy enabled, deploy
    disabled, or fail outright. If the manifest goes out of sync with the
    actual content tree (broken file paths, watchlist aliases that no longer
    exist, missing parser references) the gate is silently weaker than it
    looks.

    This suite enforces:

    - Top-level shape: `version`, `description`, `dependencies` keys present.
    - Path resolution: every key under `dependencies` resolves to a real file
      on disk under AnalyticalRules/ or HuntingQueries/.
    - Watchlist resolution: every `watchlists[]` alias declared by any entry
      maps to a real `Watchlists/*/watchlist.json` whose `watchlistAlias`
      field matches.
    - Function resolution: every `functions[]` alias maps to a real
      `Parsers/*.yaml` `functionAlias`, OR matches the known-external pattern
      for Microsoft-provided ASIM parsers.

    Generates per-entry It blocks via -ForEach so per-file failures surface
    cleanly in the PR check UI.

.NOTES
    Run all tests:
        Invoke-Pester -Path Tests/Test-DependencyManifest.Tests.ps1

    Verbose:
        Invoke-Pester -Path Tests/Test-DependencyManifest.Tests.ps1 -Output Detailed

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

    $manifestPath = Join-Path $repoRoot 'dependencies.json'
    $script:manifestExists = Test-Path $manifestPath

    $script:manifest = $null
    $script:manifestParseError = $null
    if ($script:manifestExists) {
        try {
            $script:manifest = Get-Content -Path $manifestPath -Raw -ErrorAction Stop |
                ConvertFrom-Json -Depth 32 -AsHashtable -ErrorAction Stop
        }
        catch {
            $script:manifestParseError = $_.Exception.Message
        }
    }

    # Build per-entry test cases for path resolution. Each case carries the
    # declared path (relative to repo root) and the parsed dependency block.
    $script:entryCases = @()
    if ($script:manifest -and $script:manifest.ContainsKey('dependencies')) {
        foreach ($key in $script:manifest['dependencies'].Keys) {
            $entry = $script:manifest['dependencies'][$key]
            $script:entryCases += @{
                Key       = $key
                Entry     = $entry
                AbsPath   = (Join-Path $repoRoot $key)
                IsCommunity = ($key -match '(?i)/Community/')
            }
        }
    }

    # Aggregate every watchlist + function alias referenced from the manifest.
    # One test case per distinct alias, with a list of citing entries so the
    # failure message points at exactly which dependency declared a broken
    # reference.
    function Get-AliasCases {
        param([string]$ArrayKey)
        $bucket = @{}
        if ($script:manifest -and $script:manifest.ContainsKey('dependencies')) {
            foreach ($key in $script:manifest['dependencies'].Keys) {
                $entry = $script:manifest['dependencies'][$key]
                if ($entry -is [System.Collections.IDictionary] -and $entry.ContainsKey($ArrayKey)) {
                    foreach ($alias in @($entry[$ArrayKey])) {
                        if ([string]::IsNullOrWhiteSpace($alias)) { continue }
                        if (-not $bucket.ContainsKey($alias)) { $bucket[$alias] = @() }
                        $bucket[$alias] += $key
                    }
                }
            }
        }
        $cases = @()
        foreach ($alias in $bucket.Keys) {
            $cases += @{ Alias = $alias; CitedBy = $bucket[$alias] }
        }
        return @($cases)
    }

    $script:watchlistAliasCases = Get-AliasCases -ArrayKey 'watchlists'
    $script:functionAliasCases  = Get-AliasCases -ArrayKey 'functions'
}

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot

    if (-not (Get-Module -Name powershell-yaml)) {
        Import-Module powershell-yaml -ErrorAction Stop
    }

    # Lookup of known watchlistAlias values declared by Watchlists/*/watchlist.json.
    # Built once in BeforeAll so per-test assertions are O(1) lookups.
    $script:knownWatchlistAliases = @{}
    $watchlistRoot = Join-Path $repoRoot 'Watchlists'
    if (Test-Path $watchlistRoot) {
        Get-ChildItem -Path $watchlistRoot -Recurse -Filter 'watchlist.json' -File | ForEach-Object {
            try {
                $wl = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json -Depth 16
                if ($wl.PSObject.Properties.Name -contains 'watchlistAlias' -and $wl.watchlistAlias) {
                    $script:knownWatchlistAliases[[string]$wl.watchlistAlias] = $_.FullName
                }
            }
            catch {
                # Schema test for watchlists owns parse errors; skip silently here.
            }
        }
    }

    # Lookup of known functionAlias values declared by Parsers/*.yaml.
    $script:knownFunctionAliases = @{}
    $parsersRoot = Join-Path $repoRoot 'Parsers'
    if (Test-Path $parsersRoot) {
        Get-ChildItem -Path $parsersRoot -Recurse -Filter '*.yaml' -File | ForEach-Object {
            try {
                $p = ConvertFrom-Yaml (Get-Content -Path $_.FullName -Raw)
                if ($p -and $p.ContainsKey('functionAlias') -and $p['functionAlias']) {
                    $script:knownFunctionAliases[[string]$p['functionAlias']] = $_.FullName
                }
            }
            catch {
                # Parser-schema test owns parse errors; skip silently here.
            }
        }
    }

    # Microsoft-provided functions that won't appear under Parsers/ but are
    # still legitimate references. Add to this list when adopting a new
    # Microsoft Sentinel solution that ships its own KQL functions.
    $script:knownExternalFunctions = @(
        # ASIM unified parsers (https://learn.microsoft.com/azure/sentinel/normalization)
        'ASimDnsActivityLogs',
        'ASimAuthenticationActivityLogs',
        'ASimWebSessionLogs',
        'ASimNetworkSessionLogs',
        'ASimFileEventLogs',
        'ASimProcessEventLogs',
        'ASimRegistryEventLogs',
        'ASimUserManagementActivityLogs',
        'ASimAuditEventLogs',
        'ASimDhcpEventLogs'
    )
    # Pattern fallback for ASIM parser names we have not enumerated yet.
    $script:asimFunctionPattern = '^_?ASim\w+$|^_Im_\w+$|^im\w+$'
}

Describe 'Dependency manifest: top-level shape' {
    BeforeAll {
        # Re-load the manifest in this Describe's own BeforeAll. Script-scope
        # state set in the file-level BeforeDiscovery does not reliably survive
        # into Describe-scoped runtime when multiple Pester test files run in
        # one Invoke-Pester session (same pattern as the cross-file-invariants
        # block in Test-AnalyticalRuleYaml.Tests.ps1).
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $manifestPath = Join-Path $repoRoot 'dependencies.json'
        $script:topShapeExists = Test-Path $manifestPath
        $script:topShapeManifest = $null
        $script:topShapeParseError = $null
        if ($script:topShapeExists) {
            try {
                $script:topShapeManifest = Get-Content -Path $manifestPath -Raw -ErrorAction Stop |
                    ConvertFrom-Json -Depth 32 -AsHashtable -ErrorAction Stop
            }
            catch {
                $script:topShapeParseError = $_.Exception.Message
            }
        }
    }

    It 'exists at repo root' {
        $script:topShapeExists | Should -BeTrue -Because 'dependencies.json must live at the repo root for Deploy-CustomContent.ps1 to find it'
    }

    It 'parses as JSON' {
        $script:topShapeParseError | Should -BeNullOrEmpty
        $script:topShapeManifest   | Should -Not -BeNullOrEmpty
    }

    It 'has a version field' {
        $script:topShapeManifest | Should -Not -BeNullOrEmpty
        $script:topShapeManifest.ContainsKey('version') | Should -BeTrue
        [string]$script:topShapeManifest['version']     | Should -Not -BeNullOrEmpty
    }

    It 'has a description field' {
        $script:topShapeManifest | Should -Not -BeNullOrEmpty
        $script:topShapeManifest.ContainsKey('description') | Should -BeTrue
    }

    It 'has a dependencies object' {
        $script:topShapeManifest | Should -Not -BeNullOrEmpty
        $script:topShapeManifest.ContainsKey('dependencies') | Should -BeTrue
        ($script:topShapeManifest['dependencies'] -is [System.Collections.IDictionary]) | Should -BeTrue -Because '"dependencies" must be a JSON object keyed by content path'
    }
}

Describe 'Dependency entry path resolves: <Key>' -ForEach $script:entryCases {

    It 'declared key points at a real file on disk' {
        Test-Path $AbsPath | Should -BeTrue -Because "dependencies.json declares '$Key' but that path does not exist on disk; either the file was moved/deleted or the manifest entry is stale"
    }

    Context 'Entry shape' {
        It 'is a JSON object (not a scalar or list)' {
            ($Entry -is [System.Collections.IDictionary]) | Should -BeTrue -Because 'each manifest entry must be an object; supported keys are watchlists / tables / functions / externalData'
        }

        It 'uses only recognised dependency keys' {
            $allowed = @('watchlists', 'tables', 'functions', 'externalData')
            foreach ($subKey in $Entry.Keys) {
                $allowed | Should -Contain $subKey -Because "unknown dependency key '$subKey' in '$Key'; permitted keys are $($allowed -join ', ')"
            }
        }

        It 'has every dependency value as an array' {
            foreach ($subKey in $Entry.Keys) {
                $val = $Entry[$subKey]
                ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string]) -and -not ($val -is [System.Collections.IDictionary])) | Should -BeTrue -Because "'$Key' -> '$subKey' must be a JSON array, not a scalar"
            }
        }
    }
}

Describe 'Watchlist alias resolves: <Alias>' -ForEach $script:watchlistAliasCases {

    It 'maps to a real Watchlists/*/watchlist.json' {
        $script:knownWatchlistAliases.ContainsKey($Alias) | Should -BeTrue -Because "watchlist alias '$Alias' is referenced by $($CitedBy.Count) dependency entr(y/ies) (e.g. $($CitedBy[0])) but no Watchlists/*/watchlist.json declares this watchlistAlias"
    }
}

Describe 'Function alias resolves: <Alias>' -ForEach $script:functionAliasCases {

    It 'maps to a Parsers/*.yaml functionAlias or a known Microsoft-provided function' {
        $isInternal = $script:knownFunctionAliases.ContainsKey($Alias)
        $isExternal = ($script:knownExternalFunctions -contains $Alias) -or ($Alias -match $script:asimFunctionPattern)
        ($isInternal -or $isExternal) | Should -BeTrue -Because "function '$Alias' is referenced by $($CitedBy.Count) dependency entr(y/ies) (e.g. $($CitedBy[0])) but it is neither declared in Parsers/*.yaml nor in the known-external list. If this is a new Microsoft-provided function, add it to `$script:knownExternalFunctions in this test file."
    }
}
