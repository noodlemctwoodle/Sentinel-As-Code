#Requires -Version 7.6

<#
.SYNOPSIS
    Stages 1 and 2: make sure the assets library and findings list exist, and deploy the web part package when asked.

.DESCRIPTION
    A step of the SharePoint site publish. Steps run in order and pass their results
    to later ones through the publish context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Publish/Steps/Invoke-PublishStructure.ps1
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

function Invoke-PublishStructure {
    <#
    .SYNOPSIS
        Stages 1 and 2: make sure the assets library and findings list exist, and deploy the web part package when asked.

    .PARAMETER Context
        The publish context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the publish context.
    $AppPackagePath = $Context.AppPackagePath
    $state = $Context.state

    # 1. Structure ---------------------------------------------------------------
    Write-PublishStep '1/8 Site structure'
    Initialize-SacSiteStructure

    # 2. App ---------------------------------------------------------------------
    $appVersion = $state.appVersion
    if ($AppPackagePath) {
        Write-PublishStep '2/8 Dashboard web part package'
        Assert-TokenFresh 'app package'
        $appVersion = Publish-SacAppPackage -Path $AppPackagePath
    }
    else {
        Write-PublishStep '2/8 Dashboard web part package (skipped: no -AppPackagePath)'
    }

    # Left in the publish context for later steps.
    $Context.appVersion = $appVersion
}
