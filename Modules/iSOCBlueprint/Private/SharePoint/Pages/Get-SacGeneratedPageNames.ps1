#Requires -Version 7.6

<#
.SYNOPSIS
    The names of the pages the generator owns on the site.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Pages/Get-SacGeneratedPageNames.ps1
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

function Get-SacGeneratedPageNames {
    <#
    .SYNOPSIS
        Names (without .aspx) of the generated section pages in Site Pages:
        every page whose file name starts with 'sac-'.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    $items = Get-PnPListItem -List 'SitePages' -PageSize 500 -Fields 'FileLeafRef'
    return , @($items |
        ForEach-Object { [string]$_.FieldValues['FileLeafRef'] } |
        Where-Object { $_ -match '^sac-.+\.aspx$' } |
        ForEach-Object { $_ -replace '\.aspx$', '' })
}
