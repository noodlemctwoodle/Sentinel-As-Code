#Requires -Version 7.6

<#
.SYNOPSIS
    Say, as it happens, that a capture could not be read and why: a line in the outcome's colour under the capture's label, or a warning for an error.

.NOTES
    File:         Modules/iSOCBlueprint/Private/CaptureSummary/Issues/Write-CaptureNote.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Capture reporting
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-CaptureNote {
    <#
    .SYNOPSIS
        Say, as it happens, that a capture could not be read and why: a line
        in the outcome's colour under the capture's label, or a warning for
        an error.

    .PARAMETER Kind
        NotAvailable, Permission or Error.

    .PARAMETER Label
        The capture's label, for an error's warning.

    .PARAMETER Text
        What happened.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Tells the operator at the console, in the outcome colour, that a capture could not be read as it happens.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('NotAvailable', 'Permission', 'Error')] [string] $Kind,
        [string] $Label,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text
    )

    switch ($Kind) {
        'NotAvailable' { Write-Host "  ↳ not available: $Text" -ForegroundColor DarkCyan }
        'Permission' { Write-Host "  ↳ no permission: $Text" -ForegroundColor Magenta }
        default { Write-Warning "[$Label] FAILED: $Text" }
    }
}
