#Requires -Version 7.6

<#
.SYNOPSIS
    Write one JSON file of the bundle, honouring -WhatIf.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Output/Write-SiteBundleJson.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-SiteBundleJson {
    <# Write an object to a bundle JSON file, honouring -WhatIf. #>
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] $Data,
        [Parameter(Mandatory)] [string] $What
    )
    if ($PSCmdlet.ShouldProcess($Path, $What)) {
        ($Data | ConvertTo-Json -Depth 32) | Set-Content -LiteralPath $Path -Encoding utf8
    }
}
