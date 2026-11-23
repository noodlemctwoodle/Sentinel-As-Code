#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests that hold the iSOCBlueprint module to the repo's PowerShell conventions.

.DESCRIPTION
    The rules are the ones in .github/instructions/powershell-scripts.instructions.md and
    the module's own layout, checked over every PowerShell file under
    Modules/iSOCBlueprint (the web part's build script aside):

    - File header: the PowerShell floor on the first line, a help block with a synopsis
      and the eight .NOTES keys in order, the File: key naming the file's own path.
    - One function to a file, named after it, with a comment line between the file help
      and the function so Get-Help does not show the file's text for the function. A Data
      folder holds script-scope values instead of functions.
    - Every function has an approved verb, [CmdletBinding()], help with a synopsis, and a
      .PARAMETER entry for each parameter it takes and none it does not.
    - No exit, no module installs, no Invoke-Expression, and no ForEach-Object member-name
      form (it returns nothing under -WhatIf).
    - No tabs, no trailing whitespace, LF line endings, a final newline.
    - No mention of an AI tool and no section-sign character.
    - The module's Markdown links resolve, and no page still names a script that the
      module replaced.

    Nested functions (a helper that closes over its parent's variables) are left alone: the
    one-function rule is about files.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Compliance.Tests.ps1

    Checks every module file against the rules above.

.NOTES
    File:         Tests/iSOCBlueprint/Compliance.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-23
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:moduleRoot = Join-Path $script:repoRoot 'Modules/iSOCBlueprint'
    $script:approved = @((Get-Verb).Verb)
    $ast = [System.Management.Automation.Language.FunctionDefinitionAst]

    $script:files = foreach ($file in Get-ChildItem -LiteralPath $script:moduleRoot -Filter '*.ps1' -File -Recurse |
            Where-Object { $_.FullName -notmatch '[\\/]WebParts[\\/]' }) {
        $text = [System.IO.File]::ReadAllText($file.FullName)
        $tokens = $null
        $errors = $null
        $tree = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
        [pscustomobject]@{
            Path   = [System.IO.Path]::GetRelativePath($script:repoRoot, $file.FullName).Replace('\', '/')
            Name   = $file.BaseName
            Text   = $text
            Tokens = $tokens
            Errors = $errors
            Tree   = $tree
            Top    = @($tree.FindAll({ param($n) $n -is $ast }, $false) |
                    Where-Object { $_.Parent -eq $tree.EndBlock })
            IsData = ($file.FullName -match '[\\/]Data[\\/]')
        }
    }

    function Get-Offender {
        param([scriptblock] $Where, [scriptblock] $Select)
        @($script:files | Where-Object $Where | ForEach-Object $Select)
    }
}

Describe 'Module files' {
    It 'all parse' {
        Get-Offender { $_.Errors.Count } { "$($_.Path): $($_.Errors[0].Message)" } | Should -BeNullOrEmpty
    }

    It 'open with the PowerShell floor and a help block' {
        Get-Offender { $_.Text -notmatch '^#Requires -Version 7\.6\r?\n(#Requires [^\n]*\n)*\s*<#' } { $_.Path } |
            Should -BeNullOrEmpty
    }

    It 'carry the eight .NOTES keys in order, with the right values' {
        $required = 'File', 'Repository', 'Author', 'Website', 'Created', 'Version', 'Last Updated', 'Requires'
        $found = foreach ($f in $script:files) {
            $notes = [regex]::Match($f.Text, '(?s)\.NOTES\r?\n(.*?)(?=\r?\n#>)').Groups[1].Value
            $pairs = [regex]::Matches($notes, '(?m)^    ([A-Za-z ]+):\s+(.*)$')
            $keys = @($pairs | ForEach-Object { $_.Groups[1].Value.Trim() })
            $value = @{}
            foreach ($p in $pairs) { if (-not $value.ContainsKey($p.Groups[1].Value.Trim())) { $value[$p.Groups[1].Value.Trim()] = $p.Groups[2].Value.Trim() } }
            $problem = $null
            if (@($required | Where-Object { $_ -notin $keys }).Count) { $problem = 'a key is missing' }
            elseif ((@($keys | Where-Object { $_ -in $required }) -join '|') -ne ($required -join '|')) { $problem = 'keys out of order' }
            elseif ($value['File'] -ne $f.Path) { $problem = "File: says $($value['File'])" }
            elseif ($value['Repository'] -ne 'Sentinel-As-Code') { $problem = 'Repository:' }
            elseif ($value['Author'] -ne 'noodlemctwoodle') { $problem = 'Author:' }
            elseif ($value['Website'] -ne 'https://sentinel.blog') { $problem = 'Website:' }
            elseif ($value['Created'] -notmatch '^\d{4}-\d\d-\d\d$' -or $value['Last Updated'] -notmatch '^\d{4}-\d\d-\d\d$') { $problem = 'a date is not ISO' }
            elseif ($value['Created'] -gt $value['Last Updated']) { $problem = 'Created is after Last Updated' }
            elseif ($value['Version'] -notmatch '^\d+\.\d+\.\d+$') { $problem = 'Version: is not semver' }
            elseif ($value['Requires'] -notmatch '^PowerShell 7\.6\+') { $problem = 'Requires: does not start with PowerShell 7.6+' }
            elseif ($keys[-1] -ne 'Requires' -and @($keys | Where-Object { $_ -in $required })[-1] -ne 'Requires') { $problem = 'Requires: is not last' }
            if ($problem) { "$($f.Path): $problem" }
        }
        @($found) | Should -BeNullOrEmpty
    }

    It 'define one function each, named after the file, and nothing else' {
        $found = foreach ($f in $script:files | Where-Object { $_.Path -match '/(Public|Private)/' -and -not $_.IsData }) {
            $others = @($f.Tree.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] })
            if ($f.Top.Count -ne 1) { "$($f.Path): defines $($f.Top.Count) functions" }
            elseif ($f.Top[0].Name -ne $f.Name) { "$($f.Path): defines $($f.Top[0].Name)" }
            elseif ($others.Count) { "$($f.Path): has other statements" }
        }
        @($found) | Should -BeNullOrEmpty
    }

    It 'keep functions out of the Data folders' {
        Get-Offender { $_.IsData -and $_.Top.Count } { $_.Path } | Should -BeNullOrEmpty
    }

    It 'put a comment line between the file help and the function' {
        Get-Offender { $_.Top.Count -and $_.Text -match '#>[ \t]*\r?\n([ \t]*\r?\n)?function ' } { $_.Path } |
            Should -BeNullOrEmpty
    }
}

Describe 'Module functions' {
    It 'use an approved verb in Verb-Noun form' {
        $found = foreach ($f in $script:files) {
            foreach ($fn in $f.Top) {
                if (($fn.Name -split '-')[0] -notin $script:approved -or $fn.Name -notmatch '^[A-Z][A-Za-z]+-[A-Za-z0-9]+$') { "$($f.Path): $($fn.Name)" }
            }
        }
        @($found) | Should -BeNullOrEmpty
    }

    It 'are advanced functions' {
        $found = foreach ($f in $script:files) {
            foreach ($fn in $f.Top) {
                if (-not ($fn.Body.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' })) { "$($f.Path): $($fn.Name)" }
            }
        }
        @($found) | Should -BeNullOrEmpty
    }

    It 'have help with a synopsis, and a parameter entry for each parameter and no other' {
        $found = foreach ($f in $script:files) {
            foreach ($fn in $f.Top) {
                $help = $fn.GetHelpContent()
                if (-not $help -or -not $help.Synopsis) { "$($f.Path): no synopsis"; continue }
                $declared = @($fn.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath.ToLower() })
                $documented = @($help.Parameters.Keys | ForEach-Object { $_.ToLower() })
                $missing = @($declared | Where-Object { $_ -notin $documented })
                $extra = @($documented | Where-Object { $_ -notin $declared })
                if ($missing) { "$($f.Path): undocumented $($missing -join ', ')" }
                if ($extra) { "$($f.Path): documents $($extra -join ', ') which it lacks" }
            }
        }
        @($found) | Should -BeNullOrEmpty
    }
}

Describe 'Module code' {
    It 'never calls exit, installs a module or uses Invoke-Expression' {
        $found = foreach ($f in $script:files) {
            foreach ($c in $f.Tree.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                if ($c.GetCommandName() -in 'Install-Module', 'Install-Package', 'Install-PSResource', 'Invoke-Expression', 'iex') {
                    "$($f.Path):$($c.Extent.StartLineNumber) $($c.GetCommandName())"
                }
            }
            foreach ($e in $f.Tree.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExitStatementAst] }, $true)) {
                "$($f.Path):$($e.Extent.StartLineNumber) exit"
            }
        }
        @($found) | Should -BeNullOrEmpty
    }

    It 'never uses the member-name form of ForEach-Object, which returns nothing under -WhatIf' {
        $found = foreach ($f in $script:files) {
            foreach ($c in $f.Tree.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in 'ForEach-Object', '%' }, $true)) {
                $first = @($c.CommandElements | Select-Object -Skip 1 | Select-Object -First 1)
                if ($first -and $first[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]) { "$($f.Path):$($c.Extent.StartLineNumber)" }
                elseif ($first -and $first[0] -is [System.Management.Automation.Language.CommandParameterAst] -and $first[0].ParameterName -like 'M*') { "$($f.Path):$($c.Extent.StartLineNumber)" }
            }
        }
        @($found) | Should -BeNullOrEmpty
    }
}

Describe 'Module text' {
    It 'has LF line endings, no tabs, no trailing whitespace and a final newline' {
        $found = foreach ($f in $script:files) {
            if ($f.Text.Contains("`r")) { "$($f.Path): CR" }
            elseif ($f.Text.Contains("`t")) { "$($f.Path): tab" }
            elseif ($f.Text -match '(?m)[ \t]+$') { "$($f.Path): trailing whitespace" }
            elseif (-not $f.Text.EndsWith("`n")) { "$($f.Path): no final newline" }
        }
        @($found) | Should -BeNullOrEmpty
    }

    It 'names no AI tool and uses no section sign' {
        $sign = [string][char]0x00A7
        $found = foreach ($f in $script:files) {
            if ($f.Text -match '(?i)\b(Claude|Anthropic|ChatGPT|Copilot|OpenAI)\b') { "$($f.Path): $($Matches[0])" }
            if ($f.Text.Contains($sign)) { "$($f.Path): section sign" }
        }
        @($found) | Should -BeNullOrEmpty
    }
}

Describe 'Module documents' {
    BeforeAll {
        $script:pages = @(
            Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'Docs/Modules/iSOCBlueprint') -Filter '*.md' -File
            Get-Item -LiteralPath (Join-Path $script:moduleRoot 'README.md'), (Join-Path $script:moduleRoot 'MIGRATION.md')
        )
    }

    It 'link only to files that exist' {
        $found = foreach ($page in $script:pages) {
            $inFence = $false
            $number = 0
            foreach ($line in [System.IO.File]::ReadAllLines($page.FullName)) {
                $number++
                if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
                if ($inFence) { continue }
                $plain = $line -replace '`[^`]*`', ''
                foreach ($m in [regex]::Matches($plain, '\]\((?<t>[^)\s]+)\)')) {
                    $target = $m.Groups['t'].Value
                    if ($target -match '^(https?:|mailto:|#)') { continue }
                    $path = ($target -split '#')[0]
                    if (-not $path) { continue }
                    if (-not (Test-Path -LiteralPath ([System.IO.Path]::GetFullPath((Join-Path $page.DirectoryName $path))))) {
                        "$([System.IO.Path]::GetRelativePath($script:repoRoot, $page.FullName)):$number $target"
                    }
                }
            }
        }
        @($found) | Should -BeNullOrEmpty
    }

    It 'no longer name a script or folder the module replaced' {
        $replaced = 'Invoke-iSOCBlueprintEngine|Export-SentinelInventory\.ps1|Convert-SentinelInventoryToMarkdown\.ps1|Convert-MarkdownToWord\.ps1|Build-SentinelDocsSite\.ps1|Publish-SentinelDocsSite\.ps1|Initialize-SentinelDocsSite\.ps1|Convert-MermaidToImage\.ps1|GapChecks\.ps1|Modules/iSOCBlueprint/Engine'
        $pages = @(Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'Docs/Modules/iSOCBlueprint') -Filter '*.md' -File)
        $found = foreach ($page in $pages) {
            $number = 0
            foreach ($line in [System.IO.File]::ReadAllLines($page.FullName)) {
                $number++
                if ($line -match $replaced) { "$($page.Name):$number $($Matches[0])" }
            }
        }
        @($found) | Should -BeNullOrEmpty
    }
}
