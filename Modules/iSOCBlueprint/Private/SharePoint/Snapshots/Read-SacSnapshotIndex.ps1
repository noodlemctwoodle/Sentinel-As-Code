#Requires -Version 7.6

<#
.SYNOPSIS
    Read the index of the per-day dashboard copies.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Snapshots/Read-SacSnapshotIndex.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Read-SacSnapshotIndex {
    <#
    .SYNOPSIS
        Read the list of dashboard snapshots the earlier publishes kept, or
        an empty list.

    .OUTPUTS
        [hashtable] @{ entries = @(...) }, newest first.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $index = @{ entries = @() }
    try {
        $text = Get-PnPFile -Url "$script:SacAssetsLibraryUrl/$script:SacSnapshotFolder/$script:SacSnapshotIndexFile" -AsString -ErrorAction Stop
        if ($text) {
            $parsed = $text | ConvertFrom-Json -AsHashtable
            if ($parsed.entries) { $index.entries = @($parsed.entries) }
        }
    }
    catch {
        Write-Verbose "No snapshot index yet: $($_.Exception.Message)"
    }
    return $index
}
