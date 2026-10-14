#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the iSOCBlueprint module's manifest, help and public
    commands.

.DESCRIPTION
    The public commands are thin wrappers over the engine scripts, so most
    of what can go wrong is in how they map their parameters. These tests
    stand in for the engine (Invoke-iSOCBlueprintEngine is mocked) and
    check each command passes the right script the right parameters, that
    New-iSOCBlueprint runs the steps each format needs and refuses
    contradictory requests, and that the prerequisite list agrees with the
    engine scripts' own #Requires. They also hold the manifest, the help
    and the file headers to the repository's conventions.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Module.Tests.ps1

    Runs the whole suite.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Module.Tests.ps1 -FullName '*New-iSOCBlueprint*'

    Runs only the one-line command's tests.

.NOTES
    File:         Tests/iSOCBlueprint/Module.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.3.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $moduleRoot = Join-Path $repoRoot 'Modules/iSOCBlueprint'
    $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot 'iSOCBlueprint.psd1')
    $commands = @($manifest.FunctionsToExport | ForEach-Object { @{ Name = $_ } })
    $ownFiles = @(
        Get-Item -LiteralPath (Join-Path $moduleRoot 'iSOCBlueprint.psm1')
        Get-ChildItem -LiteralPath (Join-Path $moduleRoot 'Public'), (Join-Path $moduleRoot 'Private'), (Join-Path $moduleRoot 'Engine/Private/Vendor') -Filter '*.ps1' -File
    ) | ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:moduleRoot = Join-Path $script:repoRoot 'Modules/iSOCBlueprint'
    $script:engineRoot = Join-Path $script:moduleRoot 'Engine'
    Import-Module (Join-Path $script:moduleRoot 'iSOCBlueprint.psd1') -Force
    $script:manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:moduleRoot 'iSOCBlueprint.psd1')
}

AfterAll {
    Remove-Module iSOCBlueprint -ErrorAction SilentlyContinue
}

Describe 'Manifest' {
    It 'is a valid module manifest' {
        { Test-ModuleManifest -Path (Join-Path $script:moduleRoot 'iSOCBlueprint.psd1') -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports one command per file in Public/' {
        $files = @(Get-ChildItem -LiteralPath (Join-Path $script:moduleRoot 'Public') -Filter '*.ps1' -File | ForEach-Object BaseName | Sort-Object)
        @($script:manifest.FunctionsToExport | Sort-Object) | Should -Be $files
    }

    It 'exports exactly the listed commands once imported' {
        @((Get-Module iSOCBlueprint).ExportedFunctions.Keys | Sort-Object) | Should -Be @($script:manifest.FunctionsToExport | Sort-Object)
    }

    It 'declares no required modules, so a JSON-only user needs none of the optional tools' {
        $script:manifest.ContainsKey('RequiredModules') | Should -BeFalse
    }

    It 'has a three-part version no older than the newest release in the CHANGELOG' {
        $version = [version]$script:manifest.ModuleVersion
        $script:manifest.ModuleVersion | Should -Match '^\d+\.\d+\.\d+$'
        $changelog = Get-Content -LiteralPath (Join-Path $script:repoRoot 'Docs/Releases/CHANGELOG.md')
        $released = @($changelog | ForEach-Object { if ($_ -match '^## (\d+\.\d+(?:\.\d+)?)\b') { [version]$Matches[1] } } | Sort-Object -Descending)
        $released.Count | Should -BeGreaterThan 0
        $version | Should -BeGreaterOrEqual $released[0]
    }
}

Describe 'Help for <Name>' -ForEach $commands {
    BeforeAll {
        $script:help = Get-Help $Name -Full
        $script:command = Get-Command $Name
    }

    It 'has a synopsis, a description and an example' {
        $script:help.Synopsis | Should -Not -BeNullOrEmpty
        $script:help.Synopsis | Should -Not -Match "^\s*$([regex]::Escape($Name))"
        ($script:help.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty
        @($script:help.Examples.Example).Count | Should -BeGreaterThan 0
    }

    It 'documents every parameter' {
        $common = [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
        foreach ($p in $script:command.Parameters.Keys | Where-Object { $_ -notin $common }) {
            $entry = @($script:help.Parameters.Parameter | Where-Object Name -eq $p)
            ($entry.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty -Because "-$p needs a description"
        }
    }

    It 'keeps the product name out of its name and synopsis' {
        $Name | Should -Not -Match 'Sentinel'
        $script:help.Synopsis | Should -Not -Match 'Sentinel'
    }
}

Describe 'File header of <Path>' -ForEach $ownFiles {
    It 'opens with the PowerShell floor and names its own path' {
        $text = Get-Content -LiteralPath (Join-Path $script:repoRoot $Path) -Raw
        $text | Should -Match '^#Requires -Version 7\.2\r?\n'
        $text | Should -Match ("(?m)^\s*File:\s+" + [regex]::Escape($Path) + '\s*$')
    }
}

Describe 'Prerequisites' {
    BeforeAll {
        $script:requirements = & (Get-Module iSOCBlueprint) { Get-iSOCBlueprintRequirement }
        function Get-ScriptRequirement {
            param([string] $Relative)
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:engineRoot $Relative), [ref]$null, [ref]$null)
            $ast.ScriptRequirements
        }
    }

    It 'lists the modules the collector requires, for Collect' {
        $engine = @((Get-ScriptRequirement 'Export-SentinelInventory.ps1').RequiredModules.Name | Sort-Object)
        $listed = @($script:requirements | Where-Object { $_.Kind -eq 'Module' -and $_.Required -and $_.Step -contains 'Collect' } | ForEach-Object Name | Sort-Object)
        $listed | Should -Be $engine
    }

    It 'lists the modules the renderer requires, for Render' {
        $engine = @((Get-ScriptRequirement 'Convert-SentinelInventoryToMarkdown.ps1').RequiredModules.Name | Sort-Object)
        $listed = @($script:requirements | Where-Object { $_.Kind -eq 'Module' -and $_.Step -contains 'Render' } | ForEach-Object Name | Sort-Object)
        $listed | Should -Be $engine
    }

    It 'matches the publisher and set-up scripts on PowerShell and PnP versions, for Publish' {
        foreach ($relative in 'SharePoint/Publish-SentinelDocsSite.ps1', 'SharePoint/Initialize-SentinelDocsSite.ps1') {
            $r = Get-ScriptRequirement $relative
            $pnp = $r.RequiredModules | Where-Object Name -eq 'PnP.PowerShell'
            ($script:requirements | Where-Object Name -eq 'PnP.PowerShell').MinimumVersion | Should -Be ([string]$pnp.Version)
            $ps = $script:requirements | Where-Object { $_.Kind -eq 'PowerShell' -and $_.Step -contains 'Publish' } | Sort-Object { [version]$_.MinimumVersion } | Select-Object -Last 1
            [version]$ps.MinimumVersion | Should -Be ([version]('{0}.{1}' -f $r.RequiredPSVersion.Major, $r.RequiredPSVersion.Minor))
        }
    }

    It 'returns one result per requirement with the documented properties' {
        $all = @(Test-iSOCBlueprintPrerequisite)
        $all.Count | Should -Be @($script:requirements).Count
        foreach ($p in 'Name', 'Step', 'Required', 'Found', 'Version', 'Detail') { $all[0].PSObject.Properties.Name | Should -Contain $p }
    }

    It 'limits the list to the steps asked for' {
        $word = @(Test-iSOCBlueprintPrerequisite -Step Word)
        @($word | Where-Object Name -eq 'pandoc').Count | Should -Be 1
        @($word | Where-Object Name -like 'Az.*').Count | Should -Be 0
        foreach ($r in $word) { $r.Step | Should -Be @('Word') }
    }

    It 'answers yes or no with -Quiet' {
        Test-iSOCBlueprintPrerequisite -Step Site -Quiet | Should -BeOfType [bool]
        Test-iSOCBlueprintPrerequisite -Step Site -Quiet | Should -BeTrue
    }
}

Describe 'Collector API versions' {
    It 'reads alert rules with the preview API, which carries subTechniques, and falls back to GA' {
        $collector = Get-Content -LiteralPath (Join-Path $script:engineRoot 'Export-SentinelInventory.ps1') -Raw
        $block = [regex]::Match($collector, "(?s)Try-Capture 'alert-rules' \{.*?\n\}").Value
        $block | Should -Match '/alertRules" -ApiVersion \$apiVersions\.SentinelPreview'
        $block | Should -Match '(?s)catch \{.*/alertRules" -ApiVersion \$apiVersions\.Sentinel\s'
    }
}

Describe 'Incident closure capture' {
    It 'counts closed incidents by who closed them, exporting the category and never the name' {
        $collector = Get-Content -LiteralPath (Join-Path $script:engineRoot 'Export-SentinelInventory.ps1') -Raw
        $block = [regex]::Match($collector, "(?s)Try-Capture 'incidents-summary' \{.*?\n\}").Value
        $block | Should -Match 'ModifiedBy contains "Automation", "AutomationRule"'
        $block | Should -Match '"DefenderXdr"'
        $block | Should -Match '"Analyst"'
        $block | Should -Match 'summarize N = count\(\) by By'
        $block | Should -Match 'OpenBySeverity = toscalar\(openBySev\), ClosedBy = toscalar\(closedBy\)'
        # ModifiedBy only feeds the case(); the summarised output holds the category.
        $block | Should -Not -Match 'make_set\(ModifiedBy|make_list\(ModifiedBy|by ModifiedBy'
    }
}

Describe 'SharePoint publisher name' {
    It 'defaults to the iSOC Blueprint name and renames an app found under an earlier one' {
        $setup = Get-Content -LiteralPath (Join-Path $script:repoRoot 'Deploy/setup/Setup-SharePointPublisher.ps1') -Raw
        $init = Get-Content -LiteralPath (Join-Path $script:engineRoot 'SharePoint/Initialize-SentinelDocsSite.ps1') -Raw
        foreach ($s in $setup, $init) { $s | Should -Match "\`$PublisherAppName = 'iSOC Blueprint SharePoint publisher'" }
        $setup | Should -Match "foreach \(\`$legacyName in 'Sentinel Blueprint SharePoint publisher', 'Sentinel Documenter SharePoint publisher'\)"
    }
}

Describe 'Blueprint output stays off GitHub' {
    # Output from a real workspace is tenant configuration. Only the test
    # fixtures' _raw folders may be tracked.
    BeforeAll {
        $script:blocked = '(^|/)(SecurityDocs|BlueprintRuns)/|(^|/)_raw/'
        $script:allowed = '^Tests/(.*/)?Fixtures/'
        $script:hook = Join-Path $script:repoRoot '.githooks/pre-push'
    }

    It 'is not tracked anywhere in the repository' {
        $tracked = @(git -C $script:repoRoot ls-files) | Where-Object { $_ -match $script:blocked -and $_ -notmatch $script:allowed }
        $tracked | Should -BeNullOrEmpty
    }

    It 'is ignored by git wherever the module writes it' {
        foreach ($p in 'SecurityDocs/ws/_raw/a.json', 'BlueprintRuns/ws/sections/index.json', 'out/ws/_raw/a.json') {
            git -C $script:repoRoot check-ignore -q --no-index $p
            $LASTEXITCODE | Should -Be 0 -Because "$p is Blueprint output"
        }
        git -C $script:repoRoot check-ignore -q --no-index 'Tests/iSOCBlueprint/Fixtures/sample/_raw/new.json'
        $LASTEXITCODE | Should -Be 1 -Because 'fixture captures are tracked'
    }

    It 'pre-push refuses a GitHub push that carries it and lets the rest through' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
        $repo = Join-Path $TestDrive 'hook-repo'
        git init -q $repo
        git -C $repo config user.email 'test@example.com'
        git -C $repo config user.name 'test'
        $commit = {
            param([string] $Path, [switch] $Force)
            $full = Join-Path $repo $Path
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            '{}' | Set-Content -LiteralPath $full
            if ($Force) { git -C $repo add -f -- $Path } else { git -C $repo add -- $Path }
            git -C $repo commit -q -m $Path
            git -C $repo rev-parse HEAD
        }
        $clean = & $commit 'README.md'
        $fixture = & $commit 'Tests/iSOCBlueprint/Fixtures/sample/_raw/alert-rules.json'
        $leak = & $commit 'SecurityDocs/law-test/_raw/alert-rules.json' -Force
        $zero = '0' * 40
        $push = {
            param([string] $Url, [string] $Sha)
            Push-Location $repo
            try { "refs/heads/main $Sha refs/heads/main $zero" | sh $script:hook origin $Url 2>$null | Out-Null; $LASTEXITCODE }
            finally { Pop-Location }
        }
        & $push 'https://github.com/owner/repo.git' $clean | Should -Be 0
        & $push 'https://github.com/owner/repo.git' $fixture | Should -Be 0
        & $push 'https://github.com/owner/repo.git' $leak | Should -Be 1
        & $push 'git@github.com:owner/repo.git' $leak | Should -Be 1
        & $push 'https://dev.azure.com/org/project/_git/repo' $leak | Should -Be 0
    }
}

Describe 'Invoke-iSOCBlueprintEngine' {
    BeforeAll {
        $script:fakeEngine = Join-Path $TestDrive 'engine'
        New-Item -ItemType Directory -Path $script:fakeEngine -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:fakeEngine 'Echo.ps1') -Value @'
[CmdletBinding(SupportsShouldProcess)]
param([string] $Name, [string] $Other)
$undefinedProperty = ([pscustomobject]@{ a = 1 }).b
[pscustomobject]@{ Bound = @($PSBoundParameters.Keys | Sort-Object); WhatIf = [bool]$WhatIfPreference; Strict = ($null -eq $undefinedProperty) }
'@
        Set-Content -LiteralPath (Join-Path $script:fakeEngine 'Plain.ps1') -Value @'
[CmdletBinding()]
param([string] $Name)
[pscustomobject]@{ Bound = @($PSBoundParameters.Keys | Sort-Object) }
'@
        $script:module = Get-Module iSOCBlueprint
        $script:savedRoot = & $script:module { $script:iSOCBlueprintEngineRoot }
        & $script:module { param($r) $script:iSOCBlueprintEngineRoot = $r } $script:fakeEngine
    }

    AfterAll {
        & $script:module { param($r) $script:iSOCBlueprintEngineRoot = $r } $script:savedRoot
    }

    It 'leaves out parameters whose value is null, so the script default applies' {
        $r = & $script:module { Invoke-iSOCBlueprintEngine -Script 'Echo.ps1' -Parameters @{ Name = 'x'; Other = $null } }
        $r.Bound | Should -Be @('Name')
    }

    It 'passes common parameters the script accepts and drops the ones it does not' {
        $r = & $script:module { Invoke-iSOCBlueprintEngine -Script 'Echo.ps1' -Parameters @{ Name = 'x' } -BoundParameters @{ WhatIf = [switch]$true; Verbose = [switch]$true } }
        $r.Bound | Should -Contain 'WhatIf'
        $r.Bound | Should -Contain 'Verbose'
        $r.WhatIf | Should -BeTrue
        $p = & $script:module { Invoke-iSOCBlueprintEngine -Script 'Plain.ps1' -Parameters @{ Name = 'x' } -BoundParameters @{ WhatIf = [switch]$true } }
        $p.Bound | Should -Be @('Name')
    }

    It 'runs the script without the module''s strict mode' {
        $r = & $script:module { Invoke-iSOCBlueprintEngine -Script 'Echo.ps1' -Parameters @{ Name = 'x' } }
        $r.Strict | Should -BeTrue
    }

    It 'fails clearly when the script is missing' {
        { & $script:module { Invoke-iSOCBlueprintEngine -Script 'Nope.ps1' -Parameters @{} } } | Should -Throw '*engine script not found*'
    }
}

Describe 'Public commands map their parameters onto the engine' {
    BeforeAll {
        Mock -ModuleName iSOCBlueprint Invoke-iSOCBlueprintEngine { }
        Push-Location $TestDrive
        $script:cwd = (Get-Location).ProviderPath
    }

    AfterAll { Pop-Location }

    It 'Export-iSOCBlueprintInventory defaults the output to ./SecurityDocs and passes only what was given' {
        $r = Export-iSOCBlueprintInventory -ResourceGroup rg -WorkspaceName ws -IncludePreview
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintEngine -Times 1 -Exactly -ParameterFilter {
            $Script -eq 'Export-SentinelInventory.ps1' -and
            $Parameters.OutputRoot -eq (Join-Path $script:cwd 'SecurityDocs') -and
            $Parameters.ResourceGroup -eq 'rg' -and $Parameters.WorkspaceName -eq 'ws' -and
            $Parameters.TargetMaturityLevel -eq 3 -and $Parameters.IncludePreview -eq $true -and
            -not $Parameters.ContainsKey('SubscriptionId') -and -not $Parameters.ContainsKey('PlaybookResourceGroup')
        }
        # One folder a day, so a run does not overwrite the last.
        $day = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintEngine -Times 1 -Exactly -ParameterFilter { $Parameters.RunFolder -eq $day }
        $r.Path | Should -Be (Join-Path $script:cwd "SecurityDocs/ws/$day")
        $r.RawPath | Should -Be (Join-Path $script:cwd "SecurityDocs/ws/$day/_raw")
    }

    It 'Export-iSOCBlueprintInventory writes to the workspace folder itself with -NoDateFolder' {
        $r = Export-iSOCBlueprintInventory -ResourceGroup rg -WorkspaceName ws -NoDateFolder
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintEngine -Times 1 -Exactly -ParameterFilter { -not $Parameters.ContainsKey('RunFolder') }
        $r.Path | Should -Be (Join-Path $script:cwd 'SecurityDocs/ws')
    }

    It 'ConvertTo-iSOCBlueprint reads and writes the workspace folder by default' {
        $r = ConvertTo-iSOCBlueprint -WorkspaceName ws -Format Json
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintEngine -Times 1 -Exactly -ParameterFilter {
            $Script -eq 'Convert-SentinelInventoryToMarkdown.ps1' -and
            $Parameters.InputRoot -eq (Join-Path $script:cwd 'SecurityDocs/ws') -and
            $Parameters.OutputRoot -eq $Parameters.InputRoot -and
            "$($Parameters.OutputFormat)" -eq 'Json' -and -not $Parameters.ContainsKey('ResourcesRoot')
        }
        $r.SectionsPath | Should -Be (Join-Path $script:cwd 'SecurityDocs/ws/sections')
    }

    It 'ConvertTo-iSOCBlueprint takes the inventory from the pipeline' {
        [pscustomobject]@{ WorkspaceName = 'piped'; Path = (Join-Path $script:cwd 'elsewhere/piped') } | ConvertTo-iSOCBlueprint -Format Markdown | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintEngine -Times 1 -Exactly -ParameterFilter {
            $Parameters.WorkspaceName -eq 'piped' -and $Parameters.InputRoot -eq (Join-Path $script:cwd 'elsewhere/piped')
        }
    }

    It 'ConvertTo-iSOCBlueprintChartImage renames AssetsDirectory and leaves unset options to the script' {
        ConvertTo-iSOCBlueprintChartImage -AssetsDirectory img | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintEngine -Times 1 -Exactly -ParameterFilter {
            $Script -eq 'Convert-MermaidToImage.ps1' -and $Parameters.Root -eq (Join-Path $script:cwd 'SecurityDocs') -and
            $Parameters.AssetsDir -eq 'img' -and $Parameters.Format -eq 'png' -and -not $Parameters.ContainsKey('Width')
        }
    }

    It 'Export-iSOCBlueprintWord writes beside the workspace folder and passes an empty strip pattern through' {
        Export-iSOCBlueprintWord -Path SecurityDocs/ws -StripLinePattern '' | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintEngine -Times 1 -Exactly -ParameterFilter {
            $Script -eq 'Report/Convert-MarkdownToWord.ps1' -and
            $Parameters.Source -eq (Join-Path $script:cwd 'SecurityDocs/ws') -and
            $Parameters.OutputPath -eq (Join-Path $script:cwd 'SecurityDocs/ws.docx') -and
            $Parameters.ContainsKey('StripLinePattern') -and $Parameters.StripLinePattern -eq '' -and
            -not $Parameters.ContainsKey('Title') -and -not $Parameters.ContainsKey('Toc')
        }
    }

    It 'New-iSOCBlueprintSite returns the bundle folder and passes -WhatIf on' {
        $r = New-iSOCBlueprintSite -Path SecurityDocs/ws -SkipWhatsNew -WhatIf
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintEngine -Times 1 -Exactly -ParameterFilter {
            $Script -eq 'SharePoint/Build-SentinelDocsSite.ps1' -and $Parameters.Source -eq (Join-Path $script:cwd 'SecurityDocs/ws') -and
            $Parameters.SkipWhatsNew -eq $true -and -not $Parameters.ContainsKey('OutputRoot') -and $BoundParameters.WhatIf
        }
        $r.Path | Should -Be (Join-Path $script:cwd 'SecurityDocs/ws/sharepoint')
        $r.WorkspaceName | Should -Be 'ws'
    }

    It 'Publish-iSOCBlueprintSite sends a token, or an interactive sign-in, never both' {
        Publish-iSOCBlueprintSite -SiteUrl https://x/sites/y -Path b -AccessToken t | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintEngine -Times 1 -Exactly -ParameterFilter {
            $Script -eq 'SharePoint/Publish-SentinelDocsSite.ps1' -and $Parameters.AccessToken -eq 't' -and
            -not $Parameters.ContainsKey('Interactive') -and $Parameters.Bundle -eq (Join-Path $script:cwd 'b')
        }
        Publish-iSOCBlueprintSite -SiteUrl https://x/sites/y -Path b -Interactive -ClientId c -Tenant t.onmicrosoft.com | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintEngine -Times 1 -Exactly -ParameterFilter {
            $Parameters.Interactive -eq $true -and $Parameters.ClientId -eq 'c' -and -not $Parameters.ContainsKey('AccessToken')
        }
    }

    It 'Initialize-iSOCBlueprintSite passes the required values and only the optional ones given' {
        Initialize-iSOCBlueprintSite -SiteUrl https://x/sites/y -Owner o@x -PublisherAppId p -ClientId c -Tenant t | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintEngine -Times 1 -Exactly -ParameterFilter {
            $Script -eq 'SharePoint/Initialize-SentinelDocsSite.ps1' -and $Parameters.Owner -eq 'o@x' -and
            $Parameters.PublisherAppId -eq 'p' -and -not $Parameters.ContainsKey('Title') -and -not $Parameters.ContainsKey('AppPackagePath')
        }
    }

    It 'Update-iSOCBlueprintConnectorCatalogue changes nothing under -WhatIf' {
        Update-iSOCBlueprintConnectorCatalogue -WhatIf | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintEngine -Times 0 -Exactly -ParameterFilter { $Script -eq 'Update-ConnectorCatalogue.ps1' }
    }
}

Describe 'New-iSOCBlueprint' {
    BeforeAll {
        Push-Location $TestDrive
        $script:cwd = (Get-Location).ProviderPath
        $script:day = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    }

    AfterAll { Pop-Location }

    BeforeEach {
        Mock -ModuleName iSOCBlueprint Test-iSOCBlueprintPrerequisite { }
        Mock -ModuleName iSOCBlueprint Export-iSOCBlueprintInventory { }
        Mock -ModuleName iSOCBlueprint ConvertTo-iSOCBlueprint { }
        Mock -ModuleName iSOCBlueprint ConvertTo-iSOCBlueprintChartImage { }
        Mock -ModuleName iSOCBlueprint Export-iSOCBlueprintWord { }
        Mock -ModuleName iSOCBlueprint New-iSOCBlueprintSite { [pscustomobject]@{ Path = 'bundle' } }
        Mock -ModuleName iSOCBlueprint Publish-iSOCBlueprintSite { 'https://contoso.sharepoint.com/sites/isoc' }
    }

    It 'collects and renders only the section model for Json' {
        $r = New-iSOCBlueprint -ResourceGroup rg -WorkspaceName ws -Format Json
        Should -Invoke -ModuleName iSOCBlueprint Export-iSOCBlueprintInventory -Times 1 -Exactly
        Should -Invoke -ModuleName iSOCBlueprint ConvertTo-iSOCBlueprint -Times 1 -Exactly -ParameterFilter { "$Format" -eq 'Json' }
        Should -Invoke -ModuleName iSOCBlueprint Export-iSOCBlueprintWord -Times 0 -Exactly
        Should -Invoke -ModuleName iSOCBlueprint New-iSOCBlueprintSite -Times 0 -Exactly
        $r.SectionsPath | Should -Be (Join-Path $script:cwd "SecurityDocs/ws/$($script:day)/sections")
        $r.MarkdownPath | Should -BeNullOrEmpty
    }

    It 'keeps the flat workspace folder with -NoDateFolder' {
        $r = New-iSOCBlueprint -ResourceGroup rg -WorkspaceName ws -Format Json -NoDateFolder
        Should -Invoke -ModuleName iSOCBlueprint Export-iSOCBlueprintInventory -Times 1 -Exactly -ParameterFilter { $NoDateFolder }
        $r.SectionsPath | Should -Be (Join-Path $script:cwd 'SecurityDocs/ws/sections')
    }

    It 'renders the newest day with -SkipCollection' {
        foreach ($d in '2026-10-01', '2026-10-03', '2026-10-02') { New-Item -ItemType Directory -Path (Join-Path $script:cwd "SecurityDocs/wsd/$d/_raw") -Force | Out-Null }
        $r = New-iSOCBlueprint -WorkspaceName wsd -SkipCollection -Format Json
        $r.Path | Should -Be (Join-Path $script:cwd 'SecurityDocs/wsd/2026-10-03')
        Should -Invoke -ModuleName iSOCBlueprint ConvertTo-iSOCBlueprint -Times 1 -Exactly -ParameterFilter { $Path -eq (Join-Path $script:cwd 'SecurityDocs/wsd/2026-10-03') }
    }

    It 'renders Markdown for Word and warns that charts need -ChartImages' {
        New-iSOCBlueprint -ResourceGroup rg -WorkspaceName ws -Format Word -WarningVariable warned -WarningAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint ConvertTo-iSOCBlueprint -Times 1 -Exactly -ParameterFilter { "$Format" -eq 'Markdown' }
        Should -Invoke -ModuleName iSOCBlueprint Export-iSOCBlueprintWord -Times 1 -Exactly -ParameterFilter { $OutputPath -eq (Join-Path $script:cwd "SecurityDocs/ws/$($script:day)/ws.docx") }
        Should -Invoke -ModuleName iSOCBlueprint ConvertTo-iSOCBlueprintChartImage -Times 0 -Exactly
        "$warned" | Should -Match 'ChartImages'
    }

    It 'draws the charts before the Word report with -ChartImages' {
        New-iSOCBlueprint -ResourceGroup rg -WorkspaceName ws -Format Word -ChartImages | Out-Null
        # Chart images look one level down: the days under the workspace's folder.
        Should -Invoke -ModuleName iSOCBlueprint ConvertTo-iSOCBlueprintChartImage -Times 1 -Exactly -ParameterFilter { $Path -eq (Join-Path $script:cwd 'SecurityDocs/ws') }
    }

    It 'builds the SharePoint bundle without publishing when no site is given' {
        $r = New-iSOCBlueprint -ResourceGroup rg -WorkspaceName ws -Format SharePoint
        Should -Invoke -ModuleName iSOCBlueprint ConvertTo-iSOCBlueprint -Times 1 -Exactly -ParameterFilter { "$Format" -eq 'Json' }
        Should -Invoke -ModuleName iSOCBlueprint New-iSOCBlueprintSite -Times 1 -Exactly -ParameterFilter { $HistoryDays -eq 90 }
        Should -Invoke -ModuleName iSOCBlueprint Publish-iSOCBlueprintSite -Times 0 -Exactly
        $r.SiteBundle | Should -Be 'bundle'
        $r.SiteUrl | Should -BeNullOrEmpty
    }

    It 'publishes with the token given' {
        $r = New-iSOCBlueprint -ResourceGroup rg -WorkspaceName ws -Format SharePoint -SiteUrl https://contoso.sharepoint.com/sites/isoc -AccessToken t
        Should -Invoke -ModuleName iSOCBlueprint Publish-iSOCBlueprintSite -Times 1 -Exactly -ParameterFilter { $AccessToken -eq 't' -and $Path -eq 'bundle' }
        $r.SiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/isoc'
    }

    It 'renders both formats once for everything' {
        New-iSOCBlueprint -ResourceGroup rg -WorkspaceName ws -Format Json, Markdown, Word, SharePoint -ChartImages | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint ConvertTo-iSOCBlueprint -Times 1 -Exactly -ParameterFilter { "$Format" -eq 'Markdown Json' }
    }

    It 'refuses <Case>' -ForEach @(
        @{ Case = 'a site without SharePoint in the formats'; Splat = @{ Format = 'Json'; SiteUrl = 'https://x' }; Message = '*add SharePoint*' }
        @{ Case = 'a site without a way to sign in'; Splat = @{ Format = 'SharePoint'; SiteUrl = 'https://x' }; Message = '*AccessToken*' }
        @{ Case = 'chart images without Markdown'; Splat = @{ Format = 'Json'; ChartImages = $true }; Message = '*ChartImages*' }
    ) {
        { New-iSOCBlueprint -ResourceGroup rg -WorkspaceName ws @Splat } | Should -Throw $Message
        Should -Invoke -ModuleName iSOCBlueprint Export-iSOCBlueprintInventory -Times 0 -Exactly
    }

    It 'stops before doing anything when a required tool is missing' {
        Mock -ModuleName iSOCBlueprint Test-iSOCBlueprintPrerequisite {
            [pscustomobject]@{ Name = 'pandoc'; Step = @('Word'); Required = $true; Found = $false; Detail = 'install pandoc' }
        }
        { New-iSOCBlueprint -ResourceGroup rg -WorkspaceName ws -Format Word } | Should -Throw '*pandoc*'
        Should -Invoke -ModuleName iSOCBlueprint Export-iSOCBlueprintInventory -Times 0 -Exactly
    }

    It 'asks only for the steps the run uses' {
        New-Item -ItemType Directory -Path (Join-Path $script:cwd 'SecurityDocs/ws/_raw') -Force | Out-Null
        New-iSOCBlueprint -WorkspaceName ws -SkipCollection -Format Json | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Test-iSOCBlueprintPrerequisite -ParameterFilter { "$Step" -eq 'Render' }
    }

    It 're-uses an inventory on disk with -SkipCollection' {
        New-Item -ItemType Directory -Path (Join-Path $script:cwd 'SecurityDocs/ws/_raw') -Force | Out-Null
        New-iSOCBlueprint -WorkspaceName ws -SkipCollection -Format Markdown | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Export-iSOCBlueprintInventory -Times 0 -Exactly
        Should -Invoke -ModuleName iSOCBlueprint ConvertTo-iSOCBlueprint -Times 1 -Exactly
    }

    It 'fails clearly with -SkipCollection and no inventory' {
        { New-iSOCBlueprint -WorkspaceName missing -SkipCollection } | Should -Throw '*needs an inventory*'
    }

    It 'does nothing under -WhatIf' {
        New-iSOCBlueprint -ResourceGroup rg -WorkspaceName ws -Format Json -WhatIf | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Export-iSOCBlueprintInventory -Times 0 -Exactly
        Should -Invoke -ModuleName iSOCBlueprint ConvertTo-iSOCBlueprint -Times 0 -Exactly
    }
}
