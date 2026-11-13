#Requires -Version 7.6

<#
.SYNOPSIS
    Get-BpInlineText

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/Get-BpInlineText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-BpInlineText {
    param([object] $Inline)
    $sb = [System.Text.StringBuilder]::new()
    for ($i = $Inline; $null -ne $i; $i = $i.NextSibling) {
        if ($i.GetType().Name -eq 'LiteralInline') { [void]$sb.Append($i.Content.ToString()) }
        elseif ($i.PSObject.Properties['FirstChild']) { [void]$sb.Append((Get-BpInlineText $i.FirstChild)) }
    }
    return $sb.ToString()
}
