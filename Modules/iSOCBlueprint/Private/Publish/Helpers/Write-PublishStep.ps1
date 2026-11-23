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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-PublishStep {
    <#
    .SYNOPSIS
        Print a stage heading.

    .DESCRIPTION
        Writes the message to the host in cyan, after a blank line.

    .PARAMETER Message
        The heading text.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Message)
    Write-Host "`n$Message" -ForegroundColor Cyan
}
