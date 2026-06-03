#
# Sentinel-As-Code/Tools/Migrate-ForkLayout.ps1
#
# Created by noodlemctwoodle on 03/06/2026.
#

<#
.SYNOPSIS
    One-shot helper for fork maintainers: relocates files left at the pre-26.06
    flat layout onto the by-concern layout (Content/, Infra/, Deploy/, Tools/).

.DESCRIPTION
    The 26.06 restructure moved the repository from a flat root into grouped
    folders. Tracked files move automatically when you merge or rebase the
    restructure (git rename detection reconciles your customisations). This
    helper catches stragglers — untracked custom content or conflict leftovers
    still sitting at an old path — and moves them to their new home.

    The move is at the filesystem level (Move-Item), which works for both
    tracked and untracked files; git detects the renames for tracked content on
    your next commit. The helper is idempotent: paths already at the new
    location are skipped. When both the old and new path exist (a partial
    migration), the old folder's contents are merged into the new folder and a
    warning is emitted for anything that would collide.

    This script does NOT rewrite file contents, regenerate dependencies.json, or
    commit. After running it: review `git status`, run
    `./Tools/Build-DependencyManifest.ps1 -Mode Generate`, then commit.

.PARAMETER RepoPath
    Repository root. Defaults to the parent of the Tools/ folder this script
    lives in.

.PARAMETER AllowDirty
    Proceed even if the working tree has uncommitted changes. By default the
    script refuses to run on a dirty tree so the moves are easy to review and
    revert.

.EXAMPLE
    ./Tools/Migrate-ForkLayout.ps1 -WhatIf

    Preview every move without touching the tree.

.EXAMPLE
    ./Tools/Migrate-ForkLayout.ps1

    Apply the moves.

.NOTES
    Author:         noodlemctwoodle
    Repository:     Sentinel-As-Code
    Requires:       PowerShell 7.2+, git
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoPath = (Split-Path -Path $PSScriptRoot -Parent),

    [Parameter(Mandatory = $false)]
    [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'

# Old (repo-relative) -> new (repo-relative). Order: directories first, then
# the individual scripts and config that split out of the old Scripts/ folder.
$moveMap = [ordered]@{
    'AnalyticalRules'                       = 'Content/AnalyticalRules'
    'AutomationRules'                       = 'Content/AutomationRules'
    'DefenderCustomDetections'              = 'Content/DefenderCustomDetections'
    'HuntingQueries'                        = 'Content/HuntingQueries'
    'Parsers'                               = 'Content/Parsers'
    'Playbooks'                             = 'Content/Playbooks'
    'SummaryRules'                          = 'Content/SummaryRules'
    'Watchlists'                            = 'Content/Watchlists'
    'Workbooks'                             = 'Content/Workbooks'
    'Bicep/main.bicep'                      = 'Infra/sentinel/main.bicep'
    'Bicep/sentinel.bicep'                  = 'Infra/sentinel/sentinel.bicep'
    'Bicep/test/main.bicep'                 = 'Infra/test-workspace/main.bicep'
    'Automation/DCR-Watchlist/main.bicep'   = 'Infra/dcr-watchlist/main.bicep'
    'Automation/DCR-Watchlist/modules'      = 'Infra/dcr-watchlist/modules'
    'Automation/DCR-Watchlist/scripts/Invoke-DCRWatchlistSync.ps1' = 'Tools/Invoke-DCRWatchlistSync.ps1'
    'Automation/DCR-Watchlist/scripts/Set-RunbookPermissions.ps1'  = 'Deploy/permissions/Set-RunbookPermissions.ps1'
    'Scripts/Deploy-CustomContent.ps1'      = 'Deploy/content/Deploy-CustomContent.ps1'
    'Scripts/Deploy-DefenderDetections.ps1' = 'Deploy/content/Deploy-DefenderDetections.ps1'
    'Scripts/Deploy-SentinelContentHub.ps1' = 'Deploy/content/Deploy-SentinelContentHub.ps1'
    'Scripts/Set-PlaybookPermissions.ps1'   = 'Deploy/permissions/Set-PlaybookPermissions.ps1'
    'Scripts/Setup-ServicePrincipal.ps1'    = 'Deploy/setup/Setup-ServicePrincipal.ps1'
    'sentinel-deployment.config'            = 'Deploy/content/sentinel-deployment.config'
    'Scripts/Build-DependencyManifest.ps1'  = 'Tools/Build-DependencyManifest.ps1'
    'Scripts/Test-SentinelRuleDrift.ps1'    = 'Tools/Test-SentinelRuleDrift.ps1'
    'Scripts/Invoke-PRValidation.ps1'       = 'Tools/Invoke-PRValidation.ps1'
    'Scripts/Export-SentinelWorkbooks.ps1'  = 'Tools/Export-SentinelWorkbooks.ps1'
    'Scripts/Import-CommunityRules.ps1'     = 'Tools/Import-CommunityRules.ps1'
    'Scripts/Documenter'                    = 'Tools/Documenter'
}

Push-Location $RepoPath
try {
    if (-not (Test-Path (Join-Path $RepoPath '.git'))) {
        throw "Not a git repository: $RepoPath"
    }

    if (-not $AllowDirty) {
        $dirty = git status --porcelain 2>$null
        if ($dirty) {
            throw "Working tree has uncommitted changes. Commit or stash first, or pass -AllowDirty."
        }
    }

    $moved = 0; $skipped = 0; $warned = 0

    foreach ($old in $moveMap.Keys) {
        $new = $moveMap[$old]
        $oldExists = Test-Path -LiteralPath $old
        $newExists = Test-Path -LiteralPath $new

        if (-not $oldExists) {
            if ($newExists) { Write-Verbose "Already migrated: $old -> $new" }
            else { Write-Verbose "Nothing at: $old" }
            $skipped++
            continue
        }

        # Old exists — make sure the destination's parent folder is present.
        $newParent = Split-Path -Path $new -Parent
        if ($newParent -and -not (Test-Path -LiteralPath $newParent)) {
            if ($PSCmdlet.ShouldProcess($newParent, 'Create directory')) {
                New-Item -ItemType Directory -Path $newParent -Force | Out-Null
            }
        }

        if (-not $newExists) {
            if ($PSCmdlet.ShouldProcess("$old -> $new", 'Move')) {
                Move-Item -LiteralPath $old -Destination $new
                $moved++
            }
            continue
        }

        # Both exist. A file-vs-file clash is a genuine conflict; leave it.
        if (Test-Path -LiteralPath $old -PathType Leaf) {
            Write-Warning "Both files exist (left in place): '$old' and '$new'."
            $warned++
            continue
        }

        # Directory merge: move each child into the new folder, warning on clash.
        Write-Warning "Both '$old' and '$new' exist — merging '$old' contents into '$new'."
        $warned++
        Get-ChildItem -LiteralPath $old -Force | ForEach-Object {
            $dest = Join-Path $new $_.Name
            if (Test-Path -LiteralPath $dest) {
                Write-Warning "  collision (left in place): $($_.FullName)"
            }
            elseif ($PSCmdlet.ShouldProcess("$($_.FullName) -> $dest", 'Move')) {
                Move-Item -LiteralPath $_.FullName -Destination $dest
                $moved++
            }
        }
    }

    Write-Host ''
    Write-Host 'Fork layout migration summary:'
    Write-Host "  moved:   $moved"
    Write-Host "  skipped: $skipped"
    Write-Host "  warned:  $warned"
    Write-Host ''
    Write-Host 'Next: review `git status`, run ./Tools/Build-DependencyManifest.ps1 -Mode Generate, then commit.'
}
finally {
    Pop-Location
}
