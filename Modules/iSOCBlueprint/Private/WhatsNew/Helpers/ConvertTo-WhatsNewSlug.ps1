#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertTo-WhatsNewSlug

.NOTES
    File:         Modules/iSOCBlueprint/Private/WhatsNew/Helpers/ConvertTo-WhatsNewSlug.ps1
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

function ConvertTo-WhatsNewSlug {
    <#
    .SYNOPSIS
        The anchor Microsoft Learn gives a heading: lower case, anything but
        letters, digits, spaces and hyphens dropped, each space a hyphen.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Text)
    return (($Text.ToLowerInvariant() -replace '[^a-z0-9 \-]', '') -replace ' ', '-')
}
