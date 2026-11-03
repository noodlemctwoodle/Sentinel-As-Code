#Requires -Version 7.2

<#
.SYNOPSIS
    The state one Compare-iSOCContent call works with.

.NOTES
    File:         Modules/iSOCDeployments/Private/Drift/New-iSOCDriftRun.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function New-iSOCDriftRun {
    <#
    .SYNOPSIS
        Build a drift run.

    .DESCRIPTION
        Replaces the script-scope state Tools/Test-SentinelRuleDrift.ps1 kept.
        A content type's Classify handler reads what it needs once (the
        repository's files, the templates) into the cache.

    .PARAMETER Context
        The workspace context.

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER Options
        Solution (names to limit Content Hub rules to), Severity (the
        severities to compare) and ExcludeSource (sources to leave out).

    .OUTPUTS
        [pscustomobject] Context, RepoPath, Options, Cache and Started.

    .EXAMPLE
        $run = New-iSOCDriftRun -Context $ctx -RepoPath $repo -Options @{ Severity = @('High') }
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; nothing outside the call changes.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $RepoPath,

        [hashtable] $Options = @{}
    )

    $settings = @{ Solution = @(); Severity = @(); ExcludeSource = @() }
    foreach ($name in $Options.Keys) { $settings[$name] = @($Options[$name] | Where-Object { $_ }) }

    [pscustomobject]@{
        PSTypeName = 'iSOCDeployments.DriftRun'
        Context    = $Context
        RepoPath   = $RepoPath
        Options    = [pscustomobject]$settings
        Cache      = @{}
        Started    = Get-Date
    }
}
