#Requires -Version 7.2

<#
.SYNOPSIS
    Read what an item's file, or the files of its folder, hold now.

.DESCRIPTION
    Export-iSOCContent reads an item's files before it writes them: to
    merge with what they hold (a workbook's curated metadata) and to tell
    whether writing would change anything.

.NOTES
    File:         Modules/iSOCDeployments/Private/Export/Read-iSOCRepoItemFile.ps1
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

function Read-iSOCRepoItemFile {
    <#
    .SYNOPSIS
        Return an item's file text, or its folder's files by name, or
        nothing when there is none.

    .DESCRIPTION
        For a content type with one item per file, the file's text. For one
        with one item per folder, an ordered dictionary of the files
        directly in the folder, by name in ordinal order, an empty file
        read as empty text. Nothing when the file or folder is not there.

    .PARAMETER Root
        The folder the relative path is under: the repository, or the
        folder an export writes to instead.

    .PARAMETER RelativePath
        The item's file or folder, forward-slash, under the root.

    .PARAMETER ContentType
        The content type, for its layout.

    .OUTPUTS
        [string] or [System.Collections.Specialized.OrderedDictionary].

    .EXAMPLE
        $existing = Read-iSOCRepoItemFile -Root $repo -RelativePath 'Content/Workbooks/Cost' -ContentType $workbooks
    #>
    [CmdletBinding()]
    [OutputType([string], [System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string] $Root,

        [Parameter(Mandatory)]
        [string] $RelativePath,

        [Parameter(Mandatory)]
        [psobject] $ContentType
    )

    $target = Join-Path $Root $RelativePath
    if ($ContentType.Layout -eq 'File') {
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { return }
        $text = Get-Content -LiteralPath $target -Raw
        if ($null -eq $text) { return '' }
        return $text
    }

    if (-not (Test-Path -LiteralPath $target -PathType Container)) { return }
    $names = [string[]]@(Get-ChildItem -LiteralPath $target -File | ForEach-Object { $_.Name })
    [Array]::Sort($names, [System.StringComparer]::Ordinal)
    $files = [ordered]@{}
    foreach ($name in $names) {
        $text = Get-Content -LiteralPath (Join-Path $target $name) -Raw
        $files[$name] = if ($null -eq $text) { '' } else { $text }
    }
    $files
}
