#Requires -Version 7.6

<#
.SYNOPSIS
    Print a stage heading.

.DESCRIPTION
    Helper for the SharePoint site publish (Invoke-iSOCBlueprintSitePublish).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Publish/Helpers/Write-PublishStep.ps1
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

function Write-PublishStep {
    param([Parameter(Mandatory)] [string] $Message)
    Write-Host "`n$Message" -ForegroundColor Cyan
}
