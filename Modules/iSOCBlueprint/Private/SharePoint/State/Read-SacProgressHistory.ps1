#Requires -Version 7.6

<#
.SYNOPSIS
    Read the progress history kept on the site.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/State/Read-SacProgressHistory.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Read-SacProgressHistory {
    <#
    .SYNOPSIS
        Read the progress history earlier publishes left on the site, or
        $null when there is none (Merge-SacProgressHistory starts afresh).
    #>
    [CmdletBinding()]
    param()
    $text = Read-SacStateText -FileName $script:SacProgressHistoryFile
    if (-not $text) { return $null }
    try { return ($text | ConvertFrom-Json -Depth 32) }
    catch {
        Write-Verbose "Unreadable progress history, starting fresh: $($_.Exception.Message)"
        return $null
    }
}
