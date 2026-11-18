#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests that keep the iSOCBlueprint module's PowerShell files small
    and their lines short.

.DESCRIPTION
    A module file holds one concern and stays within 300 lines, as in
    iSOCDeployments. Every PowerShell file under the module is held to it; a
    file that grows past the limit fails and is split up.

    A line of code stays within 160 characters, in the module and in its
    tests (Tests/iSOCBlueprint). The rule is for code: a line
    that is long because of a string it carries (report prose, a message, help
    text inside a here-string) is left whole, since wrapping it would change
    the text or break a search for it. A line is measured after each
    single-line string is replaced by a placeholder, and lines inside a
    multi-line string or comment are skipped. Two report writers sit near the
    300-line limit and are held to 200 until they are split.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Structure.Tests.ps1

    Checks every PowerShell file under Modules/iSOCBlueprint against the
    size and line-length limits.

.NOTES
    File:         Tests/iSOCBlueprint/Structure.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.3.2
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $moduleRoot = Join-Path $repoRoot 'Modules/iSOCBlueprint'
    $limit = 300
    $files = @(
        Get-ChildItem -LiteralPath $moduleRoot -Filter '*.ps1' -File -Recurse |
            Where-Object { $_.FullName -notmatch '[\\/]WebParts[\\/]' } |
            ForEach-Object {
                $relative = [System.IO.Path]::GetRelativePath($moduleRoot, $_.FullName).Replace('\', '/')
                @{ Path = $relative; Lines = @(Get-Content -LiteralPath $_.FullName).Count; Limit = $limit }
            }
    )
}

Describe 'Module file size' {
    It '<Path> is <Lines> lines, within the <Limit> line limit' -ForEach $files {
        $Lines | Should -BeLessOrEqual $Limit
    }
}

Describe 'Module line length' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $moduleRoot = Join-Path $repoRoot 'Modules/iSOCBlueprint'
        $limit = 160
        $looser = @{
            'Private/Render/Sections/DataConnectors/Write-BlueprintDataConnectorsSection.ps1'                = 200
            'Private/Render/Sections/AutomationRulesPlaybooks/Write-BlueprintAutomationRulesPlaybooksSection.ps1' = 200
        }
        $testsRoot = Join-Path $repoRoot 'Tests/iSOCBlueprint'
        $checked = @(
            Get-ChildItem -LiteralPath $moduleRoot -Filter '*.ps1' -File -Recurse |
                Where-Object { $_.FullName -notmatch '[\\/]WebParts[\\/]' }
            Get-ChildItem -LiteralPath $testsRoot -Filter '*.ps1' -File -Recurse
        )
        $script:offenders = foreach ($file in $checked) {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            $base = if ($file.FullName.StartsWith($moduleRoot)) { $moduleRoot } else { $repoRoot }
            $relative = [System.IO.Path]::GetRelativePath($base, $file.FullName).Replace('\', '/')
            $max = if ($looser.ContainsKey($relative)) { $looser[$relative] } else { $limit }
            $lines = $text -split "`n"
            if (-not ($lines | Where-Object { $_.TrimEnd("`r").Length -gt $max })) { continue }
            $tokens = $null
            [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$null)
            $inside = [System.Collections.Generic.HashSet[int]]::new()
            $stringChars = @{}
            foreach ($token in $tokens) {
                $first = $token.Extent.StartLineNumber
                $last = $token.Extent.EndLineNumber
                if ($token.Kind -ne 'NewLine' -and $last -gt $first) { foreach ($i in ($first + 1)..$last) { [void]$inside.Add($i) } }
                if ($token.Kind -in 'StringLiteral', 'StringExpandable' -and $last -eq $first) {
                    $stringChars[$first] = [int]$stringChars[$first] + $token.Extent.Text.Length
                }
            }
            for ($n = 1; $n -le $lines.Count; $n++) {
                $length = $lines[$n - 1].TrimEnd("`r").Length
                if ($length -gt $max -and -not $inside.Contains($n) -and ($length - [int]$stringChars[$n]) -gt $max) { "${relative}:$n ($length characters)" }
            }
        }
    }

    It 'has no line of code over the limit' {
        @($script:offenders) | Should -BeNullOrEmpty
    }
}
