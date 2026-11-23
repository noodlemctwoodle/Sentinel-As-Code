#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the workbook content type's handlers.

.DESCRIPTION
    The handlers are tested on the fixture repository: reading one item
    per folder, validation (a missing template skips, a metadata.json that
    does not parse fails), and the request body: metadata over the
    defaults, the workbookId derived from the workspace and folder name
    when metadata has none (checked against a value worked out outside
    PowerShell), and the inner serializedData of an ARM-wrapped template.
    Every workbook folder under Content/Workbooks/ in this repository is
    read through the ReadRepo handler, must pass Test-iSOCWorkbook with no
    issues, and must build a request through the ToRequest handler.
    Parity with Deploy-CustomContent.ps1 was proven on release/26.11.0
    before the script was removed.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Workbook.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Workbook.Tests.ps1
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
    $workbookFolders = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content/Workbooks') -Directory) |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'
    $script:workspacePath = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/ws'
    $script:context = InModuleScope iSOCDeployments -Parameters @{ W = $script:workspacePath } {
        param($W)
        New-iSOCContext -Value @{
            TenantId = 't'; SubscriptionId = '00000000-0000-0000-0000-000000000000'; ResourceGroup = 'rg'; WorkspaceName = 'ws'
            WorkspaceResourceId = $W; WorkspaceId = 'c'; Region = 'uksouth'; PlaybookResourceGroup = 'rg'; Environment = 'AzureCloud'
            IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'a'
        }
    }

    function Get-WorkbookItem {
        <#
        .SYNOPSIS
            Reads the workbook items of a repository with the ReadRepo handler of the Workbook content type.
        .PARAMETER Repo
            The repository path; the fixture repository by default.
        #>
        param([string] $Repo = $script:fixtureRepo)
        InModuleScope iSOCDeployments -Parameters @{ R = $Repo } {
            param($R)
            $type = Get-iSOCContentTypeDefinition -Name Workbook
            Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $R; ContentType = $type }
        }
    }
    function Get-Request {
        <#
        .SYNOPSIS
            Returns the request the module builds for a workbook item.
        .PARAMETER Item
            The workbook item.
        #>
        param([psobject] $Item)
        InModuleScope iSOCDeployments -Parameters @{ I = $Item; C = $script:context } { param($I, $C) ConvertTo-iSOCWorkbookRequest -Item $I -Context $C }
    }
    function Test-Item {
        <#
        .SYNOPSIS
            Returns the validation errors the module reports for a workbook item.
        .PARAMETER Item
            The workbook item.
        #>
        param([psobject] $Item)
        @(InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) Test-iSOCWorkbook -Item $I })
    }
    function New-WorkbookFolder {
        <#
        .SYNOPSIS
            Writes a workbook folder with the given workbook and metadata into a new temporary repository and returns the item read from it.
        .PARAMETER Name
            The name of the workbook folder.
        .PARAMETER Workbook
            The text of workbook.json; the file is left out when null.
        .PARAMETER Metadata
            The text of metadata.json; the file is left out when empty.
        #>
        param([string] $Name, [string] $Workbook, [string] $Metadata)
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $folder = Join-Path $repo "Content/Workbooks/$Name"
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        if ($null -ne $Workbook) { Set-Content -LiteralPath (Join-Path $folder 'workbook.json') -Value $Workbook -NoNewline }
        if ($Metadata) { Set-Content -LiteralPath (Join-Path $folder 'metadata.json') -Value $Metadata }
        @(Get-WorkbookItem -Repo $repo)[0]
    }

    $script:items = @(Get-WorkbookItem)
    $script:overview = $script:items | Where-Object { $_.RelativePath -like '*/FixtureOverview' }
    $script:wrapped = $script:items | Where-Object { $_.RelativePath -like '*/ArmWrapped' }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Workbook handlers' {
    BeforeEach { Mock -ModuleName iSOCDeployments Write-iSOCLog { } }

    It 'reads one item per folder, recording only workbook.json in the state' {
        @($script:items.RelativePath) | Should -Be @('Content/Workbooks/ArmWrapped', 'Content/Workbooks/FixtureOverview', 'Content/Workbooks/NoTemplate')
        $script:overview.Identity | Should -BeExactly '7d0f5a3e-2b1c-4e8f-9a6d-3c2b1a0f9e8d'
        $script:overview.Name | Should -Be 'Fixture overview'
        @($script:overview.Files) | Should -Be @($script:overview.WorkbookPath)
        $script:overview.WorkbookPath | Should -BeLike '*FixtureOverview*workbook.json'
    }

    It 'names a folder without metadata by the folder, split at its capitals (MIGRATION.md edit E16)' {
        $script:wrapped.Name | Should -BeExactly 'Arm Wrapped'
        (Get-Request $script:wrapped).Body.properties.displayName | Should -BeExactly 'Arm Wrapped'
        (Get-Request (New-WorkbookFolder -Name 'SOCOverviewV2' -Workbook '{}')).Body.properties.displayName | Should -BeExactly 'SOCOverview V2'
        $script:wrapped.Data | Should -BeNullOrEmpty
        $script:wrapped.Identity | Should -BeNullOrEmpty
    }

    It 'skips a folder without workbook.json' {
        Test-Item ($script:items | Where-Object { $_.RelativePath -like '*/NoTemplate' }) | Should -Be @('workbook.json not found.')
    }

    It 'passes a complete workbook, with or without metadata' {
        Test-Item $script:overview | Should -BeNullOrEmpty
        Test-Item $script:wrapped | Should -BeNullOrEmpty
    }

    It 'reports a metadata.json that does not parse as a parse error' {
        $item = New-WorkbookFolder -Name Broken -Workbook '{}' -Metadata '{ not json'
        $item.ParseError | Should -BeLike 'metadata.json does not parse*'
        @(Test-Item $item)[0] | Should -BeExactly $item.ParseError
    }

    It 'builds the body the deployer sends, from the template and its metadata' {
        $request = Get-Request $script:overview
        $request.ResourceName | Should -BeExactly '7d0f5a3e-2b1c-4e8f-9a6d-3c2b1a0f9e8d'
        $request.Body.location | Should -BeExactly 'uksouth'
        $request.Body.kind | Should -BeExactly 'shared'
        $p = $request.Body.properties
        $p.displayName | Should -Be 'Fixture overview'
        $p.category | Should -BeExactly 'workbook'
        $p.version | Should -BeExactly '1.0'
        $p.sourceId | Should -BeExactly $script:workspacePath
        $p.serializedData | Should -BeExactly (Get-Content -LiteralPath $script:overview.WorkbookPath -Raw)
    }

    It 'derives the workbookId from the workspace and the folder when metadata has none' {
        # SHA-256 of '<workspace resource id>-ArmWrapped', first 16 bytes as a
        # .NET Guid, worked out with Python's uuid.UUID(bytes_le=...).
        $request = Get-Request $script:wrapped
        $request.ResourceName | Should -BeExactly 'eb5368a8-b550-f9c5-9977-46194d2bcdd8'
        $request.Identity | Should -BeExactly 'eb5368a8-b550-f9c5-9977-46194d2bcdd8'
        $request.Body.properties.category | Should -BeExactly 'sentinel'
    }

    It 'sends the inner serializedData of an ARM-wrapped template' {
        $inner = (Get-Content -LiteralPath $script:wrapped.WorkbookPath -Raw | ConvertFrom-Json).resources[0].properties.serializedData
        (Get-Request $script:wrapped).Body.properties.serializedData | Should -BeExactly $inner
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Message -like 'ARM-wrapped workbook detected*' }
    }

    It 'sends the file as it is, with a warning, when <Case>' -ForEach @(
        @{ Case = 'an ARM template has no workbook resource'; Workbook = '{ "resources": [ { "type": "Microsoft.Web/sites" } ] }'; Warning = '*no Microsoft.Insights/workbooks serializedData*' }
        @{ Case = 'the template does not parse'; Workbook = '{ not json'; Warning = '*could not be parsed for ARM detection*' }
    ) {
        $item = New-WorkbookFolder -Name Odd -Workbook $Workbook
        (Get-Request $item).Body.properties.serializedData | Should -BeExactly $Workbook
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Level -eq 'Warning' -and $Message -like $Warning }
    }
}

Describe 'Content/Workbooks in this repository' {
    BeforeAll {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        $script:repoType = InModuleScope iSOCDeployments { Get-iSOCContentTypeDefinition -Name Workbook }
        function Invoke-RepoHandler {
            <#
            .SYNOPSIS
                Runs a handler of the content type under test.
            .PARAMETER Handler
                The name of the handler to run.
            .PARAMETER Parameters
                The parameters passed to the handler.
            #>
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

    It 'reads, validates and builds <Path>' -ForEach $workbookFolders {
        $item = $script:repoItems[$Path]
        $item | Should -Not -BeNullOrEmpty -Because 'the ReadRepo handler reads everything under Content/Workbooks'
        Test-Item $item | Should -BeNullOrEmpty
        { $script:repoRequest = Invoke-RepoHandler -Handler ToRequest -Parameters @{ Item = $item; Context = $script:context } } | Should -Not -Throw
        $script:repoRequest.Body | Should -Not -BeNullOrEmpty
    }
}
