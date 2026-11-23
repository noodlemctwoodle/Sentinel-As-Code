#Requires -Version 7.6

<#
.SYNOPSIS
    The files or folders in the repository that hold a content type's items.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Get-iSOCContentFile.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.2
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCContentFile {
    <#
    .SYNOPSIS
        List a content type's files, or for a folder layout its item folders.

    .DESCRIPTION
        A File layout returns every file under the type's folder whose name
        matches one of its patterns, through every subfolder when the type
        recurses. A Folder layout returns each folder directly under the
        type's folder, one item per folder. Both come back in ordinal order
        of their repository-relative path, so every machine walks the
        repository in the same order. A type whose folder does not exist has
        no items.

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER ContentType
        The content type.

    .OUTPUTS
        [System.IO.FileInfo] or [System.IO.DirectoryInfo]

    .EXAMPLE
        Get-iSOCContentFile -RepoPath $repo -ContentType $rules
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileSystemInfo])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath,

        [Parameter(Mandatory)]
        [psobject] $ContentType
    )

    $root = Join-Path $RepoPath $ContentType.RepoFolder
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return }

    # Wrapped whole: an if statement's output is unrolled, so a type with one
    # item would otherwise come back as a single object.
    $found = @(if ($ContentType.Layout -eq 'Folder') {
            Get-ChildItem -LiteralPath $root -Directory
        } else {
            Get-ChildItem -LiteralPath $root -File -Recurse:([bool]$ContentType.Recurse) | Where-Object {
                $fileName = $_.Name
                @($ContentType.FilePattern | Where-Object { $fileName -like $_ }).Count -gt 0
            }
        })
    if ($found.Count -eq 0) { return }

    # [Array]::Sort with a separate items array would sort a converted copy,
    # so the items are sorted as key and item pairs in a list instead.
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $found) {
        $entries.Add([pscustomobject]@{ Key = [System.IO.Path]::GetRelativePath($RepoPath, $item.FullName).Replace('\', '/'); Item = $item })
    }
    $entries.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Key, $b.Key) })
    foreach ($entry in $entries) { $entry.Item }
}
