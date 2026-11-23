#Requires -Version 7.6

<#
.SYNOPSIS
    The status of a What's New item, from its title, text and release label.

.NOTES
    File:         Modules/iSOCBlueprint/Private/WhatsNew/Helpers/Get-WhatsNewStatus.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, What's new reading
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-WhatsNewStatus {
    <#
    .SYNOPSIS
        Action needed, Retiring, Generally available, Preview or Update.
        A call to action or a retirement outranks a release status, since
        it is what the reader has to act on.

    .PARAMETER Title
        The item's title.

    .PARAMETER Text
        The item's summary text, searched together with the title for
        retirement wording.

    .PARAMETER Prefix
        The release label the item carries, such as GA or Preview. Empty when
        it has none.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Title, [AllowEmptyString()] [string] $Text, [AllowEmptyString()] [string] $Prefix)
    if ($Title -match '(?i)call to action') { return 'Action needed' }
    if ("$Title $Text" -match
            '(?i)\bretir(e|ed|es|ing|ement)\b|\bdeprecat|end of support|no longer (be )?(supported|available)|\btransitioning\b|will stop (delivering|working|being)') {
        return 'Retiring'
    }
    if ($Prefix -match '(?i)^GA$' -or $Title -match '(?i)generally available|\(GA\)') { return 'Generally available' }
    if ($Prefix -match '(?i)^preview$' -or $Title -match '(?i)\(preview\)|\bpreview\b') { return 'Preview' }
    return 'Update'
}
