#Requires -Version 7.6

<#
.SYNOPSIS
    Stop before a stage when the access token has been in use for too long.

.DESCRIPTION
    Helper for the SharePoint site publish (Invoke-iSOCBlueprintSitePublish).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Publish/Helpers/Assert-TokenFresh.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Assert-TokenFresh {
    param([Parameter(Mandatory)] [string] $Step)
    if ($PSCmdlet.ParameterSetName -ne 'Token' -or -not $script:ConnectedAt) { return }
    $age = (Get-Date) - $script:ConnectedAt
    if ($age.TotalMinutes -gt $TokenLifetimeMinutes) {
        throw "Stopping before '$Step': the access token has been in use for $([int]$age.TotalMinutes) minutes (limit $TokenLifetimeMinutes). Re-run the publish to continue with a fresh token."
    }
}
