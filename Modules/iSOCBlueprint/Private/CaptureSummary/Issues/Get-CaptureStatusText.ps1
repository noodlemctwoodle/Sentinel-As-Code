#Requires -Version 7.6

<#
.SYNOPSIS
    The HTTP status a capture's error names, as "401 Unauthorized" or "Forbidden"; $null when it names none.

.NOTES
    File:         Modules/iSOCBlueprint/Private/CaptureSummary/Issues/Get-CaptureStatusText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Capture reporting
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-CaptureStatusText {
    <#
    .SYNOPSIS
        The HTTP status a capture's error names, as "401 Unauthorized" or
        "Forbidden"; $null when it names none.

    .PARAMETER Message
        The capture's error message.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Message)

    if ($Message -match '\b(\d{3})\s*\(([A-Za-z ]+)\)') { return "$($Matches[1]) $($Matches[2])" }
    if ($Message -match 'does not indicate success: (\w+)') { return $Matches[1] }
    if ($Message -match '\b(Forbidden|Unauthori[sz]ed|AuthorizationFailed|AuthorizationPermissionMismatch|Authorization_RequestDenied|AccessDenied)\b') {
        return $Matches[1]
    }
    $null
}
