#Requires -Version 7.6

<#
.SYNOPSIS
    Build and publish the SharePoint site for a New-iSOCBlueprint run.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Run/Invoke-iSOCBlueprintRunSite.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, one-command run
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCBlueprintRunSite {
    <#
    .SYNOPSIS
        Build the site bundle (New-iSOCBlueprintSite) when the formats
        include SharePoint and, with -SiteUrl, publish it
        (Publish-iSOCBlueprintSite).

    .PARAMETER Run
        The run's shared state: the values New-iSOCBlueprint was called with
        and what each step has produced so far. Steps read and add to it.
        Adds Bundle (the bundle folder) and Published (the site's address),
        each $null when that step did not run.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Run)

    $Run.Bundle = $null
    $Run.Published = $null
    if ($Run.Format -contains 'SharePoint') {
        $Run.Bundle = (New-iSOCBlueprintSite -Path $Run.Workspace -HistoryDays $Run.HistoryDays).Path
        if ($Run.SiteUrl) {
            $publish = @{ SiteUrl = $Run.SiteUrl; Path = $Run.Bundle }
            if ($Run.AccessToken) { $publish.AccessToken = $Run.AccessToken }
            else {
                $publish.Interactive = $true
                $publish.ClientId = $Run.ClientId
                $publish.Tenant = $Run.Tenant
            }
            if ($Run.AppPackagePath) { $publish.AppPackagePath = $Run.AppPackagePath }
            $publish.HistoryDays = $Run.HistoryDays
            $Run.Published = Publish-iSOCBlueprintSite @publish
        }
    }
}
