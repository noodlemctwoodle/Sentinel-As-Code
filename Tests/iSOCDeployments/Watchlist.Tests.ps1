#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the watchlist content type's handlers.

.DESCRIPTION
    The handlers are tested on the fixture repository: reading one item
    per folder, validation (the messages Deploy-CustomContent.ps1 logged,
    including the 3.5 MB inline limit), and the upload body with its rows
    and defaults (MIGRATION.md edit E9). Every watchlist folder under
    Content/Watchlists/ in this repository is read through the ReadRepo
    handler, must pass Test-iSOCWatchlist with no issues, and must build a
    request through the ToRequest handler. Parity with
    Deploy-CustomContent.ps1 was proven on release/26.11.0 before the
    script was removed.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Watchlist.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Watchlist.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $watchlistFolders = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content/Watchlists') -Directory) |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'

    function Get-WatchlistItem {
        param([string] $Repo = $script:fixtureRepo)
        InModuleScope iSOCDeployments -Parameters @{ R = $Repo } {
            param($R)
            $type = Get-iSOCContentTypeDefinition -Name Watchlist
            Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $R; ContentType = $type }
        }
    }
    function Get-Request {
        param([psobject] $Item)
        InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) ConvertTo-iSOCWatchlistRequest -Item $I }
    }
    function Test-Item {
        param([psobject] $Item)
        @(InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) Test-iSOCWatchlist -Item $I })
    }
    function New-WatchlistFolder {
        param([string] $Name, [string] $Metadata, [string] $Csv)
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $folder = Join-Path $repo "Content/Watchlists/$Name"
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        if ($null -ne $Metadata) { Set-Content -LiteralPath (Join-Path $folder 'watchlist.json') -Value $Metadata }
        if ($null -ne $Csv) { Set-Content -LiteralPath (Join-Path $folder 'data.csv') -Value $Csv -NoNewline }
        @(Get-WatchlistItem -Repo $repo)[0]
    }

    $script:items = @(Get-WatchlistItem)
    $script:vip = $script:items | Where-Object { $_.RelativePath -like '*/vipUsers' }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Watchlist handlers' {
    It 'reads one item per folder, named by its alias in lower case' {
        @($script:items.RelativePath) | Should -Be @('Content/Watchlists/emptyFolder', 'Content/Watchlists/noData', 'Content/Watchlists/vipUsers')
        $script:vip.Identity | Should -BeExactly 'vipusers'
        $script:vip.Name | Should -Be 'Fixture VIP users'
        $script:vip.MetadataPath | Should -BeLike '*vipUsers*watchlist.json'
        $script:vip.CsvPath | Should -BeLike '*vipUsers*data.csv'
    }

    It 'names a folder without a watchlist.json by the folder, with no parse error' {
        $empty = $script:items | Where-Object { $_.RelativePath -like '*/emptyFolder' }
        $empty.Name | Should -Be 'emptyFolder'
        $empty.Data | Should -BeNullOrEmpty
        $empty.ParseError | Should -BeNullOrEmpty
    }

    It 'says what is missing: <Case>' -ForEach @(
        @{ Case = 'the metadata'; Leaf = 'emptyFolder'; Message = 'watchlist.json not found.' }
        @{ Case = 'the rows'; Leaf = 'noData'; Message = 'data.csv not found.' }
    ) {
        Test-Item ($script:items | Where-Object { $_.RelativePath -like "*/$Leaf" }) | Should -Be @($Message)
    }

    It 'passes a complete watchlist' {
        Test-Item $script:vip | Should -BeNullOrEmpty
    }

    It 'reports a watchlist.json that does not parse as a parse error' {
        $item = New-WatchlistFolder -Name broken -Metadata '{ not json' -Csv "A`n1"
        $item.ParseError | Should -BeLike 'watchlist.json does not parse*'
        @(Test-Item $item)[0] | Should -BeLike 'watchlist.json does not parse*'
    }

    It 'needs the alias, display name and search key' {
        $item = New-WatchlistFolder -Name partial -Metadata '{ "watchlistAlias": "partial", "displayName": "Partial" }' -Csv "A`n1"
        Test-Item $item | Should -Be @('watchlist.json missing required fields (watchlistAlias, displayName, itemsSearchKey).')
    }

    It 'refuses rows over the 3.5 MB inline upload limit' {
        $item = New-WatchlistFolder -Name large -Metadata '{ "watchlistAlias": "large", "displayName": "Large", "itemsSearchKey": "A" }' -Csv ("A`n" + ('x' * 3700000))
        @(Test-Item $item)[0] | Should -BeLike 'data.csv exceeds 3.5 MB inline upload limit*Upload manually via portal.'
    }

    It 'builds the upload the deployer sends, with the rows inline' {
        $request = Get-Request $script:vip
        $request.ResourceName | Should -BeExactly 'vipUsers'
        $p = $request.Body.properties
        $p.watchlistAlias | Should -Be 'vipUsers'
        $p.displayName | Should -Be 'Fixture VIP users'
        $p.provider | Should -Be 'Fixture'
        $p.itemsSearchKey | Should -Be 'UserPrincipalName'
        $p.source | Should -Be 'Local File'
        $p.sourceType | Should -Be 'Local'
        $p.contentType | Should -Be 'Text/Csv'
        $p.numberOfLinesToSkip | Should -Be 0
        $p.rawContent | Should -BeExactly (Get-Content -LiteralPath $script:vip.CsvPath -Raw)
    }

    It 'defaults the description and provider when the file has neither (MIGRATION.md edit E9)' {
        $item = New-WatchlistFolder -Name bare -Metadata '{ "watchlistAlias": "bare", "displayName": "Bare", "itemsSearchKey": "A" }' -Csv "A`n1"
        $p = (Get-Request $item).Body.properties
        $p.description | Should -BeExactly ''
        $p.provider | Should -Be 'Custom'
    }
}

Describe 'Content/Watchlists in this repository' {
    BeforeAll {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        $script:repoType = InModuleScope iSOCDeployments { Get-iSOCContentTypeDefinition -Name Watchlist }
        function Invoke-RepoHandler {
            param([string] $Handler, [hashtable] $Parameters)
            InModuleScope iSOCDeployments -Parameters @{ T = $script:repoType; H = $Handler; P = $Parameters } {
                param($T, $H, $P)
                Invoke-iSOCContentTypeHandler -ContentType $T -Handler $H -Parameters $P
            }
        }
        $script:repoItems = @{}
        foreach ($item in Invoke-RepoHandler -Handler ReadRepo -Parameters @{ RepoPath = $script:repoRoot; ContentType = $script:repoType }) {
            $script:repoItems[$item.RelativePath] = $item
        }
    }

    It 'reads, validates and builds <Path>' -ForEach $watchlistFolders {
        $item = $script:repoItems[$Path]
        $item | Should -Not -BeNullOrEmpty -Because 'the ReadRepo handler reads everything under Content/Watchlists'
        Test-Item $item | Should -BeNullOrEmpty
        { $script:repoRequest = Invoke-RepoHandler -Handler ToRequest -Parameters @{ Item = $item } } | Should -Not -Throw
        $script:repoRequest.Body | Should -Not -BeNullOrEmpty
    }
}
