#Requires -Version 7.6

<#
.SYNOPSIS
    Replace each file name (NN-name.md) in escaped plain text with the section's title, as a link from -Link for a section in this run and as text otherwise.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Html/ConvertTo-SacFileMentionHtml.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint page conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-SacFileMentionHtml {
    <#
    .SYNOPSIS
        Replace each file name (NN-name.md) in escaped plain text with the
        section's title, as a link from -Link for a section in this run and
        as text otherwise.

    .PARAMETER Html
        Escaped text with no markup.

    .PARAMETER Link
        Scriptblock taking the section id and the escaped title, returning
        the link HTML.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Link', Justification = 'Read inside the -creplace script block, which the analyser does not follow.')]
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [AllowNull()] [string] $Html, [Parameter(Mandatory)] [scriptblock] $Link)

    if (-not $Html -or $Html -cnotmatch $script:SacFileNamePattern) { return [string]$Html }
    return $Html -creplace $script:SacFileNamePattern, {
        $id = $_.Groups['id'].Value
        $title = ConvertTo-SacHtmlText (Get-SacSectionName -SectionId $id)
        if ($script:SacSectionTitles -and $script:SacSectionTitles.ContainsKey($id)) { & $Link $id $title } else { $title }
    }
}
