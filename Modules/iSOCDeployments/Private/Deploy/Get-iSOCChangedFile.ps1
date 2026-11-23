#Requires -Version 7.6

<#
.SYNOPSIS
    The files the commit being deployed changed, for smart deployment.

.DESCRIPTION
    Copied from the git half of Initialize-SmartDeployment
    (Deploy/content/Deploy-CustomContent.ps1), unchanged in what it asks
    git, with git run against the repository root instead of changing the
    current folder.

.NOTES
    File:         Modules/iSOCDeployments/Private/Deploy/Get-iSOCChangedFile.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    Needs git 2.x on PATH when smart deployment is asked for.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCChangedFile {
    <#
    .SYNOPSIS
        Return the repository-relative paths git reports as changed, or
        nothing when it cannot tell.

    .DESCRIPTION
        - An Azure DevOps pull request build diffs against its target
          branch.
        - An Azure DevOps CI build deepens the shallow clone by one commit
          and diffs HEAD~1 with HEAD, fetching two commits of the branch if
          that fails.
        - Anywhere else, HEAD~1 is diffed with HEAD.

        When git fails or reports nothing, smart deployment falls back to
        deploying everything, so nothing is skipped because a diff could not
        be made.

    .PARAMETER RepoPath
        The repository root.

    .OUTPUTS
        [string[]] Paths with forward slashes, or nothing.

    .EXAMPLE
        $changed = Get-iSOCChangedFile -RepoPath $repo
    #>
    [CmdletBinding()]
    [OutputType([string[]], [object[]])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    $git = { param([string[]] $Arguments) Invoke-iSOCGit -ArgumentList (@('-C', $RepoPath) + $Arguments) -AllowFailure -NoStandardError }
    $changedFiles = $null
    try {
        if ($env:BUILD_SOURCEBRANCH -and $env:SYSTEM_PULLREQUEST_TARGETBRANCH) {
            $targetBranch = $env:SYSTEM_PULLREQUEST_TARGETBRANCH -replace '^refs/heads/', ''
            & $git 'fetch', '--depth=1', 'origin', $targetBranch | Out-Null
            $changedFiles = (& $git 'diff', '--name-only', "origin/$targetBranch...HEAD").Output
        } elseif ($env:BUILD_SOURCEVERSION) {
            & $git 'fetch', '--deepen=1' | Out-Null
            $diff = & $git 'diff', '--name-only', 'HEAD~1', 'HEAD'
            $changedFiles = $diff.Output
            if ($diff.ExitCode -ne 0 -or -not $changedFiles) {
                $branch = $env:BUILD_SOURCEBRANCH -replace '^refs/heads/', ''
                & $git 'fetch', '--depth=2', 'origin', $branch | Out-Null
                $changedFiles = (& $git 'diff', '--name-only', 'HEAD~1', 'HEAD').Output
            }
        } else {
            $changedFiles = (& $git 'diff', '--name-only', 'HEAD~1', 'HEAD').Output
        }
    } catch {
        Write-iSOCLog "  Git diff failed: $($_.Exception.Message); deploying all content." -Level Warning
        return
    }

    $changedFiles = @($changedFiles | Where-Object { $_ } | ForEach-Object { ([string]$_).Replace('\', '/') })
    if ($changedFiles.Count -eq 0) {
        Write-iSOCLog '  Could not determine changed files; deploying all content.' -Level Warning
        return
    }
    $changedFiles
}
