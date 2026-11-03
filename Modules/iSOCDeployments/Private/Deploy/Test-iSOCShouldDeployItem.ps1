#Requires -Version 7.2

<#
.SYNOPSIS
    Decide whether an item deploys in this run.

.DESCRIPTION
    Replaces Test-ShouldDeployFile (Deploy/content/Deploy-CustomContent.ps1).
    The checks are the same, applied to each of the item's files; an item
    deploys when any of its files would, as the script's watchlist step
    did. The result says why, so an excluded item is not reported as
    unchanged (MIGRATION.md edit E12).

.NOTES
    File:         Modules/iSOCDeployments/Private/Deploy/Test-iSOCShouldDeployItem.ps1
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

function Test-iSOCShouldDeployItem {
    <#
    .SYNOPSIS
        Return whether an item deploys, and the reason.

    .DESCRIPTION
        For each file of the item:

        - a path in excludecontentfiles (or under one) never deploys;
        - without smart deployment, everything else deploys;
        - with it, a file deploys when git reports it, a path under it or
          a file in its folder as changed, or when the state does not
          record its last deployment as a success (a retry).

    .PARAMETER Run
        The deployment run.

    .PARAMETER Item
        A repository item.

    .OUTPUTS
        [pscustomobject] Deploy ([bool]) and Reason: Full, Changed, Retry,
        Unchanged or Excluded.

    .EXAMPLE
        $decision = Test-iSOCShouldDeployItem -Run $run -Item $item
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Run,

        [Parameter(Mandatory)]
        [psobject] $Item
    )

    $decisions = foreach ($relativePath in Get-iSOCItemFile -Item $Item -RepoPath $Run.RepoPath) {
        $excluded = $false
        foreach ($excl in $Run.Config.Excluded) {
            if ($relativePath -like "$excl*" -or $relativePath -eq $excl) { $excluded = $true; break }
        }
        if ($excluded) { [pscustomobject]@{ Deploy = $false; Reason = 'Excluded' }; continue }

        if ($null -eq $Run.ChangedFiles) { [pscustomobject]@{ Deploy = $true; Reason = 'Full' }; continue }

        $isChanged = $false
        foreach ($cf in $Run.ChangedFiles) {
            if ($relativePath -eq $cf -or $relativePath -like "$cf*" -or $cf -like "$relativePath*") { $isChanged = $true; break }
        }
        if (-not $isChanged) {
            $parentDir = (Split-Path $relativePath -Parent).Replace('\', '/')
            if ($parentDir) {
                foreach ($cf in $Run.ChangedFiles) {
                    if ($cf -like "$parentDir/*") { $isChanged = $true; break }
                }
            }
        }
        if ($isChanged) { [pscustomobject]@{ Deploy = $true; Reason = 'Changed' }; continue }

        if (-not (Test-iSOCDeployedSuccessfully -State $Run.State -Key $relativePath)) {
            [pscustomobject]@{ Deploy = $true; Reason = 'Retry' }
            continue
        }
        [pscustomobject]@{ Deploy = $false; Reason = 'Unchanged' }
    }

    $deploying = @($decisions | Where-Object Deploy)
    if ($deploying.Count -gt 0) { return $deploying[0] }
    @($decisions)[0]
}
