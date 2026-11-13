#Requires -Version 7.6

<#
.SYNOPSIS
    HTML for a list of text runs, for a Text web part.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Html/ConvertTo-SacRunsHtml.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, SharePoint page conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function ConvertTo-SacRunsHtml {
    <#
    .SYNOPSIS
        HTML for a list of text runs, for a Text web part.

    .PARAMETER Runs
        Text runs from the section model.

    .PARAMETER FindingsListUrl
        Site-relative URL of the findings list.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] [AllowEmptyCollection()] [object[]] $Runs,
        [Parameter(Mandatory)] [string] $FindingsListUrl
    )
    $sb = [System.Text.StringBuilder]::new()
    foreach ($r in @($Runs)) {
        if ($null -eq $r) { continue }
        if ($r.break) { [void]$sb.Append('<br>'); continue }
        # A link or mention by file name shows the section's title.
        $text = [string]$r.text
        if ($r.href -and [string]$r.target.kind -eq 'section') { $text = Get-SacSectionLinkText -Text $text -SectionId ([string]$r.target.section) }
        $fileOnly = (-not $r.href) -and $text -match '^\s*\d{2}-[a-z0-9-]+\.md\s*$'
        $h = ConvertTo-SacHtmlText $text
        if (-not $r.href) { $h = ConvertTo-SacFileMentionHtml -Html $h -Link { param($id, $title) "<a href=`"~site/SitePages/$(Get-SacPageName -FileName $id).aspx`">$title</a>" } }
        if ($r.code -and -not $fileOnly) { $h = "<code>$h</code>" }
        if ($r.strike) { $h = "<s>$h</s>" }
        if ($r.italic) { $h = "<em>$h</em>" }
        if ($r.bold) { $h = "<strong>$h</strong>" }
        if ($r.href) {
            $url = ConvertTo-SacSiteLink -Run $r -FindingsListUrl $FindingsListUrl
            if ($url) { $h = "<a href=`"$url`">$h</a>" }
        }
        [void]$sb.Append($h)
    }
    return $sb.ToString()
}
