#Requires -Version 7.6

<#
.SYNOPSIS
    Write a progress line in the colour of its level.

.DESCRIPTION
    Helper for the Word report conversion (Invoke-iSOCBlueprintWordConversion).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Word/Helpers/Logging/Write-WordLog.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Word report
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-WordLog {
    <#
    .SYNOPSIS
        Write a progress line in the colour of its level.

    .DESCRIPTION
        The line is written with Write-Host. A Section line is preceded by a
        blank line and written in cyan; Warning is yellow, Error red and Success
        green. Info is written in the default colour.

    .PARAMETER Message
        The line to write.

    .PARAMETER Level
        Info, Section, Warning, Error or Success. Info when omitted.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Message,
        [Parameter()] [ValidateSet('Info', 'Section', 'Warning', 'Error', 'Success')]
        [string] $Level = 'Info'
    )
    switch ($Level) {
        'Section' { Write-Host "`n$Message" -ForegroundColor Cyan }
        'Warning' { Write-Host $Message -ForegroundColor Yellow }
        'Error' { Write-Host $Message -ForegroundColor Red }
        'Success' { Write-Host $Message -ForegroundColor Green }
        default { Write-Host $Message }
    }
}
