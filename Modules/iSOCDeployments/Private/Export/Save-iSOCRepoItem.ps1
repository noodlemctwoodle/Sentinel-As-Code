#Requires -Version 7.6

<#
.SYNOPSIS
    Write an item's file, or the files of its folder, and say what changed.

.DESCRIPTION
    Each file goes through Save-iSOCRepoFile, so one whose text would not
    change is not written.

.NOTES
    File:         Modules/iSOCDeployments/Private/Export/Save-iSOCRepoItem.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Save-iSOCRepoItem {
    <#
    .SYNOPSIS
        Write an item's content under a root, and return Created, Updated
        or Unchanged.

    .DESCRIPTION
        Text is written to the relative path. A dictionary of files is
        written into the folder the relative path names, each file by its
        name; files already in the folder that the dictionary does not name
        are left. Created when the file or folder was not there, Updated
        when any file changed, Unchanged otherwise.

    .PARAMETER Root
        The folder to write under.

    .PARAMETER RelativePath
        The item's file or folder, forward-slash, under the root.

    .PARAMETER Content
        What a ToRepoFile handler returned.

    .OUTPUTS
        [string] Created, Updated or Unchanged.

    .EXAMPLE
        Save-iSOCRepoItem -Root $repo -RelativePath $path -Content $content
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Export-iSOCContent checks ShouldProcess before it calls this.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Root,

        [Parameter(Mandatory)]
        [string] $RelativePath,

        [Parameter(Mandatory)]
        [object] $Content
    )

    if ($Content -isnot [System.Collections.IDictionary]) {
        return Save-iSOCRepoFile -RepoPath $Root -RelativePath $RelativePath -Content ([string]$Content)
    }

    $created = -not (Test-Path -LiteralPath (Join-Path $Root $RelativePath) -PathType Container)
    $changed = $false
    foreach ($name in $Content.Keys) {
        $action = Save-iSOCRepoFile -RepoPath $Root -RelativePath "$RelativePath/$name" -Content ([string]$Content[$name])
        if ($action -ne 'Unchanged') { $changed = $true }
    }
    if ($created) { 'Created' } elseif ($changed) { 'Updated' } else { 'Unchanged' }
}
