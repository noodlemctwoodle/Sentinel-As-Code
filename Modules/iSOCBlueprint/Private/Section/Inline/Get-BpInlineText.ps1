#Requires -Version 7.6

<#
.SYNOPSIS
    Return the plain text of a chain of Markdig inline nodes

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/Get-BpInlineText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-BpInlineText {
    <#
    .SYNOPSIS
        Return the plain text of a chain of Markdig inline nodes.

    .DESCRIPTION
        Literal text is appended and the children of nested nodes are read in
        turn. Any other node without children adds nothing.

    .PARAMETER Inline
        The first inline of the chain, which is followed through NextSibling.

    .OUTPUTS
        [string] The text.
    #>
    [CmdletBinding()]
    param([object] $Inline)
    $sb = [System.Text.StringBuilder]::new()
    for ($i = $Inline; $null -ne $i; $i = $i.NextSibling) {
        if ($i.GetType().Name -eq 'LiteralInline') { [void]$sb.Append($i.Content.ToString()) }
        elseif ($i.PSObject.Properties['FirstChild']) { [void]$sb.Append((Get-BpInlineText $i.FirstChild)) }
    }
    return $sb.ToString()
}
