#Requires -Version 7.6

<#
.SYNOPSIS
    Get-WhatsNewStatus

.NOTES
    File:         Modules/iSOCBlueprint/Private/WhatsNew/Helpers/Get-WhatsNewStatus.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, What's new reading
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-WhatsNewStatus {
    <#
    .SYNOPSIS
        Action needed, Retiring, Generally available, Preview or Update.
        A call to action or a retirement outranks a release status, since
        it is what the reader has to act on.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Title, [AllowEmptyString()] [string] $Text, [AllowEmptyString()] [string] $Prefix)
    if ($Title -match '(?i)call to action') { return 'Action needed' }
    if ("$Title $Text" -match '(?i)\bretir(e|ed|es|ing|ement)\b|\bdeprecat|end of support|no longer (be )?(supported|available)|\btransitioning\b|will stop (delivering|working|being)') { return 'Retiring' }
    if ($Prefix -match '(?i)^GA$' -or $Title -match '(?i)generally available|\(GA\)') { return 'Generally available' }
    if ($Prefix -match '(?i)^preview$' -or $Title -match '(?i)\(preview\)|\bpreview\b') { return 'Preview' }
    return 'Update'
}
