#Requires -Version 7.6

<#
.SYNOPSIS
    Return the text for a section whose capture is missing or empty.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Inventory/Get-BlueprintEmptyMessage.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-BlueprintEmptyMessage([string]$Name, [string]$Empty = '_None._') {
    # A capture added after a snapshot was taken leaves no file. Its section
    # says so, rather than claiming the workspace has nothing.
    if (Test-Path (Join-Path $script:RawRoot $Name)) { return $Empty }
    return '_Not captured in this snapshot._'
}
