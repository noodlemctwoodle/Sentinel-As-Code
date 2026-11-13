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
    Version:      0.2.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Assert-TokenFresh {
    <#
    .SYNOPSIS
        Stop before a stage when the access token has been in use for too long.

    .DESCRIPTION
        An access token cannot be refreshed, so a run that outlasts it would
        fail part-way with an authorisation error. This stops it before a
        stage starts instead, with a message that says why. Only an
        -AccessToken run is checked: an interactive sign-in refreshes itself.
        The inputs are script variables, set by the entry point
        (PublishParameterSet, PublishTokenLifetimeMinutes) and by the connect
        step (ConnectedAt).

    .PARAMETER Step
        The stage about to start, for the message.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Step)
    if ($script:PublishParameterSet -ne 'Token' -or -not $script:ConnectedAt) { return }
    $age = (Get-Date) - $script:ConnectedAt
    if ($age.TotalMinutes -gt $script:PublishTokenLifetimeMinutes) {
        throw "Stopping before '$Step': the access token has been in use for $([int]$age.TotalMinutes) minutes (limit $script:PublishTokenLifetimeMinutes). Re-run the publish to continue with a fresh token."
    }
}
