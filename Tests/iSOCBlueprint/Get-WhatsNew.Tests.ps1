#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the What's new capture and its topic map.

.DESCRIPTION
    Get-WhatsNew reads the Microsoft Sentinel and Defender XDR What's new
    pages on Microsoft Learn as Markdown. These tests drive the parser with
    small pages written in the two shapes (### items under ## months; and
    top-level bullets with a (Preview) or (GA) prefix), check the status,
    deadline and anchor rules, the fetch and its failure path with
    Invoke-WebRequest mocked, and that every topic in
    whats-new-topics.json names a real report page and maturity criterion.

.NOTES
    File:         Tests/iSOCBlueprint/Get-WhatsNew.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-14
    Version:      0.1.0
    Last Updated: 2026-10-14
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Get-WhatsNew.ps1')
    $script:sentinelUrl = 'https://learn.microsoft.com/en-us/azure/sentinel/whats-new'
    $script:defenderUrl = 'https://learn.microsoft.com/en-us/defender-xdr/whats-new'
    $script:sentinelMd = @(
        '---', 'title: What''s new', '---', '', '# What''s new', '', 'Intro.', '',
        '## September 2026', '', 'A month introduction.', '', '- Contents entry one', '- Contents entry two', '',
        '### Feature one is now generally available', '', 'Feature one does **this** and [that](/en-us/azure/sentinel/feature-one).', '',
        '### [Updated] Call to action: update automation by July 1, 2026 - names change', '', 'Update your rules before the date.', '',
        '## August 2026', '',
        '### Feature two (Preview)', '', 'Note', '', 'Feature two text.', '',
        '### Microsoft Sentinel in the Azure portal to be retired March 2027', '', 'Move to the Defender portal.', '',
        '## Not a month', '', '### Ignored', '', 'Under a heading that is not a month.'
    ) -join "`n"
    $script:defenderMd = @(
        '---', 'title: What''s new', '---', '', '# What''s new', '',
        '- [Other page](/en-us/defender-office-365/whats-new)', '',
        '## September 2026', '',
        '- (Preview) **Thing one** does something. For more information, see [Thing one](thing-one).',
        '- (GA) The following tables are now generally available:',
        '    - The `TableA` table holds A.',
        '    - The `TableB` table holds B.',
        '- A plain update with no prefix and no bold title, which runs on for a while. More text.', '',
        '## July 2026', '',
        '- (Preview) The `NewTable` table is available. The `OldTable` table is transitioning to it and remains accessible until July 1, 2026.'
    ) -join "`n"
}

Describe 'ConvertFrom-WhatsNewMarkdown, Sentinel shape' {
    BeforeAll { $script:s = @(ConvertFrom-WhatsNewMarkdown -Markdown $sentinelMd -Product 'Microsoft Sentinel' -PageUrl $sentinelUrl) }

    It 'reads each ### under a month as an item, and nothing under a heading that is not a month' {
        $s.Count | Should -Be 4
        @($s.Title) | Should -Not -Contain 'Ignored'
        @($s.Month | Select-Object -Unique) | Should -Be @('2026-09', '2026-08')
    }

    It 'skips a month''s introduction and contents list' {
        @($s.Title) | Should -Not -Contain 'Contents entry one'
        $s[0].Title | Should -Be 'Feature one is now generally available'
    }

    It 'gives each item a status' {
        @($s.Status) | Should -Be @('Generally available', 'Action needed', 'Preview', 'Retiring')
    }

    It 'links each item to its heading on the page, as Learn anchors it' {
        $s[1].Link | Should -Be ($sentinelUrl + '#updated-call-to-action-update-automation-by-july-1-2026---names-change')
    }

    It 'takes the first paragraph as the summary, as plain text, past a Note label' {
        $s[0].Summary | Should -Be 'Feature one does this and that.'
        $s[2].Summary | Should -Be 'Feature two text.'
        $s[0].LearnMore | Should -Be 'https://learn.microsoft.com/en-us/azure/sentinel/feature-one'
    }

    It 'reads the deadline a call to action or retirement names' {
        $s[1].Deadline | Should -Be '2026-07-01'
        $s[3].Deadline | Should -Be '2027-03'
        $s[0].Deadline | Should -BeNullOrEmpty
    }
}

Describe 'ConvertFrom-WhatsNewMarkdown, Defender XDR shape' {
    BeforeAll { $script:d = @(ConvertFrom-WhatsNewMarkdown -Markdown $defenderMd -Product 'Microsoft Defender XDR' -PageUrl $defenderUrl) }

    It 'reads each top-level bullet under a month as an item, not the links before the first month' {
        $d.Count | Should -Be 4
        @($d.Title) | Should -Not -Contain 'Other page'
    }

    It 'takes the bold text as the title and the prefix as the status' {
        $d[0].Title | Should -Be 'Thing one'
        $d[0].Status | Should -Be 'Preview'
        $d[1].Status | Should -Be 'Generally available'
        $d[2].Status | Should -Be 'Update'
    }

    It 'falls back to the first sentence for a title, and keeps nested bullets as detail' {
        $d[1].Title | Should -Be 'The following tables are now generally available'
        @($d[1].Details) | Should -Be @('The TableA table holds A.', 'The TableB table holds B.')
    }

    It 'links an item to its month on the page and resolves a relative Learn link beside the page' {
        $d[0].Link | Should -Be ($defenderUrl + '#september-2026')
        $d[0].LearnMore | Should -Be 'https://learn.microsoft.com/en-us/defender-xdr/thing-one'
    }

    It 'reads a transition with a cut-off as Retiring, with its date' {
        $d[3].Status | Should -Be 'Retiring'
        $d[3].Deadline | Should -Be '2026-07-01'
    }
}

Describe 'Get-WhatsNew' {
    It 'keeps the last Months months from both pages' {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = $(if ($Uri -like '*sentinel*') { $sentinelMd } else { $defenderMd }) } }
        $r = Get-WhatsNew -Months 1 -Now ([datetime]'2026-09-20')
        @($r.Items.Month | Select-Object -Unique) | Should -Be @('2026-09')
        @($r.Sources.Ok) | Should -Be @($true, $true)
        @($r.Items | Where-Object Product -EQ 'Microsoft Sentinel').Count | Should -Be 2
        Should -Invoke Invoke-WebRequest -Times 2 -ParameterFilter { $Headers.Accept -eq 'text/markdown' }
    }

    It 'records a page it cannot read and keeps the other' {
        Mock Invoke-WebRequest { if ($Uri -like '*sentinel*') { throw 'offline' } else { [pscustomobject]@{ Content = $defenderMd } } }
        $r = Get-WhatsNew -Months 12 -Now ([datetime]'2026-09-20')
        ($r.Sources | Where-Object Product -EQ 'Microsoft Sentinel').Ok | Should -BeFalse
        ($r.Sources | Where-Object Product -EQ 'Microsoft Sentinel').Error | Should -Match 'offline'
        @($r.Items.Product | Select-Object -Unique) | Should -Be @('Microsoft Defender XDR')
    }
}

Describe 'whats-new-topics.json' {
    BeforeAll {
        $script:topics = @((Get-Content (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources/whats-new-topics.json') -Raw | ConvertFrom-Json).topics)
        $script:criteria = @((Get-Content (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources/maturity-criteria.json') -Raw | ConvertFrom-Json).criteria.id)
        $script:renderer = Get-Content (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Convert-SentinelInventoryToMarkdown.ps1') -Raw
    }

    It 'gives every topic a pattern that compiles, a report page the renderer writes and real criteria' {
        $topics.Count | Should -BeGreaterThan 10
        foreach ($t in $topics) {
            { [regex]::new([string]$t.match, 'IgnoreCase') } | Should -Not -Throw -Because $t.id
            $renderer | Should -Match ([regex]::Escape("'$($t.section).md'")) -Because "$($t.id) links to $($t.section)"
            foreach ($c in @($t.criteria)) { $criteria | Should -Contain $c -Because $t.id }
        }
    }

    It 'is captured by the collector as a single-object file' {
        $collector = Get-Content (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Export-SentinelInventory.ps1') -Raw
        $collector | Should -Match "Try-Capture 'whats-new' \{"
        $collector | Should -Match "Save-Json -FileName 'whats-new\.json' -Data \(Get-WhatsNew -Months 12\)"
        $collector | Should -Match "'whats-new\.json'\s*\)"
    }

    It 'keeps topic ids unique' {
        @($topics.id | Sort-Object -Unique).Count | Should -Be $topics.Count
    }
}
