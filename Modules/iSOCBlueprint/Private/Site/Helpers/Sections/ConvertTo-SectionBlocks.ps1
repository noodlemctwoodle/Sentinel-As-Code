#Requires -Version 7.6

<#
.SYNOPSIS
    A section model as the dashboard's structured blocks.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Sections/ConvertTo-SectionBlocks.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-SectionBlocks {
    <#
    .SYNOPSIS
        Turn one section from the section model into the dashboard's render
        blocks.

    .DESCRIPTION
        Headings, paragraphs, lists, tables, notes (callouts) and charts become
        blocks. Code, rules and any other block type are left out, and so is a
        block marked inGraphic, which a graphic on the page shows in full. A
        chart is added only when it has data: pie and xy charts keep their data
        as it is, and every other kind has its data converted by
        ConvertTo-DashboardChartData and carries its source. A chart whose title
        repeats the heading above it is added with no title. A note takes its
        first paragraph as its title when more blocks follow it and it reads as
        a short lead line; its tone is info unless it names one.

    .PARAMETER Section
        One section from the section model; its blocks are read.

    .OUTPUTS
        [object[]] The blocks, each an ordered dictionary whose t is h, p, ul,
        chart, table or note.
    #>
    [CmdletBinding()]
    param($Section)

    $blocks = [System.Collections.Generic.List[object]]::new()
    # A chart whose title repeats the heading above it shows the heading only.
    $lastHeading = ''
    foreach ($b in @($Section.blocks)) {
        if ($null -eq $b) { continue }
        # A table or line of figures a graphic on the page shows in full is left to the exports.
        if ($b.inGraphic -eq $true) { continue }
        switch ([string]$b.type) {
            'heading' {
                $lastHeading = (@($b.text) | ForEach-Object { [string]$_.text }) -join ''
                $blocks.Add([ordered]@{ t = 'h'; lvl = [int]$b.level; html = (ConvertTo-SectionRunsHtml @($b.text)) })
            }
            'paragraph' { $blocks.Add([ordered]@{ t = 'p'; html = (ConvertTo-SectionRunsHtml @($b.text)) }) }
            'list' { $blocks.Add([ordered]@{ t = 'ul'; items = @(Get-SectionListItems $b) }) }
            'chart' {
                # The dashboard draws pie and xy itself and every other kind
                # with the chart web part's renderers (dashboard-charts.js).
                if ($null -ne $b.data) {
                    $title = [string]$b.title
                    if ($title -and $title.Trim() -ieq $lastHeading.Trim()) { $title = '' }
                    if ([string]$b.kind -in 'pie', 'xy') {
                        $blocks.Add([ordered]@{ t = 'chart'; kind = [string]$b.kind; title = $title; data = $b.data })
                    } else {
                        $blocks.Add([ordered]@{
                            t = 'chart'
                            kind = [string]$b.kind
                            title = $title
                            data = (ConvertTo-DashboardChartData -Chart $b)
                            source = [string]$b.source
                        })
                    }
                }
            }
            'table' {
                $blocks.Add([ordered]@{
                        t       = 'table'
                        headers = @(@($b.columns) | ForEach-Object { ConvertTo-SectionRunsHtml @($_.text) })
                        align   = @(@($b.columns) | ForEach-Object { if ($_.align) { [string]$_.align } else { 'left' } })
                        rows    = @(foreach ($row in @($b.rows)) { , @(foreach ($cell in @($row)) { ConvertTo-SectionRunsHtml @($cell) }) })
                    })
            }
            'note' {
                # A callout: an optional short lead line, bullet items, paragraphs.
                $inner = @($b.blocks | Where-Object { $_ })
                $title = ''
                $first = $inner | Select-Object -First 1
                if ($inner.Count -gt 1 -and $first -and [string]$first.type -eq 'paragraph') {
                    $lead = ((@($first.text) | ForEach-Object { if ($_.text) { $_.text } }) -join '').Trim()
                    if ($lead -match '^[A-Za-z][\w &/-]{1,24}$') {
                        $title = ConvertTo-SectionRunsHtml @($first.text)
                        $inner = @($inner | Select-Object -Skip 1)
                    }
                }
                $tone = if ($b -is [System.Collections.IDictionary]) {
                    [string]$b['tone']
                } elseif ($b.PSObject.Properties['tone']) { [string]$b.tone } else { '' }
                $blocks.Add([ordered]@{
                        t     = 'note'
                        tone  = $(if ($tone) { $tone } else { 'info' })
                        title = $title
                        items = @($inner | Where-Object { [string]$_.type -eq 'list' } | ForEach-Object { Get-SectionListItems $_ })
                        paras = @($inner | Where-Object { [string]$_.type -eq 'paragraph' } | ForEach-Object { ConvertTo-SectionRunsHtml @($_.text) })
                    })
            }
            default { }
        }
    }
    return $blocks.ToArray()
}
