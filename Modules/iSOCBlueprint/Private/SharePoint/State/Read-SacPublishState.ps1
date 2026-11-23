#Requires -Version 7.6

<#
.SYNOPSIS
    Read the publish state the last run left on the site.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/State/Read-SacPublishState.ps1
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

function Read-SacPublishState {
    <#
    .SYNOPSIS
        Read the state the last successful publish left behind (page hashes,
        navigation signature, app version), or an empty state.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $state = @{ pages = @{}; navSignature = ''; appVersion = '' }
    $text = Read-SacStateText -FileName $script:SacStateFile
    if ($text) {
        try {
            $parsed = $text | ConvertFrom-Json -AsHashtable
            if ($parsed.pages) { $state.pages = $parsed.pages }
            if ($parsed.navSignature) { $state.navSignature = [string]$parsed.navSignature }
            if ($parsed.appVersion) { $state.appVersion = [string]$parsed.appVersion }
        } catch {
            Write-Verbose "Unreadable publish state, starting fresh: $($_.Exception.Message)"
        }
    }
    return $state
}
