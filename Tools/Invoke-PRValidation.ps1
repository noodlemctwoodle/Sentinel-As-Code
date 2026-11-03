#Requires -Version 7.2

<#
.SYNOPSIS
    PR-validation entry-point. Runs every Pester suite under Tests/ against the
    repository, emits a JUnit XML test report, and exits non-zero if any test
    fails, any BeforeAll or AfterAll block fails, or any suite cannot be
    loaded. Called by both the GitHub Actions PR workflow and the Azure DevOps
    PR pipeline so the gating logic stays in one place.

.DESCRIPTION
    What this validates:

    - Drift-detector pure functions (Test-SentinelRuleDrift.Tests.ps1):
      Compare-SentinelRule, Update-RuleYamlFile, Get-LineDiff,
      Resolve-RuleSource, Save-AbsorbedRule, New-AbsorbedRuleYaml,
      ConvertTo-FileSlug.

    - YAML schema (Test-AnalyticalRuleYaml.Tests.ps1):
      every YAML under Content/AnalyticalRules/ and Content/HuntingQueries/ parses, has the
      required fields with the right shape, uses kind-appropriate scheduling
      fields, and the 'id:' GUIDs are unique across the analytical-rule tree.

    Output artefacts (always emitted, even on failure):

    - NUnit-2.5 XML at $TestResultsPath
        Pester's native test-result format. ADO's PublishTestResults@2 ingests
        it directly via testResultsFormat: NUnit. The GitHub workflow uses
        EnricoMi/publish-unit-test-result-action with files: test-results/*.xml,
        which auto-detects the NUnit schema.

    Exit codes:
        0  every test passed
        1  one or more tests failed, a BeforeAll or AfterAll block failed,
           or a suite could not be loaded (the calling pipeline must fail
           the PR check on a non-zero exit)

    Pester counts the three apart. A suite whose BeforeDiscovery or
    top-level code throws, or that does not parse, is a failed container:
    none of its tests is discovered, so it adds nothing to FailedCount. A
    failed AfterAll is a failed block, and its tests still pass. Before
    1.1.0 the script read FailedCount alone, so such a suite was skipped
    and the gate passed.

.PARAMETER RepoPath
    Repository root. Defaults to the parent of the Tools/ folder this
    script lives in.

.PARAMETER TestResultsPath
    Destination path for the JUnit XML report. Defaults to
    {RepoPath}/test-results/pester-results.xml. The folder is created if
    missing.

.PARAMETER TestNameFilter
    Optional Pester full-name filter. Defaults to running every Tests/*.Tests.ps1
    file. Useful for local debugging:
        ./Tools/Invoke-PRValidation.ps1 -TestNameFilter '*Resolve-RuleSource*'

.PARAMETER InstallModules
    Install Pester and powershell-yaml at the user scope before running tests.
    Default true (matches CI behaviour). Pass -InstallModules:$false locally if
    the modules are already pinned via your profile.

.EXAMPLE
    ./Tools/Invoke-PRValidation.ps1

    Runs every Pester suite under Tests/ and writes JUnit XML to
    test-results/pester-results.xml. Exits 1 on the first failed assertion.

.EXAMPLE
    ./Tools/Invoke-PRValidation.ps1 -TestNameFilter '*Analytical rule schema*'

    Runs only the YAML-schema tests. Useful when iterating on a single rule
    file locally.

.NOTES
    File:           Tools/Invoke-PRValidation.ps1
    Repository:     Sentinel-As-Code
    Author:         noodlemctwoodle
    Website:        https://sentinel.blog
    Created:        2026-04-29
    Version:        1.1.0
    Last Updated:   2026-11-03
    Requires:       PowerShell 7.2+, Pester 5+ and powershell-yaml (both auto-installed if missing)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoPath = (Split-Path -Path $PSScriptRoot -Parent)
    ,
    [Parameter(Mandatory = $false)]
    [string]$TestResultsPath
    ,
    [Parameter(Mandatory = $false)]
    [string]$TestNameFilter
    ,
    [Parameter(Mandatory = $false)]
    [bool]$InstallModules = $true
)

$ErrorActionPreference = 'Stop'

# Intentionally NOT setting Set-StrictMode here. The Pester process runs
# under whatever strict-mode setting the suite-level BeforeAll establishes;
# leaking strict mode from this orchestrator would force every imported
# script (some of which use ?? against non-existent properties by design)
# into strict-mode behaviour and break tests that pass standalone.

if (-not $TestResultsPath) {
    $TestResultsPath = Join-Path -Path $RepoPath -ChildPath 'test-results/pester-results.xml'
}

$resultsDir = Split-Path -Path $TestResultsPath -Parent
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}

# ---------------------------------------------------------------------------
# Module setup. Both pipelines start from a clean PowerShell host.
# ---------------------------------------------------------------------------
if ($InstallModules) {
    Write-Host '##[section]Installing test dependencies'

    if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.0.0' })) {
        Install-Module -Name Pester -MinimumVersion '5.0.0' -Force -SkipPublisherCheck -Scope CurrentUser -AllowClobber | Out-Null
    }
    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module -Name powershell-yaml -Force -Scope CurrentUser -AllowClobber | Out-Null
    }
}

Import-Module Pester -MinimumVersion '5.0.0' -ErrorAction Stop
Import-Module powershell-yaml -ErrorAction Stop

# ---------------------------------------------------------------------------
# Pester configuration. NUnitXml is what both GitHub and ADO ingest natively;
# we pick JUnit-compatible NUnit2.5 output for broadest compatibility.
# ---------------------------------------------------------------------------
$testsRoot = Join-Path -Path $RepoPath -ChildPath 'Tests'
if (-not (Test-Path $testsRoot)) {
    Write-Error "Tests folder not found: $testsRoot"
    exit 1
}

$config = New-PesterConfiguration
$config.Run.Path        = $testsRoot
$config.Run.PassThru    = $true
$config.Run.Exit        = $false   # we handle exit code ourselves
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled       = $true
$config.TestResult.OutputFormat  = 'NUnitXml'
$config.TestResult.OutputPath    = $TestResultsPath

if ($TestNameFilter) {
    $config.Filter.FullName = $TestNameFilter
}

Write-Host "##[section]Running Pester tests under: $testsRoot"
Write-Host "JUnit/NUnit XML report: $TestResultsPath"
if ($TestNameFilter) { Write-Host "Filter: $TestNameFilter" }

$result = Invoke-Pester -Configuration $config

# ---------------------------------------------------------------------------
# Summary + exit code.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '##[section]Test summary'
Write-Host ("  Passed:       {0}" -f $result.PassedCount)
Write-Host ("  Failed:       {0}" -f $result.FailedCount)
Write-Host ("  Skipped:      {0}" -f $result.SkippedCount)
Write-Host ("  Inconclusive: {0}" -f $result.InconclusiveCount)
Write-Host ("  Failed setup or teardown blocks: {0}" -f $result.FailedBlocksCount)
Write-Host ("  Suites that could not be loaded: {0}" -f $result.FailedContainersCount)
Write-Host ("  Duration:     {0}" -f $result.Duration)

# Every line of an error, each marked so the pipeline annotates it.
function Write-PRValidationError {
    param([object[]] $ErrorRecord)
    foreach ($record in @($ErrorRecord | Where-Object { $_ })) {
        $text = if ($record.PSObject.Properties['DisplayErrorMessage'] -and $record.DisplayErrorMessage) { $record.DisplayErrorMessage } else { $record.Exception.Message }
        foreach ($line in ([string]$text -split '\r?\n')) { Write-Host ('##[error]    {0}' -f $line) }
    }
}

if ($result.FailedContainersCount -gt 0) {
    Write-Host '##[error]One or more Pester suites could not be loaded, so none of their tests ran.'
    foreach ($container in $result.FailedContainers) {
        Write-Host ('##[error]  {0}' -f $container.Item)
        Write-PRValidationError -ErrorRecord $container.ErrorRecord
    }
}

if ($result.FailedBlocksCount -gt 0) {
    Write-Host '##[error]One or more BeforeAll or AfterAll blocks failed.'
    foreach ($block in $result.FailedBlocks) {
        Write-Host ('##[error]  {0} ({1})' -f $block.ExpandedPath, $block.BlockContainer.Item)
        Write-PRValidationError -ErrorRecord $block.ErrorRecord
    }
}

if ($result.FailedCount -gt 0) {
    Write-Host '##[error]One or more Pester tests failed. PR cannot merge until they pass.'
    foreach ($failedTest in $result.Failed) {
        Write-Host ('##[error]  {0}' -f $failedTest.ExpandedPath)
        if ($failedTest.ErrorRecord) {
            Write-Host ('##[error]    {0}' -f $failedTest.ErrorRecord.DisplayErrorMessage)
        }
    }
}

if (($result.FailedCount + $result.FailedBlocksCount + $result.FailedContainersCount) -gt 0) {
    exit 1
}

Write-Host '##[section]All Pester tests passed.'
exit 0
