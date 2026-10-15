#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the bookmarks capture's fallback to the HuntingBookmark table.

.DESCRIPTION
    The bookmarks list API refuses a response over about 8 MB and has no
    paging. The collector then keeps the count the error reports and lists
    the bookmarks from the HuntingBookmark table, where Sentinel logs every
    bookmark and each change to it. These tests hold the capture to that:
    the row conversion into the API's item shape, and the query and files
    the capture writes.

.NOTES
    File:         Tests/iSOCBlueprint/Bookmarks-Capture.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.1.0
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $collectorPath = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Export-SentinelInventory.ps1'
    $collector = Get-Content $collectorPath -Raw
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($collectorPath, [ref]$null, [ref]$null)
    . ([scriptblock]::Create($ast.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq 'ConvertFrom-HuntingBookmarkRow' }, $true).Extent.Text))
    # The bookmarks capture's own text, up to the next capture.
    $start = $collector.IndexOf("Try-Capture 'bookmarks'")
    $script:capture = $collector.Substring($start, $collector.IndexOf("Try-Capture 'hunts'") - $start)

    function New-BookmarkRow([string]$Tags) {
        [pscustomobject]@{
            BookmarkId      = '73e01a99-5cd7-4139-a149-9f2736ff2ab5'
            BookmarkName    = 'Lateral movement from VPN'
            CreatedTime     = '2026-09-30T08:15:00Z'
            LastUpdatedTime = '2026-10-01T10:00:00Z'
            Tags            = $Tags
            Notes           = 'Seen on three hosts'
        }
    }
}

Describe 'ConvertFrom-HuntingBookmarkRow' {
    It 'gives the row the bookmarks API item shape' {
        $item = ConvertFrom-HuntingBookmarkRow -Row (New-BookmarkRow 'hunt')
        $item.name | Should -Be '73e01a99-5cd7-4139-a149-9f2736ff2ab5'
        $item.properties.displayName | Should -Be 'Lateral movement from VPN'
        $item.properties.created | Should -Be '2026-09-30T08:15:00Z'
        $item.properties.updated | Should -Be '2026-10-01T10:00:00Z'
        $item.properties.notes | Should -Be 'Seen on three hosts'
    }

    It 'splits the comma-separated Tags into labels' {
        $labels = @((ConvertFrom-HuntingBookmarkRow -Row (New-BookmarkRow 'hunt, vpn ,')).properties.labels)
        $labels.Count | Should -Be 2
        $labels[0] | Should -Be 'hunt'
        $labels[1] | Should -Be 'vpn'
    }

    It 'reads Tags written as a JSON array' {
        $labels = @((ConvertFrom-HuntingBookmarkRow -Row (New-BookmarkRow '["c2", "beacon"]')).properties.labels)
        $labels.Count | Should -Be 2
        $labels[1] | Should -Be 'beacon'
    }

    It 'gives no labels when there are no tags' {
        @((ConvertFrom-HuntingBookmarkRow -Row (New-BookmarkRow '')).properties.labels).Count | Should -Be 0
        @((ConvertFrom-HuntingBookmarkRow -Row (New-BookmarkRow $null)).properties.labels).Count | Should -Be 0
    }
}

Describe 'The bookmarks capture when the list is refused as too large' {
    It 'keeps the count the error reports before reading the table' {
        $script:capture.Contains('too large[^)]*?(\d+)\s+items') | Should -BeTrue
        $script:capture.IndexOf('''bookmarks-count.json''') | Should -BeLessThan $script:capture.IndexOf('| summarize arg_max')
    }

    It 'lists each bookmark once, at its latest entry, less the deleted ones' {
        $script:capture | Should -Match 'HuntingBookmark\s*\n\| summarize arg_max\(TimeGenerated, [^)]*SoftDeleted\) by BookmarkId'
        $script:capture | Should -Match '\| where not\(coalesce\(SoftDeleted, false\)\)'
    }

    It 'leaves out the query text, result row and entities that make the list large' {
        $kql = [regex]::Match($script:capture, '(?s)@''\s*\nHuntingBookmark.*?\n''@').Value
        $kql | Should -Not -BeNullOrEmpty
        $kql | Should -Not -Match 'QueryResultRow|QueryText|Entities'
    }

    It 'writes the list to bookmarks-from-logs.json, never bookmarks.json' {
        $script:capture | Should -Match 'Save-Json -FileName ''bookmarks-from-logs\.json'' -Data \$listed'
        ([regex]::Matches($script:capture, 'Save-Json -FileName ''bookmarks\.json''')).Count | Should -Be 1
    }

    It 'warns only when the table cannot be read' {
        $script:capture | Should -Match 'Write-Information "Bookmarks list refused as too large'
        $script:capture | Should -Match 'Write-Warning "Bookmarks list refused as too large and the HuntingBookmark table could not be read'
    }
}
