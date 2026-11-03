#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the watchlist content type's handlers, and for parity
    with the deployer they were taken from.

.DESCRIPTION
    The handlers are tested on the fixture repository: reading one item
    per folder, validation (the messages Deploy-CustomContent.ps1 logs,
    including the 3.5 MB inline limit), and the upload body with its rows
    and defaults (MIGRATION.md edit E9). The parity block lifts
    Deploy-CustomWatchlists out of Deploy/content/Deploy-CustomContent.ps1
    by AST, runs it over every watchlist in Content/Watchlists/ with the
    REST call captured, and holds each captured request (path, api-version
    and body) to the one the module builds for the same folder.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Watchlist.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Watchlist.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+, Pester 5+

    The parity block goes when Deploy-CustomContent.ps1 is removed at
    cut-over.
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $watchlistFolders = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content/Watchlists') -Directory) |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '_helpers/Parity.psm1') -Force
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

Describe 'Parity with Deploy-CustomContent.ps1' {
    BeforeAll {
        Import-Module (Join-Path $script:repoRoot 'Tests/_helpers/Import-ScriptFunctions.psm1') -Force
        Import-ScriptFunctions -Path (Join-Path $script:repoRoot 'Deploy/content/Deploy-CustomContent.ps1')
        function Write-PipelineMessage { param($Message, $Level) }
        # The deployer asks about watchlist.json first; the folder it is in
        # names the watchlist each captured request belongs to.
        function Test-ShouldDeployFile { param($FilePath) $script:legacyFolder = Split-Path -Parent $FilePath; $true }
        function Test-ContentDependencies { param($ContentPath) @{ Passed = $true; Missing = @() } }
        function Set-DeploymentItemState { param($FilePath, $Status) }
        function Invoke-SentinelApi {
            param($Uri, $Method, $Headers, $Body)
            $script:legacyCalls.Add([pscustomobject]@{ Folder = $script:legacyFolder; Uri = $Uri; Method = $Method; Body = $Body })
        }

        $script:workspacePath = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/ws'
        $script:BasePath = $script:repoRoot
        $script:WhatIf = $false
        $script:BaseUri = "https://management.azure.com$($script:workspacePath)"
        $script:SentinelApiVersion = '2025-09-01'
        $script:AuthHeader = @{}
        $script:legacyCalls = [System.Collections.Generic.List[object]]::new()
        $script:legacyCounters = Deploy-CustomWatchlists

        $script:legacyByFolder = @{}
        foreach ($call in $script:legacyCalls) {
            $relative = [System.IO.Path]::GetRelativePath($script:repoRoot, $call.Folder).Replace('\', '/')
            if (-not $script:legacyByFolder.ContainsKey($relative)) { $script:legacyByFolder[$relative] = [System.Collections.Generic.List[object]]::new() }
            $script:legacyByFolder[$relative].Add($call)
        }
        $script:context = InModuleScope iSOCDeployments -Parameters @{ W = $script:workspacePath } {
            param($W)
            New-iSOCContext -Value @{
                TenantId = 't'; SubscriptionId = '00000000-0000-0000-0000-000000000000'; ResourceGroup = 'rg'; WorkspaceName = 'ws'
                WorkspaceResourceId = $W; WorkspaceId = 'c'; Region = 'uksouth'; PlaybookResourceGroup = 'rg'; Environment = 'AzureCloud'
                IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'a'
            }
        }
        $script:moduleItems = @{}
        foreach ($item in Get-WatchlistItem -Repo $script:repoRoot) { $script:moduleItems[$item.RelativePath] = $item }
    }

    It 'sent a request for every watchlist it read' {
        $script:legacyCounters.Failed | Should -Be 0
        $script:legacyCounters.Skipped | Should -Be 0
        $script:legacyCalls.Count | Should -Be $script:moduleItems.Count
    }

    It 'sends <Path> as Deploy-CustomContent.ps1 does' -ForEach $watchlistFolders {
        $item = $script:moduleItems[$Path]
        Test-Item $item | Should -BeNullOrEmpty
        $request = Get-Request $item
        $legacy = @($script:legacyByFolder[$Path])
        $legacy.Count | Should -Be 1

        $path = InModuleScope iSOCDeployments -Parameters @{ C = $script:context; N = $request.ResourceName } {
            param($C, $N)
            $type = Get-iSOCContentTypeDefinition -Name Watchlist
            '{0}?api-version={1}' -f (Get-iSOCResourcePath -Context $C -ContentType $type -Name $N), (Get-iSOCApiVersion $type.ApiVersion)
        }
        "https://management.azure.com$path" | Should -BeExactly $legacy[0].Uri
        $legacy[0].Method | Should -Be 'Put'
        ConvertTo-ParityJson $request.Body | Should -BeExactly (ConvertTo-ParityJson $legacy[0].Body)
    }
}
