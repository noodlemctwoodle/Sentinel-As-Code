#Requires -Version 7.6

<#
.SYNOPSIS
    Add-BpInlineRuns

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/Add-BpInlineRuns.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Add-BpInlineRuns {
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
