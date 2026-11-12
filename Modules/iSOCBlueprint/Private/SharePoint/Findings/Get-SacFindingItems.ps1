#Requires -Version 7.6

<#
.SYNOPSIS
    Read the findings list items.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Findings/Get-SacFindingItems.ps1
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

function Get-SacFindingItems {
    <#
    .SYNOPSIS
        Read the findings list into the planner's shape (ItemId, FindingId,
        Status).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    $items = Get-PnPListItem -List $script:SacFindingsListUrl -PageSize 500 -Fields 'FindingId', 'Status' -ErrorAction SilentlyContinue
    return , @($items | ForEach-Object {
            [pscustomobject]@{
                ItemId    = $_.Id
                FindingId = [string]$_.FieldValues['FindingId']
                Status    = [string]$_.FieldValues['Status']
            }
        })
}
