#Requires -Version 7.6

<#
.SYNOPSIS
    Read a text file from the publisher's state folder.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Files/Read-SacStateText.ps1
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

function Read-SacStateText {
    <#
    .SYNOPSIS
        Text of one _state/ file from the assets library, falling back to the
        library's pre-Blueprint name, or $null when neither has it.

    .PARAMETER FileName
        File name under _state/.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $FileName)
    foreach ($library in $script:SacAssetsLibraryUrl, $script:SacLegacyAssetsLibraryUrl) {
        try {
            $text = Get-PnPFile -Url "$library/_state/$FileName" -AsString -ErrorAction Stop
            if ($text) { return [string]$text }
        } catch {
            Write-Verbose "No $FileName in $($library): $($_.Exception.Message)"
        }
    }
    return $null
}
