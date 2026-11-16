#Requires -Version 7.6

<#
.SYNOPSIS
    What Microsoft has released, previewed and announced for retirement in
    Microsoft Sentinel and Microsoft Defender XDR, from their What's new
    pages on Microsoft Learn.

.DESCRIPTION
    Microsoft Learn returns a page's Markdown when asked for text/markdown,
    so the two What's new pages are read as Markdown rather than scraped.
    The Sentinel page gives each month a "## Month yyyy" heading and each
    item a "### Title"; the Defender XDR page gives each item a top-level
    bullet, "(Preview)" or "(GA)" first and its title in bold, with any
    nested bullets as its detail. Both shapes are read the same way into
    one list of items: product, month, title, status, summary, detail, the
    item's own link on the page, its first Learn link, and for a retirement
    or a call to action the date it names.

    Status is Action needed (a call to action), Retiring (retired,
    deprecated, transitioning, end of support), Generally available,
    Preview, or Update. The collector saves the result as whats-new.json;
    the renderer's What's new page links each item to the report pages and
    maturity criteria it touches.

    Dot-source this file to define Get-WhatsNew and the functions it uses.
    They live one per file under Modules/iSOCBlueprint/Private/WhatsNew:

      Get-WhatsNew.ps1   the entry point, with the description above and
                         the parameters
      Parsing/   ConvertFrom-WhatsNewMarkdown, one page's Markdown to items
      Helpers/   slugs, plain text, links, status and the deadline a retirement names
      Data/      the two What's new pages that are read

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Get-WhatsNew.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-14
    Version:      0.2.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file loads functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# The What's new functions (the module's own Private/WhatsNew, two folders up
# from here), defined in the caller's scope.
$whatsNewRoot = Join-Path $PSScriptRoot '..' '..' 'Private' 'WhatsNew'
foreach ($whatsNewFile in Get-ChildItem -LiteralPath $whatsNewRoot -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
    . $whatsNewFile.FullName
}
Remove-Variable -Name whatsNewFile, whatsNewRoot -WhatIf:$false
