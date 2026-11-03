#Requires -Version 7.2

<#
.SYNOPSIS
    The object the manifest commands return.

.NOTES
    File:         Modules/iSOCDeployments/Private/Manifest/New-iSOCManifestResult.ps1
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

function New-iSOCManifestResult {
    <#
    .SYNOPSIS
        Turn a manifest state into the result a command returns.

    .PARAMETER State
        From Get-iSOCDependencyManifestState.

    .PARAMETER Changed
        Whether the command wrote the manifest.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ManifestResult: ManifestPath
        (repository-relative), Exists, HasDrift, Changed, Entries (the
        count), Diff and MissingWatchlists.

    .EXAMPLE
        New-iSOCManifestResult -State $state -Changed $false
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; nothing outside the call changes.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $State,

        [bool] $Changed
    )

    [pscustomobject]@{
        PSTypeName        = 'iSOCDeployments.ManifestResult'
        ManifestPath      = ConvertTo-iSOCRepoRelativePath -Path $State.ManifestPath -RepoPath $State.RepoPath
        Exists            = $State.Exists
        HasDrift          = $State.HasDrift
        Changed           = $Changed
        Entries           = $State.Entries.Count
        Diff              = $State.Diff
        MissingWatchlists = $State.MissingWatchlists
    }
}
