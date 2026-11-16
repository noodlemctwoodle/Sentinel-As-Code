#Requires -Version 7.2
#Requires -Modules PSScriptAnalyzer

<#
.SYNOPSIS
    Rewrites the PSScriptAnalyzer baseline with each file's current finding
    count.

.DESCRIPTION
    Tests/Test-PSScriptAnalyzer.Tests.ps1 lints every PowerShell file in the
    repository and allows a file no more findings than
    Tests/PSScriptAnalyzer/PSScriptAnalyzerBaseline.psd1 records for it (zero
    when it is not listed). The count may only go down: when a file improves,
    the test fails until the baseline is lowered, so the gain is kept.

    Run this after fixing findings to lower the baseline. Do not run it to make
    new findings pass: a file's count must never go up, and a new file must be
    clean. Only files with findings are written.

.PARAMETER RepositoryPath
    The repository root. Defaults to the parent of the Tools folder.

.EXAMPLE
    ./Tools/Update-PSScriptAnalyzerBaseline.ps1

    Lints every PowerShell file and rewrites the baseline.

.NOTES
    File:         Tools/Update-PSScriptAnalyzerBaseline.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.2+, PSScriptAnalyzer 1.25.0
#>

[CmdletBinding(PositionalBinding = $false, SupportsShouldProcess)]
param (
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryPath = (Split-Path -Path $PSScriptRoot -Parent)
)

Set-StrictMode -Version 'Latest'
$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path -Path $RepositoryPath -ChildPath 'Tests/_helpers/PSScriptAnalyzerLint.psm1') -Force
Initialize-RepositoryLint -RepositoryRoot $RepositoryPath

$counts = [ordered]@{}
foreach ($file in @(Get-RepositoryPowerShellFile -RepositoryRoot $RepositoryPath | Sort-Object -Property 'Path')) {
    $findings = @(Invoke-RepositoryLint -File $file -RepositoryRoot $RepositoryPath)
    if ($findings.Count -gt 0) {
        $counts[$file.Path] = $findings.Count
    }
}

$width = 0
foreach ($path in $counts.Keys) {
    $width = [Math]::Max($width, $path.Length + 2)
}
$entries = foreach ($path in $counts.Keys) {
    '    {0} = {1}' -f ("'$path'").PadRight($width), $counts[$path]
}
$header = @(
    '@{'
    '    # Allowed PSScriptAnalyzer findings per file (main profile plus the'
    '    # formatting pass). A file that is not listed must be clean. Counts may'
    '    # only go down. Regenerate with ./Tools/Update-PSScriptAnalyzerBaseline.ps1'
    '    # after fixing findings; never to let new findings in.'
)
$content = @($header) + @($entries) + @('}')

$baselinePath = Join-Path -Path $RepositoryPath -ChildPath 'Tests/PSScriptAnalyzer/PSScriptAnalyzerBaseline.psd1'
if ($PSCmdlet.ShouldProcess($baselinePath, 'Write the PSScriptAnalyzer baseline')) {
    Set-Content -LiteralPath $baselinePath -Value $content -Encoding 'utf8NoBOM'
    $total = 0
    foreach ($value in $counts.Values) {
        $total = $total + $value
    }
    Write-Information -MessageData "Baseline written: $($counts.Count) files, $total findings." -InformationAction 'Continue'
}
