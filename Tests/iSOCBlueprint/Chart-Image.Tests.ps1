#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the chart image step.

.DESCRIPTION
    Runs Invoke-iSOCBlueprintChartImage against Markdown with Mermaid fences
    and a stand-in mmdc (a small shell script that writes a file, or fails
    for a chart containing BOOM), so the step's rewriting, de-duplication,
    failure handling and summary are checked without Node or a browser.

.NOTES
    File:         Tests/iSOCBlueprint/Chart-Image.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.1
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeAll {
    $script:moduleRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/iSOCBlueprint'
    Import-Module (Join-Path $script:moduleRoot 'iSOCBlueprint.psd1') -Force
    $script:module = Get-Module iSOCBlueprint
    $script:canRun = -not $IsWindows

    if ($script:canRun) {
        $bin = Join-Path $TestDrive 'bin'
        New-Item -ItemType Directory -Path $bin | Out-Null
        $fake = Join-Path $bin 'mmdc'
        @'
#!/bin/sh
out=""; in=""; prev=""
for a in "$@"; do
  if [ "$prev" = "-o" ]; then out="$a"; fi
  if [ "$prev" = "-i" ]; then in="$a"; fi
  prev="$a"
done
if grep -q BOOM "$in"; then exit 3; fi
echo fake > "$out"
'@ | Set-Content -LiteralPath $fake
        chmod +x $fake
        $script:oldPath = $env:PATH
        $env:PATH = "$bin$([System.IO.Path]::PathSeparator)$env:PATH"
    }

    function script:Invoke-Step {
        param([string] $Root, [hashtable] $Extra = @{})
        & $script:module { param($r, $e) Invoke-iSOCBlueprintChartImage -Root $r @e 6>&1 3>&1 | ForEach-Object { "$_" } } $Root $Extra
    }
}

AfterAll {
    if ($script:canRun) { $env:PATH = $script:oldPath }
}

Describe 'Invoke-iSOCBlueprintChartImage' {
    BeforeEach {
        $script:root = Join-Path $TestDrive "docs-$(New-Guid)"
        New-Item -ItemType Directory -Path (Join-Path $script:root 'ws') -Force | Out-Null
        $fence = '```'
        Set-Content -LiteralPath (Join-Path $script:root 'ws/a.md') -Value ("# T`n`n${fence}mermaid`nflowchart LR`n A-->B`n${fence}`n`ntext`n`n${fence}mermaid`nBOOM`n${fence}`n`n${fence}mermaid`nflowchart LR`n A-->B`n${fence}")
        Set-Content -LiteralPath (Join-Path $script:root 'ws/b.md') -Value 'no charts'
    }

    It 'rewrites a chart as an image reference, shares one image between identical charts and leaves a failed chart in place' -Skip:(-not $IsLinux -and
            -not $IsMacOS) {
        $log = Invoke-Step -Root $script:root
        $md = Get-Content -LiteralPath (Join-Path $script:root 'ws/a.md') -Raw
        ([regex]::Matches($md, '!\[Diagram\]\(assets/[0-9a-f]{12}\.png\)')).Count | Should -Be 2
        $md | Should -Match '(?s)```mermaid\r?\nBOOM\r?\n```'
        @(Get-ChildItem (Join-Path $script:root 'ws/assets') -Filter '*.png').Count | Should -Be 1
        ($log -join "`n") | Should -Match 'mmdc failed for hash'
    }

    It 'counts the charts seen, the images emitted and the failures in its summary' -Skip:(-not $IsLinux -and -not $IsMacOS) {
        $log = Invoke-Step -Root $script:root
        $text = $log -join "`n"
        $text | Should -Match 'Charts seen\s+: 3'
        $text | Should -Match 'Images emitted\s+: 2'
        $text | Should -Match 'Failures\s+: 1'
    }

    It 'leaves a file with no charts untouched' -Skip:(-not $IsLinux -and -not $IsMacOS) {
        Invoke-Step -Root $script:root | Out-Null
        (Get-Content -LiteralPath (Join-Path $script:root 'ws/b.md') -Raw).Trim() | Should -Be 'no charts'
    }

    It 'names the asset folder and the format it was given' -Skip:(-not $IsLinux -and -not $IsMacOS) {
        Invoke-Step -Root $script:root -Extra @{ AssetsDir = 'img'; Format = 'svg' } | Out-Null
        (Get-Content -LiteralPath (Join-Path $script:root 'ws/a.md') -Raw) | Should -Match '!\[Diagram\]\(img/[0-9a-f]{12}\.svg\)'
        Test-Path (Join-Path $script:root 'ws/img') | Should -BeTrue
    }

    It 'says so and does nothing when there are no workspace folders' {
        $empty = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $empty | Out-Null
        (Invoke-Step -Root $empty) -join "`n" | Should -Match 'No workspace folders found'
    }

    It 'fails clearly when the root is missing' {
        { Invoke-Step -Root (Join-Path $TestDrive 'nope') } | Should -Throw '*Root not found*'
    }
}

Describe 'Get-MermaidHash' {
    It 'is the first 12 hex characters of the SHA-256 of the text, in lower case' {
        $hash = & $script:module { Get-MermaidHash 'flowchart LR' }
        $hash | Should -Match '^[0-9a-f]{12}$'
        $expected = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes('flowchart LR'))).Replace('-',
            '').Substring(0, 12).ToLower()
        $hash | Should -Be $expected
    }
}
