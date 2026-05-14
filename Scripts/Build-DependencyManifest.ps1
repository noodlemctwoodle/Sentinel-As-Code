<#
.SYNOPSIS
    Discovers content dependencies from KQL queries embedded in
    AnalyticalRules / HuntingQueries / SummaryRules / DefenderCustomDetections,
    and produces a dependencies.json manifest. Three operating modes:

      Generate  Walk content, build the manifest, write dependencies.json.
                Author runs this locally after editing rules; commits the
                regenerated file.

      Verify    Walk content, build the manifest in-memory, compare against
                the on-disk dependencies.json. Exits non-zero on drift with
                a structured diff. Used as a CI gate (see PR-validation
                workflow) and as a pre-deploy check (see Sentinel-Deploy.yml).

      Update    Like Verify, but on detected drift commits the regenerated
                manifest to a rolling auto-sync branch and opens (or
                refreshes) a PR. Mirrors the Sentinel-Drift-Detect.yml
                pattern. Run on a daily schedule by sentinel-dependency-update.yml.

.DESCRIPTION
    Discovery uses the helpers exported from Modules/Sentinel.Common.
    Each content file's embedded KQL is scanned for:

      - Watchlist references via _GetWatchlist('alias')
      - External-data URLs from `externaldata(...) [...]` blocks
      - Bare identifiers at data-source positions (start of statement,
        after let X = , after union, after from, inside join/lookup
        subqueries)

    Repo-driven classification (no hard-coded table catalogue):

      1. In-repo functions: built from Parsers/**/*.yaml functionAlias.
         Rules referencing these depend on the parser deploying first.
      2. Microsoft ASIM functions: matched by the regex
         ^(_?ASim|_Im_|im)\w+$ — external, listed for visibility.
      3. Everything else at a data-source position is a table. Tables
         are external (data plane) and not deployable from the repo, so
         no enumeration is required. Custom-log tables (suffix _CL)
         fall into this bucket too.

    Watchlist cross-validation:

      Watchlists discovered in rule queries are matched against the
      repo's Watchlists/*/watchlist.json files. References to watchlists
      not in the repo are flagged as warnings — they will fail at deploy
      time unless the watchlist is provisioned out-of-band.

    Future (Wave 5+): playbook references from automation blocks will be
    cross-validated against Playbooks/**/*.json using the same pattern.

.PARAMETER Mode
    Generate / Verify / Update. See description above.

.PARAMETER RepoPath
    Repository root containing AnalyticalRules/, Parsers/, dependencies.json.
    Defaults to the parent of this script's folder.

.PARAMETER ManifestPath
    Path to the manifest file. Defaults to <RepoPath>/dependencies.json.

.EXAMPLE
    ./Scripts/Build-DependencyManifest.ps1 -Mode Generate

    Regenerates dependencies.json from the current content. Run this
    locally after editing rules.

.EXAMPLE
    ./Scripts/Build-DependencyManifest.ps1 -Mode Verify

    Verifies dependencies.json matches what discovery produces. Exits 0
    on match, 1 on drift (with the diff printed).

.NOTES
    Author:         noodlemctwoodle
    Version:        1.0.0
    Last Updated:   2026-04-29
    Repository:     Sentinel-As-Code
    Requires:       PowerShell 7.2+, powershell-yaml, Sentinel.Common
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Generate', 'Verify', 'Update')]
    [string]$Mode
    ,
    [Parameter(Mandatory = $false)]
    [string]$RepoPath = (Split-Path -Path $PSScriptRoot -Parent)
    ,
    [Parameter(Mandatory = $false)]
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'

if (-not $ManifestPath) {
    $ManifestPath = Join-Path $RepoPath 'dependencies.json'
}

# ---------------------------------------------------------------------------
# Module imports
# ---------------------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Install-Module -Name powershell-yaml -Force -Scope CurrentUser -AllowClobber | Out-Null
}
Import-Module powershell-yaml -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '../Modules/Sentinel.Common/Sentinel.Common.psd1') -Force -ErrorAction Stop

# ---------------------------------------------------------------------------
# Build the in-repo inventory of deployable artifacts
# ---------------------------------------------------------------------------
# The repo IS the source of truth for what's deployable. We build three
# lookups by walking the repo:
#
#   - knownFunctionsLookup: alias -> full path of the Parser .yaml file.
#     Rules referencing these are noted under 'functions' in the manifest;
#     the deployer must deploy the parser before any rule that uses it.
#
#   - knownWatchlistsLookup: alias -> full path of the watchlist.json file.
#     Used to cross-validate _GetWatchlist('alias') references discovered
#     in rule queries — references to watchlists not in the repo are
#     flagged because they will fail at deploy time.
#
#   - knownPlaybooksLookup: name -> full path of the playbook .json file.
#     Built for future use (Wave 5+ automationRule cross-validation).
#
# No hard-coded tables list. Bare identifiers that aren't in the function
# lookup default to 'tables' (external / data plane).
$knownFunctionsLookup  = @{}
$knownWatchlistsLookup = @{}
$knownPlaybooksLookup  = @{}

$parsersRoot = Join-Path $RepoPath 'Parsers'
if (Test-Path $parsersRoot) {
    Get-ChildItem -Path $parsersRoot -Recurse -Filter '*.yaml' -File | ForEach-Object {
        try {
            $y = ConvertFrom-Yaml (Get-Content -Path $_.FullName -Raw)
            if ($y -and $y.functionAlias) {
                $knownFunctionsLookup[[string]$y.functionAlias] = $_.FullName
            }
        }
        catch {
            # Schema test owns parse errors; skip silently here.
        }
    }
}

$watchlistsRoot = Join-Path $RepoPath 'Watchlists'
if (Test-Path $watchlistsRoot) {
    Get-ChildItem -Path $watchlistsRoot -Recurse -Filter 'watchlist.json' -File | ForEach-Object {
        try {
            $w = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json -Depth 16
            if ($w.PSObject.Properties.Name -contains 'watchlistAlias') {
                $knownWatchlistsLookup[[string]$w.watchlistAlias] = $_.FullName
            }
        }
        catch {
            # Watchlist schema test owns parse errors.
        }
    }
}

$playbooksRoot = Join-Path $RepoPath 'Playbooks'
if (Test-Path $playbooksRoot) {
    Get-ChildItem -Path $playbooksRoot -Recurse -Filter '*.json' -File | ForEach-Object {
        # Playbook deploys are templated; the deployable name is the
        # filename without .json. Skipping nested template fragments
        # (parameters.json, etc.) is overkill for this inventory pass.
        $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        $knownPlaybooksLookup[$name] = $_.FullName
    }
}

Write-PipelineMessage "Inventoried in-repo artifacts:" -Level Info
Write-PipelineMessage "  Functions  (Parsers/):    $($knownFunctionsLookup.Count)" -Level Info
Write-PipelineMessage "  Watchlists (Watchlists/): $($knownWatchlistsLookup.Count)" -Level Info
Write-PipelineMessage "  Playbooks  (Playbooks/):  $($knownPlaybooksLookup.Count)" -Level Info

# ---------------------------------------------------------------------------
# Build the manifest from current content
# ---------------------------------------------------------------------------
function Build-Manifest {
    [CmdletBinding()]
    param([string]$RepoRoot)

    $entries = [ordered]@{}
    $missingWatchlists = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)

    # AnalyticalRules + HuntingQueries are the active query-bearing content
    # sets. SummaryRules and DefenderCustomDetections are scanned via
    # Get-ContentKqlQuery if they declare embedded queries; add their
    # roots here when they ship.
    $contentRoots = @('AnalyticalRules', 'HuntingQueries')

    foreach ($subdir in $contentRoots) {
        $root = Join-Path $RepoRoot $subdir
        if (-not (Test-Path $root)) { continue }

        Get-ChildItem -Path $root -Recurse -Filter '*.yaml' -File | Sort-Object FullName | ForEach-Object {
            $rel = ($_.FullName.Substring($RepoRoot.Length + 1)) -replace '\\', '/'
            $deps = Get-ContentDependencies `
                -Path $_.FullName `
                -KnownFunctions $knownFunctionsLookup

            # Cross-validate watchlist references against the repo. Any
            # _GetWatchlist('alias') call that doesn't resolve to a
            # watchlist.json in Watchlists/ is recorded for the warning
            # summary at the end of the run.
            foreach ($w in $deps.watchlists) {
                if (-not $knownWatchlistsLookup.ContainsKey($w)) {
                    if (-not $missingWatchlists.ContainsKey($w)) {
                        $missingWatchlists[$w] = [System.Collections.Generic.List[string]]::new()
                    }
                    $missingWatchlists[$w].Add($rel)
                }
            }

            # Skip files with no discoverable dependencies — they don't need
            # an entry in dependencies.json.
            $hasAny = ($deps.tables.Count + $deps.watchlists.Count + $deps.functions.Count + $deps.externalData.Count) -gt 0
            if (-not $hasAny) { return }

            $entry = [ordered]@{}
            if ($deps.tables.Count       -gt 0) { $entry.tables       = @($deps.tables       | Sort-Object) }
            if ($deps.watchlists.Count   -gt 0) { $entry.watchlists   = @($deps.watchlists   | Sort-Object) }
            if ($deps.functions.Count    -gt 0) { $entry.functions    = @($deps.functions    | Sort-Object) }
            if ($deps.externalData.Count -gt 0) { $entry.externalData = @($deps.externalData | Sort-Object) }

            $entries[$rel] = $entry
        }
    }

    return @{
        Entries           = $entries
        MissingWatchlists = $missingWatchlists
    }
}

function ConvertTo-OrderedManifestJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Entries
        ,
        [Parameter(Mandatory)] [string]$Version
        ,
        [Parameter(Mandatory)] [string]$Description
    )

    $manifest = [ordered]@{
        version      = $Version
        description  = $Description
        dependencies = $Entries
    }
    return ($manifest | ConvertTo-Json -Depth 32)
}

function Compare-Manifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Discovered
        ,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$OnDisk
    )

    $diff = [System.Collections.Generic.List[string]]::new()
    $allKeys = ($Discovered.Keys + $OnDisk.Keys) | Sort-Object -Unique

    foreach ($key in $allKeys) {
        $left  = $OnDisk[$key]
        $right = $Discovered[$key]

        if (-not $left -and $right)  { $diff.Add("ADDED:    $key"); continue }
        if ($left -and -not $right)  { $diff.Add("REMOVED:  $key"); continue }

        # Both sides have the entry — compare each dependency-array key.
        # Use Contains() (works for both Hashtable and OrderedDictionary)
        # rather than ContainsKey (Hashtable-only).
        $changed = $false
        foreach ($depKey in @('tables', 'watchlists', 'functions', 'externalData')) {
            $leftSet  = if ($left.Contains($depKey))  { @($left[$depKey])  | Sort-Object } else { @() }
            $rightSet = if ($right.Contains($depKey)) { @($right[$depKey]) | Sort-Object } else { @() }
            $leftStr  = $leftSet  -join ','
            $rightStr = $rightSet -join ','
            if ($leftStr -ne $rightStr) {
                if (-not $changed) { $diff.Add("CHANGED:  $key"); $changed = $true }
                $diff.Add("    $depKey :  on-disk=[$leftStr]  discovered=[$rightStr]")
            }
        }
    }

    return @{
        HasDrift = ($diff.Count -gt 0)
        Diff     = $diff
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Write-PipelineMessage "Build-DependencyManifest -Mode $Mode" -Level Section
Write-PipelineMessage "  RepoPath:     $RepoPath" -Level Info
Write-PipelineMessage "  ManifestPath: $ManifestPath" -Level Info

$build = Build-Manifest -RepoRoot $RepoPath
$discoveredEntries = $build.Entries
$missingWatchlists = $build.MissingWatchlists

Write-PipelineMessage "" -Level Info
Write-PipelineMessage "Discovered $($discoveredEntries.Count) content items with declared dependencies." -Level Info

if ($missingWatchlists.Count -gt 0) {
    Write-PipelineMessage "" -Level Warning
    Write-PipelineMessage "Watchlist references that do NOT resolve to in-repo Watchlists/:" -Level Warning
    foreach ($alias in ($missingWatchlists.Keys | Sort-Object)) {
        Write-PipelineMessage "  - $alias" -Level Warning
        foreach ($consumer in $missingWatchlists[$alias]) {
            Write-PipelineMessage "      used by: $consumer" -Level Warning
        }
    }
    Write-PipelineMessage "" -Level Warning
    Write-PipelineMessage "  Action: provision these watchlists out-of-band, or add them under Watchlists/." -Level Warning
}

switch ($Mode) {
    'Generate' {
        $json = ConvertTo-OrderedManifestJson -Entries $discoveredEntries `
            -Version '1.0' `
            -Description 'Auto-generated by Scripts/Build-DependencyManifest.ps1. Do not hand-edit; re-run the script after editing rules.'
        Set-Content -Path $ManifestPath -Value $json -Encoding UTF8
        Write-PipelineMessage "Wrote $ManifestPath ($($discoveredEntries.Count) entries)." -Level Success
        exit 0
    }

    'Verify' {
        if (-not (Test-Path $ManifestPath)) {
            Write-PipelineMessage "Manifest not found at $ManifestPath. Run -Mode Generate first." -Level Error
            exit 1
        }
        $onDiskJson = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json -Depth 32 -AsHashtable
        $onDiskEntries = if ($onDiskJson.dependencies) { $onDiskJson.dependencies } else { @{} }

        $cmp = Compare-Manifest -Discovered $discoveredEntries -OnDisk $onDiskEntries
        if ($cmp.HasDrift) {
            # Use Write-Host for diff lines so the CLI output stays clean.
            # Write-PipelineMessage -Level Error uses Write-Error locally,
            # which produces noisy exception-style output for what is just
            # a status report.
            Write-Host ""
            Write-Host "##[error]Dependency manifest is OUT OF SYNC with content. Diff:"
            foreach ($line in $cmp.Diff) { Write-Host "  $line" }
            Write-Host ""
            Write-Host "##[error]Fix: run './Scripts/Build-DependencyManifest.ps1 -Mode Generate' and commit the result."
            exit 1
        }
        Write-PipelineMessage "Manifest matches discovered dependencies." -Level Success
        exit 0
    }

    'Update' {
        if (-not (Test-Path $ManifestPath)) {
            Write-PipelineMessage "Manifest not found at $ManifestPath. Bootstrapping with discovered entries." -Level Warning
            $onDiskEntries = @{}
        }
        else {
            $onDiskJson = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json -Depth 32 -AsHashtable
            $onDiskEntries = if ($onDiskJson.dependencies) { $onDiskJson.dependencies } else { @{} }
        }

        $cmp = Compare-Manifest -Discovered $discoveredEntries -OnDisk $onDiskEntries
        if (-not $cmp.HasDrift) {
            Write-PipelineMessage "Manifest already current — no PR needed." -Level Success
            exit 0
        }

        Write-PipelineMessage "Manifest drift detected:" -Level Warning
        foreach ($line in $cmp.Diff) { Write-PipelineMessage "  $line" -Level Info }

        # Write the updated manifest to disk; the calling pipeline owns the
        # commit + branch + PR step (see sentinel-dependency-update.yml).
        $json = ConvertTo-OrderedManifestJson -Entries $discoveredEntries `
            -Version '1.0' `
            -Description 'Auto-generated by Scripts/Build-DependencyManifest.ps1. Do not hand-edit; re-run the script after editing rules.'
        Set-Content -Path $ManifestPath -Value $json -Encoding UTF8
        Write-PipelineMessage "Updated $ManifestPath. Caller should commit + push + open PR." -Level Success
        exit 0
    }
}
