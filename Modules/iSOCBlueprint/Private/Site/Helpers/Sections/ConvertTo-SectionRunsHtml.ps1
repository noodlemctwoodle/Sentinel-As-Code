#Requires -Version 7.6

<#
.SYNOPSIS
    A section's inline runs as HTML.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Sections/ConvertTo-SectionRunsHtml.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-SectionRunsHtml {
    <#
    .SYNOPSIS
        Dashboard HTML for text runs: web links open in a new tab; links to
        another section or to a finding become in-dashboard links (the
        dashboard opens the section in its Report tab, or the finding in its
        findings view). A link to an anchor on the same page shows as text.
    #>
    param([object[]] $Runs)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($r in @($Runs)) {
        if ($null -eq $r) { continue }
        if ($r.break) { [void]$sb.Append('<br>'); continue }
        # A link or mention by file name (90-gap-analysis.md) shows the
        # section's title, and a mention becomes a link to it.
        $text = [string]$r.text
        if ($r.href -and [string]$r.target.kind -eq 'section') { $text = Get-SacSectionLinkText -Text $text -SectionId ([string]$r.target.section) }
        $fileOnly = (-not $r.href) -and $text -match '^\s*\d{2}-[a-z0-9-]+\.md\s*$'
        $h = ConvertTo-HtmlText $text
        if (-not $r.href) { $h = ConvertTo-SacFileMentionHtml -Html $h -Link { param($id, $title) "<a class=`"xref`" href=`"#`" data-xsec=`"$([int]$id.Substring(0, 2))`">$title</a>" } }
        if ($r.code -and -not $fileOnly) { $h = "<code>$h</code>" }
        if ($r.strike) { $h = "<s>$h</s>" }
        if ($r.italic) { $h = "<em>$h</em>" }
        if ($r.bold) { $h = "<strong>$h</strong>" }
        if ($r.href) {
            switch ([string]$r.target.kind) {
                'external' { $h = "<a href=`"$(ConvertTo-HtmlText ([string]$r.href))`" target=`"_blank`" rel=`"noopener`">$h</a>" }
                'finding' {
                    # The page the finding's anchor is on (90, the gap analysis)
                    # is the fallback when the finding is not in this run's list.
                    $page = if ([string]$r.href -match '^(\d+)-') { [int]$Matches[1] } else { 90 }
                    $h = "<a class=`"xref`" href=`"#`" data-xfind=`"$(ConvertTo-HtmlText ([string]$r.target.id))`" data-xsec=`"$page`">$h</a>"
                }
                'section' {
                    if ([string]$r.target.section -match '^(\d+)') { $h = "<a class=`"xref`" href=`"#`" data-xsec=`"$([int]$Matches[1])`">$h</a>" }
                }
                default { }
            }
        }
        [void]$sb.Append($h)
    }
    return $sb.ToString()
}
