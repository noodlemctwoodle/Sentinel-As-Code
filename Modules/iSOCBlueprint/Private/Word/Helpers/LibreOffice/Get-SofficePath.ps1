#Requires -Version 7.6

<#
.SYNOPSIS
    Find the LibreOffice executable, or null.

.DESCRIPTION
    Helper for the Word report conversion (Invoke-iSOCBlueprintWordConversion).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Word/Helpers/LibreOffice/Get-SofficePath.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Word report
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SofficePath {
    <#
    .SYNOPSIS
        Locate the LibreOffice executable (soffice) on PATH or in the
        standard macOS app bundle. Returns $null if not found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    # Prefer the macOS app-bundle binary: the Homebrew 'soffice' on PATH is
    # a wrapper that launches asynchronously and returns before the macro
    # finishes. On Linux (CI) there is no app bundle, so the real soffice /
    # libreoffice on PATH is used.
    $mac = '/Applications/LibreOffice.app/Contents/MacOS/soffice'
    if (Test-Path -LiteralPath $mac) { return $mac }
    foreach ($name in 'soffice', 'libreoffice') {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}
