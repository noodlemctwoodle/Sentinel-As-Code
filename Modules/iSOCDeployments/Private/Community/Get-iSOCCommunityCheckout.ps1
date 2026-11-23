#Requires -Version 7.6

<#
.SYNOPSIS
    A checkout of a community source to import from.

.DESCRIPTION
    Replaces the clone in Invoke-Main (Tools/Import-CommunityRules.ps1). -SourcePath imports from a
    checkout already on disk (MIGRATION.md edit E28).

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/Get-iSOCCommunityCheckout.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCCommunityCheckout {
    <#
    .SYNOPSIS
        Clone a community source shallowly into a temporary folder, or use
        a folder given, and say which commit it is.

    .DESCRIPTION
        The clone is depth 1 of one branch. The commit is the checkout's
        HEAD, or 'unknown' when it is not a git checkout (or git is not
        installed).

    .PARAMETER SourceRepo
        The repository to clone.

    .PARAMETER SourceBranch
        The branch.

    .PARAMETER SourcePath
        A folder to import from instead of cloning.

    .PARAMETER Destination
        Where to clone to, a folder that does not exist yet; the caller
        removes it.

    .OUTPUTS
        [pscustomobject] Path and Commit.

    .EXAMPLE
        $checkout = Get-iSOCCommunityCheckout -SourceRepo $repo -SourceBranch main -Destination $temp
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $SourceRepo,

        [Parameter(Mandatory)]
        [string] $SourceBranch,

        [string] $SourcePath,

        [string] $Destination
    )

    if ($SourcePath) {
        if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) { throw "The source folder '$SourcePath' does not exist." }
        $path = (Resolve-Path -LiteralPath $SourcePath).ProviderPath
        Write-iSOCLog "Source: $path"
    } else {
        if (-not $Destination) { throw 'A clone needs a destination.' }
        $path = $Destination
        Write-iSOCLog "Cloning $SourceRepo ($SourceBranch)" -Level Section
        try { Invoke-iSOCGit -ArgumentList 'clone', '--depth', '1', '--branch', $SourceBranch, '--single-branch', $SourceRepo, $path | Out-Null }
        catch { throw "Failed to clone repository: $($_.Exception.Message)" }
        Write-iSOCLog 'Clone completed' -Level Success
    }

    $commit = 'unknown'
    try {
        $head = Invoke-iSOCGit -ArgumentList '-C', $path, 'rev-parse', 'HEAD' -AllowFailure
        if ($head.ExitCode -eq 0 -and @($head.Output).Count -gt 0) { $commit = ([string]$head.Output[0]).Trim() }
    } catch { $commit = 'unknown' }
    Write-iSOCLog "Source commit: $commit"
    [pscustomobject]@{ Path = $path; Commit = $commit }
}
