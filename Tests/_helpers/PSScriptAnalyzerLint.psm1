#Requires -Version 7.6

<#
.SYNOPSIS
    Shared repository lint for PSScriptAnalyzer: which files are checked,
    which profile each one uses, and the findings for a file.

.DESCRIPTION
    Used by Tests/Test-PSScriptAnalyzer.Tests.ps1 (the PR gate) and
    Tools/Update-PSScriptAnalyzerBaseline.ps1 (which rewrites the baseline),
    so the two can never disagree about a file's findings.

    Every .ps1, .psm1 and .psd1 in the repository is checked, except files git
    ignores. Files under Tests/ use PSScriptAnalyzerTestSettings.psd1, the rest
    PSScriptAnalyzerSettings.psd1; every file then gets a second pass with
    PSScriptAnalyzerFormatting.psd1, which checks command-name casing on its own
    (PSScriptAnalyzer #1708). Files are analysed one per call: a single call
    over many files can hit the same PSScriptAnalyzer 1.25 threading crash.
    Initialize-RepositoryLint warms PSScriptAnalyzer's command cache first:
    the first analysis of a module that calls Export-ModuleMember in a fresh
    process can crash the same way, and never does once the cache is warm.

.NOTES
    File:         Tests/_helpers/PSScriptAnalyzerLint.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+, PSScriptAnalyzer 1.25.0
#>

Set-StrictMode -Version 'Latest'

# The baseline's finding counts are exact for this version; CI pins it
# (PSSA_VERSION in .github/workflows/pr-validation.yml).
$script:PinnedVersion = [version]'1.25.0'

function Get-RepositoryPowerShellFile {
    <#
    .SYNOPSIS
        Lists every PowerShell file in the repository with the profile it is
        linted with.

    .DESCRIPTION
        Uses git (tracked files plus untracked files that are not ignored) so
        generated output and ignored folders are skipped. Without git it falls
        back to walking the folder, skipping .git and node_modules.

    .PARAMETER RepositoryRoot
        The repository root.

    .OUTPUTS
        [pscustomobject] Path (repository-relative, forward slashes), FullName
        and Settings (the main profile for the file).
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    $profileFolder = Join-Path -Path $RepositoryRoot -ChildPath 'Tests/PSScriptAnalyzer'
    $patterns = @('*.ps1', '*.psm1', '*.psd1')
    $relative = @()
    if (Get-Command -Name 'git' -ErrorAction SilentlyContinue) {
        $tracked = @(& git -C $RepositoryRoot ls-files -- @patterns)
        $untracked = @(& git -C $RepositoryRoot ls-files --others --exclude-standard -- @patterns)
        $relative = @($tracked + $untracked | Sort-Object -Unique)
    }
    if ($relative.Count -eq 0) {
        $relative = foreach ($file in Get-ChildItem -Path $RepositoryRoot -Recurse -File -Include $patterns) {
            $path = [System.IO.Path]::GetRelativePath($RepositoryRoot, $file.FullName).Replace('\', '/')
            if ($path -notmatch '(^|/)(\.git|node_modules)/') {
                $path
            }
        }
    }

    foreach ($path in $relative) {
        $fullName = Join-Path -Path $RepositoryRoot -ChildPath $path
        if (-not (Test-Path -LiteralPath $fullName)) {
            continue
        }
        $profileName = if ($path -like 'Tests/*') { 'PSScriptAnalyzerTestSettings.psd1' } else { 'PSScriptAnalyzerSettings.psd1' }
        [pscustomobject]@{
            Path     = $path
            FullName = $fullName
            Settings = Join-Path -Path $profileFolder -ChildPath $profileName
        }
    }
}

function Get-RepositoryLintVersion {
    <#
    .SYNOPSIS
        Returns the PSScriptAnalyzer version the baseline was generated with.

    .OUTPUTS
        [version] The pinned version.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([version])]
    param ()

    return $script:PinnedVersion
}

function Initialize-RepositoryLint {
    <#
    .SYNOPSIS
        Loads the pinned PSScriptAnalyzer and warms its command cache before
        any real file is linted.

    .DESCRIPTION
        Imports PSScriptAnalyzer at the pinned version when it is installed,
        so a newer copy cannot report different counts against the baseline.

        PSScriptAnalyzer 1.25 resolves Export-ModuleMember's parameters from
        several rule threads at once, and on the first analysis in a fresh
        process that can throw a NullReferenceException. Analysing a small
        throwaway module first, with each profile, fills the cache; failures
        of the throwaway analysis are retried and never reported.

    .PARAMETER RepositoryRoot
        The repository root.

    .OUTPUTS
        None.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    $available = @(Get-Module -ListAvailable -Name 'PSScriptAnalyzer' | Where-Object -FilterScript { $_.Version -eq $script:PinnedVersion })
    if ($available.Count -gt 0) {
        Import-Module -Name 'PSScriptAnalyzer' -RequiredVersion $script:PinnedVersion -ErrorAction Stop
    } else {
        Write-Warning -Message "PSScriptAnalyzer $($script:PinnedVersion) is not installed; the baseline counts are for that version."
    }

    $warmup = @'
function Get-LintWarmup {
    [CmdletBinding()]
    param ()
}
Export-ModuleMember -Function 'Get-LintWarmup'
'@
    $profileFolder = Join-Path -Path $RepositoryRoot -ChildPath 'Tests/PSScriptAnalyzer'
    foreach ($name in @('PSScriptAnalyzerSettings.psd1', 'PSScriptAnalyzerTestSettings.psd1', 'PSScriptAnalyzerFormatting.psd1')) {
        $settings = Join-Path -Path $profileFolder -ChildPath $name
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $null = Invoke-ScriptAnalyzer -ScriptDefinition $warmup -Settings $settings -ErrorAction Stop
                break
            } catch {
                Write-Verbose -Message "Warm-up analysis with $name failed (attempt $attempt): $($_.Exception.Message)"
            }
        }
    }
}

function Invoke-RepositoryLint {
    <#
    .SYNOPSIS
        Returns every PSScriptAnalyzer finding for one file.

    .DESCRIPTION
        Runs the file's main profile, then the formatting profile. Any
        analyser error is terminating, so a crash can never read as a clean
        file.

    .PARAMETER File
        One entry from Get-RepositoryPowerShellFile.

    .PARAMETER RepositoryRoot
        The repository root.

    .OUTPUTS
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]
        Every finding from both passes.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([object])]
    param (
        [Parameter(Mandatory)]
        [object]$File,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    $formatting = Join-Path -Path $RepositoryRoot -ChildPath 'Tests/PSScriptAnalyzer/PSScriptAnalyzerFormatting.psd1'
    foreach ($settings in @($File.Settings, $formatting)) {
        Invoke-ScriptAnalyzer -Path $File.FullName -Settings $settings -ErrorAction Stop
    }
}

Export-ModuleMember -Function 'Get-RepositoryLintVersion', 'Get-RepositoryPowerShellFile', 'Initialize-RepositoryLint', 'Invoke-RepositoryLint'
