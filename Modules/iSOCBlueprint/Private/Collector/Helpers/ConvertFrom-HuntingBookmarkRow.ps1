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
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# One HuntingBookmark row (a bookmark's latest entry) in the shape of a
# bookmarks API item, so the renderer reads either source the same way. The
# table's Tags column is a comma-separated string.
function ConvertFrom-HuntingBookmarkRow {
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
