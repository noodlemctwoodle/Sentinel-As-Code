#Requires -Version 7.6

<#
.SYNOPSIS
    A HuntingBookmark table row in the shape of a bookmarks API item.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Helpers/ConvertFrom-HuntingBookmarkRow.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function ConvertFrom-HuntingBookmarkRow {
    <#
    .SYNOPSIS
        A HuntingBookmark table row in the shape of a bookmarks API item.

    .DESCRIPTION
        The row is a bookmark's latest entry. It is reshaped so the renderer
        reads either source the same way. The table's Tags column is a
        comma-separated string; a value that starts with "[" is read as a JSON
        array instead.

    .PARAMETER Row
        One HuntingBookmark row, with BookmarkId, BookmarkName, CreatedTime,
        LastUpdatedTime, Tags and Notes.

    .OUTPUTS
        [pscustomobject] with name (the BookmarkId) and properties
        (displayName, created, updated, labels, notes).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Row)
    $tags = [string]$Row.Tags
    $labels = if ($tags.TrimStart().StartsWith('[')) {
        try { @($tags | ConvertFrom-Json) } catch { @($tags) }
    } else {
        @($tags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    [pscustomobject]@{
        name       = [string]$Row.BookmarkId
        properties = [pscustomobject]@{
            displayName = [string]$Row.BookmarkName
            created     = [string]$Row.CreatedTime
            updated     = [string]$Row.LastUpdatedTime
            labels      = @($labels)
            notes       = [string]$Row.Notes
        }
    }
}
