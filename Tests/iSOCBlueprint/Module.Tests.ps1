#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the iSOCBlueprint module's manifest, help and public
    commands.

.DESCRIPTION
    The public commands are thin wrappers over the worker functions, so most
    of what can go wrong is in how they map their parameters. These tests
    stand in for the workers (Invoke-iSOCBlueprintCollect, Render and the
    rest are mocked) and check each command passes the right function the
    right parameters, that New-iSOCBlueprint runs the steps each format
    needs and refuses contradictory requests, and that the commands that
    need a module check the prerequisite list first. They also hold the
    manifest, the help and the file headers to the repository's
    conventions.

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
    Version:      0.4.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $moduleRoot = Join-Path $repoRoot 'Modules/iSOCBlueprint'
    $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot 'iSOCBlueprint.psd1')
    $commands = @($manifest.FunctionsToExport | ForEach-Object { @{ Name = $_ } })
    $ownFiles = @(
        Get-Item -LiteralPath (Join-Path $moduleRoot 'iSOCBlueprint.psm1')
        Get-ChildItem -LiteralPath (Join-Path $moduleRoot 'Public'), (Join-Path $moduleRoot 'Private'), (Join-Path $moduleRoot 'Engine/Private/Vendor') -Filter '*.ps1' -File -Recurse
    ) | ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
    # Every script the module ships, engine included: one that does not
    # parse fails only when a run reaches it.
    $allScripts = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -Filter '*.ps1' -File) |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:moduleRoot = Join-Path $script:repoRoot 'Modules/iSOCBlueprint'
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
        $text | Should -Match '^#Requires -Version 7\.6\r?\n'
        $text | Should -Match ("(?m)^\s*File:\s+" + [regex]::Escape($Path) + '\s*$')
    }
}

Describe 'Script <Path>' -ForEach $allScripts {
    It 'parses' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:repoRoot $Path), [ref]$null, [ref]$errors)
        @($errors | ForEach-Object { "$($_.Message) (line $($_.Extent.StartLineNumber))" }) | Should -BeNullOrEmpty
    }
}

Describe 'Prerequisites' {
    BeforeAll {
        $script:requirements = & (Get-Module iSOCBlueprint) { Get-iSOCBlueprintRequirement }
    }

    It 'lists the Az modules the collector needs, for Collect' {
        $listed = @($script:requirements | Where-Object { $_.Kind -eq 'Module' -and $_.Required -and $_.Step -contains 'Collect' } | ForEach-Object Name | Sort-Object)
        $listed | Should -Be @('Az.Accounts', 'Az.LogicApp', 'Az.Monitor', 'Az.OperationalInsights', 'Az.Resources', 'Az.SecurityInsights')
    }

    It 'lists the YAML module the renderer needs, for Render' {
        $listed = @($script:requirements | Where-Object { $_.Kind -eq 'Module' -and $_.Step -contains 'Render' } | ForEach-Object Name | Sort-Object)
        $listed | Should -Be @('powershell-yaml')
    }

    It 'pins PowerShell 7.6 and PnP.PowerShell 3.4.1, for Publish' {
        ($script:requirements | Where-Object Name -eq 'PnP.PowerShell').MinimumVersion | Should -Be '3.4.1'
        $ps = $script:requirements | Where-Object { $_.Kind -eq 'PowerShell' -and $_.Step -contains 'Publish' } | Sort-Object { [version]$_.MinimumVersion } | Select-Object -Last 1
        $ps.MinimumVersion | Should -Be '7.6'
    }

    It '<Command> checks the <Needs> prerequisites first' -ForEach @(
        @{ Command = 'Export-iSOCBlueprintInventory'; Needs = 'Collect'; Splat = @{ ResourceGroup = 'rg'; WorkspaceName = 'ws' }; Worker = 'Invoke-iSOCBlueprintCollect' }
        @{ Command = 'ConvertTo-iSOCBlueprint'; Needs = 'Render'; Splat = @{ WorkspaceName = 'ws' }; Worker = 'Invoke-iSOCBlueprintRender' }
        @{ Command = 'Publish-iSOCBlueprintSite'; Needs = 'Publish'; Splat = @{ SiteUrl = 'https://x/sites/y'; Path = 'b'; AccessToken = 't' }; Worker = 'Invoke-iSOCBlueprintSitePublish' }
    ) {
        Mock -ModuleName iSOCBlueprint Test-iSOCBlueprintPrerequisite {
            [pscustomobject]@{ Name = 'Missing.Module'; Step = @($Step); Required = $true; Found = $false; Detail = 'Install-Module Missing.Module' }
        }
        Mock -ModuleName iSOCBlueprint Invoke-iSOCBlueprintCollect { }
        Mock -ModuleName iSOCBlueprint Invoke-iSOCBlueprintRender { }
        Mock -ModuleName iSOCBlueprint Invoke-iSOCBlueprintSitePublish { }
        $splat = $Splat
        { & $Command @splat } | Should -Throw "This command needs:*Missing.Module ($Needs)*"
        Should -Invoke -ModuleName iSOCBlueprint $Worker -Times 0 -Exactly
        Should -Invoke -ModuleName iSOCBlueprint Test-iSOCBlueprintPrerequisite -Times 1 -Exactly -ParameterFilter { $Step -contains $Needs }
    }

    It 'stops a command that needs a missing module with the list of what is missing' {
        Mock -ModuleName iSOCBlueprint Test-iSOCBlueprintPrerequisite {
            [pscustomobject]@{ Name = 'PnP.PowerShell'; Step = @('Publish'); Required = $true; Found = $false; Detail = 'Install-Module PnP.PowerShell' }
        }
        { & (Get-Module iSOCBlueprint) { Assert-iSOCBlueprintPrerequisite -Step Publish } } | Should -Throw '*This command needs:*PnP.PowerShell (Publish)*'
        { & (Get-Module iSOCBlueprint) { Assert-iSOCBlueprintPrerequisite -Step Publish -For run } } | Should -Throw 'This run needs:*'
    }

    It 'lets a command through when everything it needs is found' {
        Mock -ModuleName iSOCBlueprint Test-iSOCBlueprintPrerequisite {
            [pscustomobject]@{ Name = 'x'; Step = @('Publish'); Required = $true; Found = $true; Detail = '' }
            [pscustomobject]@{ Name = 'y'; Step = @('Publish'); Required = $false; Found = $false; Detail = '' }
        }
        { & (Get-Module iSOCBlueprint) { Assert-iSOCBlueprintPrerequisite -Step Publish } } | Should -Not -Throw
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
        $block = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Private/Collector/Captures/Sentinel/Invoke-AlertRulesCapture.ps1') -Raw
        $block | Should -Match '/alertRules" -ApiVersion \$apiVersions\.SentinelPreview'
        $block | Should -Match '(?s)catch \{.*/alertRules" -ApiVersion \$apiVersions\.Sentinel\s'
    }
}

Describe 'Alert volume capture' {
    It 'counts each alert once, not each record a status change writes' {
        $block = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Private/Collector/Captures/Detection/Invoke-AnalyticsRuleVolumesCapture.ps1') -Raw
        $block | Should -Match 'summarize arg_min\(TimeGenerated, AlertName, ProductName, AlertSeverity, ProviderName\) by SystemAlertId'
        $block | Should -Match 'by AlertName, ProductName, AlertSeverity'
    }
}

Describe 'Incident closure capture' {
    It 'counts closed incidents by who closed them, exporting the category and never the name' {
        $block = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Private/Collector/Captures/Incidents/Invoke-IncidentsSummaryCapture.ps1') -Raw
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
        $init = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Private/SiteSetup/Invoke-iSOCBlueprintSiteInitialize.ps1') -Raw
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
        # Names Git quotes (a non-ASCII character): a fixture still goes, and
        # output under SecurityDocs/ is still refused.
        $fixtureQuoted = & $commit ('Tests/iSOCBlueprint/Fixtures/sample/_raw/caf{0}.json' -f [char]0xE9)
        $leakQuoted = & $commit ('SecurityDocs/r{0}sum{0}/notes.md' -f [char]0xE9) -Force
        git -C $repo reset -q --hard $fixtureQuoted
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
        & $push 'https://github.com/owner/repo.git' $fixtureQuoted | Should -Be 0
        & $push 'https://github.com/owner/repo.git' $leakQuoted | Should -Be 1
        & $push 'https://github.com/owner/repo.git' $leak | Should -Be 1
        & $push 'git@github.com:owner/repo.git' $leak | Should -Be 1
        & $push 'https://dev.azure.com/org/project/_git/repo' $leak | Should -Be 0
    }
}

Describe 'Public commands map their parameters onto the workers' {
    BeforeAll {
        Mock -ModuleName iSOCBlueprint Assert-iSOCBlueprintPrerequisite { }
        Mock -ModuleName iSOCBlueprint Invoke-iSOCBlueprintCollect { }
        Mock -ModuleName iSOCBlueprint Invoke-iSOCBlueprintRender { }
        Mock -ModuleName iSOCBlueprint Invoke-iSOCBlueprintWordConversion { }
        Mock -ModuleName iSOCBlueprint Invoke-iSOCBlueprintSiteBuild { }
        Mock -ModuleName iSOCBlueprint Invoke-iSOCBlueprintSitePublish { }
        Mock -ModuleName iSOCBlueprint Invoke-iSOCBlueprintChartImage { }
        Mock -ModuleName iSOCBlueprint Invoke-iSOCBlueprintSiteInitialize { }
        Mock -ModuleName iSOCBlueprint Invoke-iSOCBlueprintConnectorCatalogueUpdate { }
        Push-Location $TestDrive
        $script:cwd = (Get-Location).ProviderPath
    }

    AfterAll { Pop-Location }

    It 'Export-iSOCBlueprintInventory defaults the output to ./SecurityDocs and passes only what was given' {
        $r = Export-iSOCBlueprintInventory -ResourceGroup rg -WorkspaceName ws -IncludePreview
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintCollect -Times 1 -Exactly -ParameterFilter {
            $OutputRoot -eq (Join-Path $script:cwd 'SecurityDocs') -and
            $ResourceGroup -eq 'rg' -and $WorkspaceName -eq 'ws' -and
            $TargetMaturityLevel -eq 3 -and [bool]$IncludePreview -and
            -not $PesterBoundParameters.ContainsKey('SubscriptionId') -and -not $PesterBoundParameters.ContainsKey('PlaybookResourceGroup') -and
            -not $PesterBoundParameters.ContainsKey('EngineRoot')
        }
        # One folder a day, so a run does not overwrite the last.
        $day = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintCollect -Times 1 -Exactly -ParameterFilter { $RunFolder -eq $day }
        $r.Path | Should -Be (Join-Path $script:cwd "SecurityDocs/ws/$day")
        $r.RawPath | Should -Be (Join-Path $script:cwd "SecurityDocs/ws/$day/_raw")
    }

    It 'Export-iSOCBlueprintInventory writes to the workspace folder itself with -NoDateFolder' {
        $r = Export-iSOCBlueprintInventory -ResourceGroup rg -WorkspaceName ws -NoDateFolder
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintCollect -Times 1 -Exactly -ParameterFilter { -not $PesterBoundParameters.ContainsKey('RunFolder') }
        $r.Path | Should -Be (Join-Path $script:cwd 'SecurityDocs/ws')
    }

    It 'ConvertTo-iSOCBlueprint reads and writes the workspace folder by default' {
        $r = ConvertTo-iSOCBlueprint -WorkspaceName ws -Format Json
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintRender -Times 1 -Exactly -ParameterFilter {
            $InputRoot -eq (Join-Path $script:cwd 'SecurityDocs/ws') -and
            $OutputRoot -eq $InputRoot -and
            "$OutputFormat" -eq 'Json' -and -not $PesterBoundParameters.ContainsKey('ResourcesRoot')
        }
        $r.SectionsPath | Should -Be (Join-Path $script:cwd 'SecurityDocs/ws/sections')
    }

    It 'ConvertTo-iSOCBlueprint takes the inventory from the pipeline' {
        [pscustomobject]@{ WorkspaceName = 'piped'; Path = (Join-Path $script:cwd 'elsewhere/piped') } | ConvertTo-iSOCBlueprint -Format Markdown | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintRender -Times 1 -Exactly -ParameterFilter {
            $WorkspaceName -eq 'piped' -and $InputRoot -eq (Join-Path $script:cwd 'elsewhere/piped')
        }
    }

    It 'ConvertTo-iSOCBlueprintChartImage renames AssetsDirectory and leaves unset options to the script' {
        ConvertTo-iSOCBlueprintChartImage -AssetsDirectory img | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintChartImage -Times 1 -Exactly -ParameterFilter {
            $Root -eq (Join-Path $script:cwd 'SecurityDocs') -and
            $AssetsDir -eq 'img' -and $Format -eq 'png' -and -not $PesterBoundParameters.ContainsKey('Width')
        }
    }

    It 'Export-iSOCBlueprintWord writes beside the workspace folder and passes an empty strip pattern through' {
        Export-iSOCBlueprintWord -Path SecurityDocs/ws -StripLinePattern '' | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintWordConversion -Times 1 -Exactly -ParameterFilter {
            $Source -eq (Join-Path $script:cwd 'SecurityDocs/ws') -and
            $OutputPath -eq (Join-Path $script:cwd 'SecurityDocs/ws.docx') -and
            $PesterBoundParameters.ContainsKey('StripLinePattern') -and $StripLinePattern -eq '' -and
            -not $PesterBoundParameters.ContainsKey('Title') -and -not $PesterBoundParameters.ContainsKey('Toc')
        }
    }

    It 'New-iSOCBlueprintSite returns the bundle folder' {
        $r = New-iSOCBlueprintSite -Path SecurityDocs/ws -SkipWhatsNew
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintSiteBuild -Times 1 -Exactly -ParameterFilter {
            $Source -eq (Join-Path $script:cwd 'SecurityDocs/ws') -and
            $SkipWhatsNew -and -not $PesterBoundParameters.ContainsKey('OutputRoot')
        }
        $r.Path | Should -Be (Join-Path $script:cwd 'SecurityDocs/ws/sharepoint')
        $r.WorkspaceName | Should -Be 'ws'
    }

    It 'Publish-iSOCBlueprintSite sends a token, or an interactive sign-in, never both' {
        Publish-iSOCBlueprintSite -SiteUrl https://x/sites/y -Path b -AccessToken t | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintSitePublish -Times 1 -Exactly -ParameterFilter {
            $AccessToken -eq 't' -and
            -not $PesterBoundParameters.ContainsKey('Interactive') -and $Bundle -eq (Join-Path $script:cwd 'b')
        }
        Publish-iSOCBlueprintSite -SiteUrl https://x/sites/y -Path b -Interactive -ClientId c -Tenant t.onmicrosoft.com | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintSitePublish -Times 1 -Exactly -ParameterFilter {
            $Interactive -and $ClientId -eq 'c' -and -not $PesterBoundParameters.ContainsKey('AccessToken')
        }
    }

    It 'Initialize-iSOCBlueprintSite passes the required values and only the optional ones given' {
        Initialize-iSOCBlueprintSite -SiteUrl https://x/sites/y -Owner o@x -PublisherAppId p -ClientId c -Tenant t | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintSiteInitialize -Times 1 -Exactly -ParameterFilter {
            $Owner -eq 'o@x' -and $PublisherAppId -eq 'p' -and
            -not $PesterBoundParameters.ContainsKey('Title') -and -not $PesterBoundParameters.ContainsKey('AppPackagePath')
        }
    }

    It 'Update-iSOCBlueprintConnectorCatalogue changes nothing under -WhatIf' {
        Update-iSOCBlueprintConnectorCatalogue -WhatIf | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintConnectorCatalogueUpdate -Times 0 -Exactly
    }

    It 'Update-iSOCBlueprintConnectorCatalogue resolves a local source and writes to the shipped catalogue by default' {
        Update-iSOCBlueprintConnectorCatalogue -Source toolkit/connectors.json | Out-Null
        Should -Invoke -ModuleName iSOCBlueprint Invoke-iSOCBlueprintConnectorCatalogueUpdate -Times 1 -Exactly -ParameterFilter {
            $Source -eq (Join-Path $script:cwd 'toolkit/connectors.json') -and
            $OutputPath -eq (Join-Path $script:moduleRoot 'Engine/Private/Resources/connector-catalogue.json')
        }
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
