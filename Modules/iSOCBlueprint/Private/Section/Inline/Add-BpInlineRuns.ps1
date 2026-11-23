#Requires -Version 7.6

<#
.SYNOPSIS
    Walk a chain of Markdig inline nodes and append the runs they produce to a list

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/Add-BpInlineRuns.ps1
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

function Add-BpInlineRuns {
    <#
    .SYNOPSIS
        Walk a chain of Markdig inline nodes and append the runs they produce to
        a list.

    .DESCRIPTION
        Follows NextSibling from the first inline, so one call covers a whole
        sibling chain, and calls itself for the children of emphasis and link
        nodes. Literal text and inline code become text runs. Emphasis sets
        strike for '~', bold for two or more delimiters and italic otherwise. A
        link sets href; an image adds its text with no href. A hard line break
        and an HTML br tag add a break entry, and a soft line break adds a
        space. HTML entities add their transcoded text. Any other node is walked
        through its children when it has any, and is otherwise added as its own
        string.

    .PARAMETER Inline
        The first inline of the chain to walk. When it is $null nothing is added.

    .PARAMETER Format
        The formatting the runs inherit: a hashtable that may hold bold, italic,
        code, strike and href. A nested node works on its own copy, so the
        caller's table is not changed.

    .PARAMETER Out
        The list that receives the runs, which are ordered dictionaries.
    #>
    [CmdletBinding()]
    param([object] $Inline, [hashtable] $Format, [System.Collections.Generic.List[object]] $Out)
    for ($i = $Inline; $null -ne $i; $i = $i.NextSibling) {
        switch ($i.GetType().Name) {
            'LiteralInline' { Add-BpRun -Out $Out -Text $i.Content.ToString() -Format $Format }
            'CodeInline' { $f = $Format.Clone(); $f.code = $true; Add-BpRun -Out $Out -Text ([string]$i.Content) -Format $f }
            'EmphasisInline' {
                $f = $Format.Clone()
                if ($i.DelimiterChar -eq '~') { $f.strike = $true }
                elseif ($i.DelimiterCount -ge 2) { $f.bold = $true }
                else { $f.italic = $true }
                Add-BpInlineRuns -Inline $i.FirstChild -Format $f -Out $Out
            }
            'LinkInline' {
                if ($i.IsImage) { Add-BpRun -Out $Out -Text (Get-BpInlineText $i.FirstChild) -Format $Format; break }
                $f = $Format.Clone(); $f.href = [string]$i.Url
                Add-BpInlineRuns -Inline $i.FirstChild -Format $f -Out $Out
            }
            'AutolinkInline' { $f = $Format.Clone(); $f.href = [string]$i.Url; Add-BpRun -Out $Out -Text ([string]$i.Url) -Format $f }
            'LineBreakInline' { if ($i.IsHard) { $Out.Add([ordered]@{ break = $true }) } else { Add-BpRun -Out $Out -Text ' ' -Format $Format } }
            'HtmlInline' { if ([string]$i.Tag -match '^<br\s*/?>$') { $Out.Add([ordered]@{ break = $true }) } }
            'HtmlEntityInline' { Add-BpRun -Out $Out -Text $i.Transcoded.ToString() -Format $Format }
            default {
                if ($i.PSObject.Properties['FirstChild']) { Add-BpInlineRuns -Inline $i.FirstChild -Format $Format -Out $Out }
                else { Add-BpRun -Out $Out -Text $i.ToString() -Format $Format }
            }
        }
    }
}
