#Requires -Version 7.2

<#
.SYNOPSIS
    Write a file into the repository only when its content changes.

.DESCRIPTION
    Copied from the write in Save-AbsorbedRule
    (Tools/Test-SentinelRuleDrift.ps1), so a run that finds the same drift
    again leaves the working tree as it was.

.NOTES
    File:         Modules/iSOCDeployments/Private/Drift/Save-iSOCRepoFile.ps1
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

function Save-iSOCRepoFile {
    <#
    .SYNOPSIS
        Create, update or leave a file, and say which.

    .DESCRIPTION
        The folder is created when it is missing. The text is written as
        UTF-8 without a byte order mark, exactly as given.

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER RelativePath
        The file's forward-slash path under the root.

    .PARAMETER Content
        The file's text.

    .OUTPUTS
        [string] Created, Updated or Unchanged.

    .EXAMPLE
        Save-iSOCRepoFile -RepoPath $repo -RelativePath $path -Content $yaml
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Sync-iSOCContent checks ShouldProcess before it calls this.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath,

        [Parameter(Mandatory)]
        [string] $RelativePath,

        [Parameter(Mandatory)]
        [string] $Content
    )

    $target = Join-Path $RepoPath $RelativePath
    $folder = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }

    $action = 'Created'
    if (Test-Path -LiteralPath $target) {
        if ((Get-Content -LiteralPath $target -Raw) -ceq $Content) { return 'Unchanged' }
        $action = 'Updated'
    }
    [System.IO.File]::WriteAllText($target, $Content, [System.Text.UTF8Encoding]::new($false))
    $action
}
