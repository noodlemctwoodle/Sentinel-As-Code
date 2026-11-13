#Requires -Version 7.6

<#
.SYNOPSIS
    True when python3 can import the LibreOffice UNO bridge.

.DESCRIPTION
    Helper for the Word report conversion (Invoke-iSOCBlueprintWordConversion).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Word/Helpers/LibreOffice/Test-UnoAvailable.ps1
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

function Test-UnoAvailable {
    <#
    .SYNOPSIS
        True when a python3 carrying the LibreOffice 'uno' module is on
        PATH (Ubuntu: the python3-uno package). Required for the
        page-numbered TOC bake (see Update-WordToc.py).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    if (-not (Get-Command python3 -ErrorAction SilentlyContinue)) { return $false }
    & python3 -c 'import uno' 2>$null
    return ($LASTEXITCODE -eq 0)
}
