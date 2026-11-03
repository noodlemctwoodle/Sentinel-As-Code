#Requires -Version 7.2

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
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

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
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    $changedFiles = $null
    try {
        if ($env:BUILD_SOURCEBRANCH -and $env:SYSTEM_PULLREQUEST_TARGETBRANCH) {
            $targetBranch = $env:SYSTEM_PULLREQUEST_TARGETBRANCH -replace '^refs/heads/', ''
            & git -C $RepoPath fetch --depth=1 origin $targetBranch 2>$null | Out-Null
            $changedFiles = & git -C $RepoPath diff --name-only "origin/$targetBranch...HEAD" 2>$null
        }
        elseif ($env:BUILD_SOURCEVERSION) {
            & git -C $RepoPath fetch --deepen=1 2>$null | Out-Null
            $changedFiles = & git -C $RepoPath diff --name-only HEAD~1 HEAD 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $changedFiles) {
                $branch = $env:BUILD_SOURCEBRANCH -replace '^refs/heads/', ''
                & git -C $RepoPath fetch --depth=2 origin $branch 2>$null | Out-Null
                $changedFiles = & git -C $RepoPath diff --name-only HEAD~1 HEAD 2>$null
            }
        }
        else {
            $changedFiles = & git -C $RepoPath diff --name-only HEAD~1 HEAD 2>$null
        }
    }
    catch {
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
