#Requires -Version 7.6

<#
.SYNOPSIS
    Get-SacRunsText

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Html/Get-SacRunsText.ps1
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

function Get-SacRunsText {
    <#
    .SYNOPSIS
        The plain text of a list of text runs, for a CSV cell: a section
        link shows its section's title, a line break becomes a space.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [AllowEmptyCollection()] [object[]] $Runs)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($r in @($Runs)) {
        if ($null -eq $r) { continue }
        if ($r.break) { [void]$sb.Append(' '); continue }
        $text = [string]$r.text
        if ($r.href -and [string]$r.target.kind -eq 'section') { $text = Get-SacSectionLinkText -Text $text -SectionId ([string]$r.target.section) }
        [void]$sb.Append($text)
    }
    return ($sb.ToString() -replace '\s+', ' ').Trim()
}
