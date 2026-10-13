#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests that the iSOCBlueprint module produces the same Blueprint
    as Tools/Blueprint.

.DESCRIPTION
    The module's engine is a copy of Tools/Blueprint with a few listed
    edits, and its commands are wrappers that map parameters onto the
    engine. This suite runs the same fixture inventory through both and
    compares every output:

      - the Markdown report and the section model (every page and every
        sections/*.json), rendered by the old renderer and by
        ConvertTo-iSOCBlueprint
      - the SharePoint bundle (site.json, model.json, findings.json,
        index.html and every pages/*.json), built from one rendering by the
        old builder and by New-iSOCBlueprintSite, so the builder is
        compared on its own
      - the gap-analysis findings and outcomes, and the maturity assessment

    The only differences allowed are the ones the edits make on purpose:
    the four links E6 points at GitHub (the old output is rewritten the
    same way before comparing) and the build timestamp in the bundle. Any
    other difference fails, naming the file and the first line that
    differs.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Parity.Tests.ps1

    Runs the whole suite.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Parity.Tests.ps1 -Output Detailed

    Lists every file compared.

.NOTES
    File:         Tests/iSOCBlueprint/Parity.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml (the renderer)

    Retired with Tools/Blueprint: once the old folder is removed there is
    nothing left to compare against.
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $fixture = Join-Path $repoRoot 'Tests/iSOCBlueprint/Fixtures/sample/_raw'
    $work = Join-Path ([System.IO.Path]::GetTempPath()) "isoc-parity-$([guid]::NewGuid().ToString('N'))"
    $old = Join-Path $work 'old/SecurityDocs/law-parity'
    $new = Join-Path $work 'new/SecurityDocs/law-parity'
    foreach ($ws in $old, $new) {
        New-Item -ItemType Directory -Path $ws -Force | Out-Null
        Copy-Item -LiteralPath $fixture -Destination $ws -Recurse
    }

    & (Join-Path $repoRoot 'Tools/Blueprint/Convert-SentinelInventoryToMarkdown.ps1') -WorkspaceName law-parity -InputRoot $old `
        -ResourcesRoot (Join-Path $repoRoot 'Tools/Blueprint/Private/Resources') -InformationAction SilentlyContinue *> $null

    Import-Module (Join-Path $repoRoot 'Modules/iSOCBlueprint/iSOCBlueprint.psd1') -Force
    ConvertTo-iSOCBlueprint -WorkspaceName law-parity -Path $new *> $null

    # The bundle: build both from one rendering (the module's), so only the
    # builders differ.
    $siteOld = Join-Path $work 'site-old/law-parity'
    $siteNew = Join-Path $work 'site-new/law-parity'
    foreach ($ws in $siteOld, $siteNew) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $ws) -Force | Out-Null
        Copy-Item -LiteralPath $new -Destination $ws -Recurse
    }
    & (Join-Path $repoRoot 'Tools/Blueprint/SharePoint/Build-SentinelDocsSite.ps1') -Source $siteOld -SkipWhatsNew *> $null
    New-iSOCBlueprintSite -Path $siteNew -SkipWhatsNew *> $null

    $relative = {
        param([string] $Root, [string] $Exclude)
        @(Get-ChildItem -LiteralPath $Root -Recurse -File |
                ForEach-Object { [System.IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/') } |
                Where-Object { -not $Exclude -or $_ -notlike $Exclude } | Sort-Object)
    }
    $reportOld = & $relative $old '_raw/*'
    $reportNew = & $relative $new '_raw/*'
    $bundleOld = & $relative (Join-Path $siteOld 'sharepoint') $null
    $bundleNew = & $relative (Join-Path $siteNew 'sharepoint') $null

    $reportFiles = @($reportNew | ForEach-Object { @{ File = $_ } })
    $bundleFiles = @($bundleNew | ForEach-Object { @{ File = $_ } })

    # Hand the paths to the run phase.
    $global:iSOCParity = @{
        Work = $work; Old = $old; New = $new; SiteOld = $siteOld; SiteNew = $siteNew
        ReportOld = $reportOld; ReportNew = $reportNew; BundleOld = $bundleOld; BundleNew = $bundleNew
    }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:p = $global:iSOCParity
    # Discovery imported the module, but another suite may have removed it
    # since; the assessment comparison calls it again.
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/iSOCBlueprint.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '_helpers/Migration.psm1') -Force
    $edits = Get-EngineEdit -RepoRoot $script:repoRoot
    $script:linkChanges = @(($edits.Edits | Where-Object Id -eq 'E6').Changes)

    function ConvertTo-ExpectedText {
        # The old output, with the E6 links rewritten as the module writes
        # them: as Markdown links, and as the link runs the section model
        # stores, where a repository path was { kind: repo, path } and a
        # GitHub URL is { kind: external }.
        param([string] $Text)
        foreach ($c in $script:linkChanges) {
            $Text = $Text.Replace($c.Find, $c.Replace)
            $from = [regex]::Escape($c.Find.Substring(2, $c.Find.Length - 3))
            $to = $c.Replace.Substring(2, $c.Replace.Length - 3)
            $run = '"href": "' + $from + '",(\s*)"target": \{(\s*)"kind": "repo",\s*"path": "' + $from + '"(\s*)\}'
            $Text = [regex]::Replace($Text, $run, { param($m) '"href": "' + $to + '",' + $m.Groups[1].Value + '"target": {' + $m.Groups[2].Value + '"kind": "external"' + $m.Groups[3].Value + '}' })
        }
        $Text
    }

    function Assert-SameText {
        param([string] $Expected, [string] $Actual, [string] $What)
        if ([string]::Equals($Expected, $Actual, [StringComparison]::Ordinal)) { return }
        $e = $Expected -split "`n"
        $a = $Actual -split "`n"
        $i = 0
        while ($i -lt [Math]::Min($e.Count, $a.Count) -and [string]::Equals($e[$i], $a[$i], [StringComparison]::Ordinal)) { $i++ }
        $want = if ($i -lt $e.Count) { $e[$i] } else { '<end of file>' }
        $got = if ($i -lt $a.Count) { $a[$i] } else { '<end of file>' }
        $got | Should -BeExactly $want -Because "line $($i + 1) of $What must match the old output"
    }

    function Remove-BuildStamp {
        # The bundle records when it was built; nothing else may differ.
        param([string] $Text)
        $Text = [regex]::Replace($Text, '"builtUtc"\s*:\s*"[^"]*"', '"builtUtc":"<masked>"')
        [regex]::Replace($Text, '("generatedBuildUtc"|"buildUtc")\s*:\s*"[^"]*"', '$1:"<masked>"')
    }
}

AfterAll {
    Remove-Module iSOCBlueprint -ErrorAction SilentlyContinue
    if ($global:iSOCParity -and $global:iSOCParity.Work -and (Test-Path -LiteralPath $global:iSOCParity.Work)) {
        Remove-Item -LiteralPath $global:iSOCParity.Work -Recurse -Force
    }
    Remove-Variable -Name iSOCParity -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Report parity: Markdown and the section model' {
    It 'writes the same set of files' {
        $script:p.ReportNew.Count | Should -BeGreaterThan 80
        $script:p.ReportNew | Should -Be $script:p.ReportOld
    }

    It 'writes the same <File>' -ForEach $reportFiles {
        $expected = ConvertTo-ExpectedText ([System.IO.File]::ReadAllText((Join-Path $script:p.Old $File)))
        $actual = [System.IO.File]::ReadAllText((Join-Path $script:p.New $File))
        Assert-SameText -Expected $expected -Actual $actual -What $File
    }

    It 'differs from the old output only in the four links, and has them' {
        $page = [System.IO.File]::ReadAllText((Join-Path $script:p.New '90-gap-analysis.md'))
        foreach ($c in $script:linkChanges | Where-Object { $_.Find -like '*Blueprint/Private*' }) {
            $page | Should -Match ([regex]::Escape($c.Replace))
        }
    }
}

Describe 'SharePoint bundle parity' {
    It 'writes the same set of files' {
        $script:p.BundleNew.Count | Should -BeGreaterThan 40
        $script:p.BundleNew | Should -Be $script:p.BundleOld
    }

    It 'writes the same <File>' -ForEach $bundleFiles {
        $expected = Remove-BuildStamp ([System.IO.File]::ReadAllText((Join-Path $script:p.SiteOld "sharepoint/$File")))
        $actual = Remove-BuildStamp ([System.IO.File]::ReadAllText((Join-Path $script:p.SiteNew "sharepoint/$File")))
        Assert-SameText -Expected $expected -Actual $actual -What "sharepoint/$File"
    }
}

Describe 'Assessment parity' {
    BeforeAll {
        $raw = Join-Path $script:p.New '_raw'
        $resources = Join-Path $script:repoRoot 'Tools/Blueprint/Private/Resources'
        . (Join-Path $script:repoRoot 'Tools/Blueprint/Private/Get-SentinelGap.ps1')
        . (Join-Path $script:repoRoot 'Tools/Blueprint/Private/Get-SentinelMaturity.ps1')
        $script:oldOutcomes = [System.Collections.Generic.List[object]]::new()
        $script:oldFindings = Get-SentinelGap -InputRoot $raw -ResourcesRoot $resources `
            -RulesPath (Join-Path $resources 'best-practices.json') `
            -GapChecksPath (Join-Path $script:repoRoot 'Tools/Blueprint/Private/GapChecks.ps1') `
            -OutcomeCollector $script:oldOutcomes 3>$null
        $script:oldMaturity = Get-SentinelMaturity -InputRoot $raw -ResourcesRoot $resources `
            -CriteriaPath (Join-Path $resources 'maturity-criteria.json') -GapOutcomes $script:oldOutcomes.ToArray() -TargetLevel 3

        $script:newFindings = @(Get-iSOCBlueprintFinding -Path $script:p.New 3>$null)
        $script:newOutcomes = @(Get-iSOCBlueprintFinding -Path $script:p.New -Outcome 3>$null)
        $script:newMaturity = Get-iSOCBlueprintMaturity -Path $script:p.New 3>$null

        function ConvertTo-Comparable {
            param($Value, [string[]] $Drop)
            $json = $Value | ConvertTo-Json -Depth 32
            foreach ($d in $Drop) { $json = [regex]::Replace($json, "`"$d`"\s*:\s*`"[^`"]*`"", "`"$d`": `"<masked>`"") }
            $json
        }
    }

    It 'finds the same findings' {
        $script:newFindings.Count | Should -Be @($script:oldFindings).Count
        ConvertTo-Comparable $script:newFindings 'PassedAt' | Should -BeExactly (ConvertTo-Comparable @($script:oldFindings) 'PassedAt')
    }

    It 'records the same outcome for every rule' {
        ConvertTo-Comparable $script:newOutcomes | Should -BeExactly (ConvertTo-Comparable $script:oldOutcomes.ToArray())
    }

    It 'scores the same maturity' {
        ConvertTo-Comparable $script:newMaturity 'generatedAtUtc' | Should -BeExactly (ConvertTo-Comparable $script:oldMaturity 'generatedAtUtc')
    }
}
