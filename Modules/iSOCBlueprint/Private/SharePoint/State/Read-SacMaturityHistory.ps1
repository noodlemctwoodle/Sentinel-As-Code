#Requires -Version 7.6

<#
.SYNOPSIS
    Read the maturity history kept on the site.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/State/Read-SacMaturityHistory.ps1
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

function Read-SacMaturityHistory {
    <#
    .SYNOPSIS
        Read the maturity score history the earlier publishes left behind,
        or an empty history.

    .OUTPUTS
        [hashtable] @{ entries = @(...) }, oldest first.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $history = @{ entries = @() }
    $text = Read-SacStateText -FileName $script:SacMaturityHistoryFile
    if ($text) {
        try {
            $parsed = $text | ConvertFrom-Json -AsHashtable
            if ($parsed.entries) { $history.entries = @($parsed.entries) }
        } catch {
            Write-Verbose "Unreadable maturity history, starting fresh: $($_.Exception.Message)"
        }
    }
    return $history
}
