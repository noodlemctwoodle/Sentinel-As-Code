#Requires -Version 7.6

<#
.SYNOPSIS
    Return the id of a paragraph that holds only an HTML anchor, which marks the next heading

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/Get-BpAnchorOnly.ps1
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

function Get-BpAnchorOnly {
    <#
    .SYNOPSIS
        Return the id of a paragraph that holds only an HTML anchor, which marks
        the next heading.

    .DESCRIPTION
        A paragraph that is only <a id="x"></a> names the anchor of the heading
        that follows it. The paragraph may also hold whitespace-only text and
        line breaks. Anything else, or no anchor, gives $null.

    .PARAMETER Container
        The Markdig container inline of a paragraph. When it is $null the result
        is $null.

    .OUTPUTS
        [string] The anchor id, or $null.
    #>
    [CmdletBinding()]
    param([object] $Container)
    if ($null -eq $Container) { return $null }
    $id = $null
    for ($i = $Container.FirstChild; $null -ne $i; $i = $i.NextSibling) {
        $name = $i.GetType().Name
        if ($name -eq 'HtmlInline') {
            if ([string]$i.Tag -match '^<a\s+id="([^"]+)"\s*>$') { $id = $Matches[1]; continue }
            if ([string]$i.Tag -match '^</a>$') { continue }
            return $null
        }
        if ($name -eq 'LiteralInline' -and [string]::IsNullOrWhiteSpace($i.Content.ToString())) { continue }
        if ($name -eq 'LineBreakInline') { continue }
        return $null
    }
    return $id
}
