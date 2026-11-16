#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertTo-WhatsNewPlain

.NOTES
    File:         Modules/iSOCBlueprint/Private/WhatsNew/Helpers/ConvertTo-WhatsNewPlain.ps1
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

function ConvertTo-WhatsNewPlain {
    <#
    .SYNOPSIS
        Markdown inline text as plain text: links and images to their text,
        emphasis and code marks removed, spaces collapsed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Text)
    $t = $Text -replace '!\[[^\]]*\]\([^)]*\)', ''
    $t = $t -replace '\[([^\]]*)\]\([^)]*\)', '$1'
    $t = $t -replace '\*\*|__', '' -replace '\*(\S[^*]*?)\*', '$1' -replace '`', ''
    return (($t -replace '\s+', ' ').Trim())
}
