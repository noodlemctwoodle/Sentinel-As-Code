#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Holds the whole repository to PowerShell 7.6.

.DESCRIPTION
    PowerShell 7.6 is the floor everywhere the repository runs PowerShell:
    the modules, the tools, the tests, the content scripts, the pipelines
    and the DCR watchlist runbook. This suite checks every place that
    declares a version, so nothing drifts back to an older one:

      - every tracked .ps1 and .psm1 opens with #Requires -Version 7.6,
        PowerShell itself reads 7.6 as the file's requirement, and its
        .NOTES has one Requires: key, which starts with PowerShell 7.6+;
      - every module manifest declares PowerShellVersion = '7.6';
      - no workflow, composite action or ADO pipeline runs a step in
        Windows PowerShell;
      - every Azure Automation runtime environment in Bicep is
        PowerShell 7.6, every PowerShell runbook runs on one, and the
        pipelines that import the runbook link it to that environment;
      - no file states a PowerShell requirement below 7.6 (a #Requires
        line in a code sample, "PowerShell 7.2+", "PS 7.4 or later",
        a Requires: line). CHANGELOG.md and MIGRATION.md are history and
        are not scanned.

    It reads files only. The hosted agents have run PowerShell 7.6 since
    June 2026, and #Requires stops any file on an older version.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-PowerShellVersion.Tests.ps1

    Checks the whole repository against the PowerShell 7.6 floor.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-PowerShellVersion.Tests.ps1 -Output Detailed

    Runs with per-assertion output. A failure lists every file that
    breaks the rule, with the line where there is one.

.NOTES
    File:         Tests/Test-PowerShellVersion.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-09
    Version:      0.1.0
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+, git

    Lists the files with git ls-files, so untracked scratch files are not
    held to the rule. Without git (a downloaded archive) it walks the
    folder instead, skipping node_modules, test-results and SecurityDocs.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:floor = [version]'7.6'
    $script:self = 'Tests/Test-PowerShellVersion.Tests.ps1'
    $script:allFiles = $null

    function Get-RepoFile {
        <#
        .SYNOPSIS
            Lists the tracked repository files that have one of the given extensions.
        .PARAMETER Extension
            File extensions to keep, without the dot.
        #>
        param([Parameter(Mandatory)] [string[]] $Extension)

        if ($null -eq $script:allFiles) {
            # Every tracked file is listed once and filtered here, never with a
            # git pathspec: on macOS and Linux PowerShell expands a wildcard
            # held in a variable against the current folder before git sees it.
            $listing = git -C $script:repoRoot ls-files -z 2>$null
            if ($LASTEXITCODE -eq 0 -and $listing) {
                $script:allFiles = @(($listing -join '') -split "`0" | Where-Object { $_ })
            } else {
                $skip = '(^|/)(node_modules|\.git|test-results|SecurityDocs)/'
                $script:allFiles = @(Get-ChildItem -Path $script:repoRoot -Recurse -File -Force |
                        ForEach-Object { [IO.Path]::GetRelativePath($script:repoRoot, $_.FullName).Replace('\', '/') } |
                        Where-Object { $_ -notmatch $skip })
            }
            $script:allFiles = @($script:allFiles | Where-Object { [IO.File]::Exists((Join-Path $script:repoRoot $_)) })
        }
        $pattern = '\.(' + (($Extension | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')$'
        $script:allFiles | Where-Object { $_ -match $pattern }
    }

    function Read-RepoFile {
        <#
        .SYNOPSIS
            Reads a repository file as text.
        .PARAMETER Path
            Repository-relative path of the file.
        #>
        param([Parameter(Mandatory)] [string] $Path)
        [IO.File]::ReadAllText((Join-Path $script:repoRoot $Path))
    }

    function ConvertTo-FloorVersion {
        <#
        .SYNOPSIS
            Converts a version floor such as 7 or 7.4 to a version object.
        .PARAMETER Text
            The version text; a bare major number gets a zero minor.
        #>
        param([Parameter(Mandatory)] [string] $Text)
        if ($Text -notmatch '\.') { $Text = "$Text.0" }
        [version]$Text
    }

    function Get-BicepResource {
        <#
        .SYNOPSIS
            Returns the text of each Bicep resource declaration of one type.
        .PARAMETER Text
            The Bicep source.
        .PARAMETER Type
            The resource type to find, without the API version.
        #>
        param(
            [Parameter(Mandatory)] [string] $Text,
            [Parameter(Mandatory)] [string] $Type
        )
        $declarations = [regex]::Matches($Text, "(?m)^\s*resource\s+\w+\s+'$([regex]::Escape($Type))@[^']+'\s*=\s*\{")
        foreach ($declaration in $declarations) {
            $start = $declaration.Index + $declaration.Length - 1
            $depth = 0
            for ($i = $start; $i -lt $Text.Length; $i++) {
                if ($Text[$i] -eq '{') { $depth++ }
                elseif ($Text[$i] -eq '}') {
                    $depth--
                    if ($depth -eq 0) { $Text.Substring($start, $i - $start + 1); break }
                }
            }
        }
    }

    function Get-Because {
        <#
        .SYNOPSIS
            Builds the failure reason shown when files break a rule.
        .PARAMETER Offender
            The files that break the rule.
        #>
        param([string[]] $Offender)
        if (-not $Offender) { return 'nothing breaks the rule' }
        "these break the rule ($($Offender.Count)): " + ($Offender -join '; ')
    }

    $script:scripts = @(Get-RepoFile -Extension 'ps1', 'psm1')
    $script:manifests = @(Get-RepoFile -Extension 'psd1')
    $script:yaml = @(Get-RepoFile -Extension 'yml', 'yaml' |
            Where-Object { $_ -match '^(\.github/workflows/|\.github/actions/|Pipelines/)' })
    $script:bicep = @(Get-RepoFile -Extension 'bicep')
    $script:text = @(Get-RepoFile -Extension 'md', 'yml', 'yaml', 'ps1', 'psm1', 'psd1', 'bicep', 'json', 'html', 'template' |
            Where-Object {
                $_ -ne $script:self -and
                $_ -notmatch '(^|/)(CHANGELOG|MIGRATION)\.md$' -and
                $_ -notmatch '(^|/)(package-lock|dependencies)\.json$'
            })
}

Describe 'PowerShell 7.6 floor' {

    Context 'Scripts and modules' {

        It 'finds the scripts to check' {
            $script:scripts.Count | Should -BeGreaterThan 0
        }

        It 'opens every .ps1 and .psm1 with #Requires -Version 7.6' {
            $offenders = foreach ($file in $script:scripts) {
                $first = ((Read-RepoFile $file) -split '\r?\n', 2)[0]
                if ($first -ne '#Requires -Version 7.6') { "$file opens with '$first'" }
            }
            @($offenders).Count | Should -Be 0 -Because (Get-Because $offenders)
        }

        It 'gives every .ps1 and .psm1 a PowerShell requirement of exactly 7.6' {
            $offenders = foreach ($file in $script:scripts) {
                $tokens = $null
                $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseInput((Read-RepoFile $file), [ref]$tokens, [ref]$errors)
                $required = $ast.ScriptRequirements.RequiredPSVersion
                if ("$required" -ne '7.6') { "$file requires '$required'" }
            }
            @($offenders).Count | Should -Be 0 -Because (Get-Because $offenders)
        }

        It 'starts the Requires: line of every .ps1 and .psm1 with PowerShell 7.6+' {
            $offenders = foreach ($file in $script:scripts) {
                $help = [regex]::Match((Read-RepoFile $file), '(?s)<#(.*?)#>').Groups[1].Value
                $notes = [regex]::Match($help, '(?ms)^\s*\.NOTES\s*$(.*?)(?=^\s*\.[A-Z]+\s*$|\z)').Groups[1].Value
                $lines = [regex]::Matches($notes, '(?m)^\s+Requires:\s+(.*?)\s*$')
                if ($lines.Count -ne 1) { "$file has $($lines.Count) Requires: lines"; continue }
                $value = $lines[0].Groups[1].Value
                if ($value -notmatch '^PowerShell 7\.6\+(,|$)') { "$file says '$value'" }
            }
            @($offenders).Count | Should -Be 0 -Because (Get-Because $offenders)
        }

        It 'declares PowerShellVersion 7.6 in every module manifest' {
            $modules = foreach ($file in $script:manifests) {
                $data = Import-PowerShellDataFile -Path (Join-Path $script:repoRoot $file)
                if ($data.ContainsKey('RootModule') -or $data.ContainsKey('ModuleVersion')) {
                    [pscustomobject]@{ Path = $file; PowerShellVersion = $data.PowerShellVersion }
                }
            }
            @($modules).Count | Should -BeGreaterThan 0
            $offenders = $modules | Where-Object { $_.PowerShellVersion -ne '7.6' } |
                ForEach-Object { "$($_.Path) declares '$($_.PowerShellVersion)'" }
            @($offenders).Count | Should -Be 0 -Because (Get-Because $offenders)
        }
    }

    Context 'Pipelines' {

        It 'finds the workflows and pipelines to check' {
            $script:yaml.Count | Should -BeGreaterThan 0
        }

        It 'runs no step in Windows PowerShell' {
            $windowsPowerShell = @(
                '^\s*shell:\s*powershell\s*$'
                '^\s*pwsh:\s*false\b'
                '^\s*-\s*powershell:'
            )
            $offenders = foreach ($file in $script:yaml) {
                $number = 0
                foreach ($line in ((Read-RepoFile $file) -split '\r?\n')) {
                    $number++
                    foreach ($pattern in $windowsPowerShell) {
                        if ($line -match $pattern) { "${file}:$number '$($line.Trim())'" }
                    }
                }
            }
            @($offenders).Count | Should -Be 0 -Because (Get-Because $offenders)
        }
    }

    Context 'Azure Automation' {

        BeforeAll {
            $script:environments = foreach ($file in $script:bicep) {
                foreach ($block in (Get-BicepResource -Text (Read-RepoFile $file) -Type 'Microsoft.Automation/automationAccounts/runtimeEnvironments')) {
                    [pscustomobject]@{
                        Path     = $file
                        Name     = [regex]::Match($block, "(?m)^\s*name:\s*'([^']+)'").Groups[1].Value
                        Language = [regex]::Match($block, "(?m)^\s*language:\s*'([^']+)'").Groups[1].Value
                        Version  = [regex]::Match($block, "(?m)^\s*version:\s*'([^']+)'").Groups[1].Value
                    }
                }
            }
            $script:runbooks = foreach ($file in $script:bicep) {
                foreach ($block in (Get-BicepResource -Text (Read-RepoFile $file) -Type 'Microsoft.Automation/automationAccounts/runbooks')) {
                    [pscustomobject]@{
                        Path               = $file
                        Name               = [regex]::Match($block, "(?m)^\s*name:\s*'([^']+)'").Groups[1].Value
                        RunbookType        = [regex]::Match($block, "(?m)^\s*runbookType:\s*'([^']+)'").Groups[1].Value
                        RuntimeEnvironment = [regex]::Match($block, '(?m)^\s*runtimeEnvironment:\s*(\S+)').Groups[1].Value
                    }
                }
            }
            $script:importers = @($script:yaml | Where-Object { (Read-RepoFile $_) -match 'Import-AzAutomationRunbook' })
        }

        It 'reads every runbook and runtime environment the Bicep declares' {
            $declared = 0
            foreach ($file in $script:bicep) {
                $declared += [regex]::Matches((Read-RepoFile $file), "(?m)^\s*resource\s+\w+\s+'Microsoft\.Automation/automationAccounts/(runbooks|runtimeEnvironments)@").Count
            }
            (@($script:runbooks).Count + @($script:environments).Count) | Should -Be $declared
        }

        It 'makes every runtime environment PowerShell 7.6' {
            $offenders = $script:environments |
                Where-Object { $_.Language -ne 'PowerShell' -or $_.Version -ne '7.6' } |
                ForEach-Object { "$($_.Path) $($_.Name) is $($_.Language) $($_.Version)" }
            @($offenders).Count | Should -Be 0 -Because (Get-Because $offenders)
        }

        It 'runs every PowerShell runbook on a runtime environment' {
            $offenders = $script:runbooks |
                Where-Object { $_.RunbookType -like 'PowerShell*' } |
                Where-Object { $_.RunbookType -ne 'PowerShell' -or -not $_.RuntimeEnvironment } |
                ForEach-Object { "$($_.Path) $($_.Name) is '$($_.RunbookType)' on '$($_.RuntimeEnvironment)'" }
            @($offenders).Count | Should -Be 0 -Because (Get-Because $offenders)
        }

        It 'imports the runbook as PowerShell and links it to the Bicep runtime environment' {
            $names = @($script:environments | ForEach-Object Name)
            $offenders = foreach ($file in $script:importers) {
                $content = Read-RepoFile $file
                foreach ($import in [regex]::Matches($content, 'Import-AzAutomationRunbook(?:[^\r\n]*`\r?\n)*[^\r\n]*')) {
                    $type = [regex]::Match($import.Value, '-Type\s+(\S+)').Groups[1].Value
                    if ($type -ne 'PowerShell') { "$file imports as '$type'" }
                }
                $linked = [regex]::Match($content, '\$runtimeEnvironment\s*=\s*"([^"]+)"').Groups[1].Value
                if ($linked -notin $names) { "$file links to '$linked', not one of: $($names -join ', ')" }
            }
            @($offenders).Count | Should -Be 0 -Because (Get-Because $offenders)
        }
    }

    Context 'Stated requirements' {

        It 'finds the files to scan' {
            $script:text.Count | Should -BeGreaterThan 0
        }

        It 'states no PowerShell requirement below 7.6' {
            $patterns = @(
                '#Requires\s+-Version\s+(?<v>\d+(?:\.\d+)*)(?![\d\\])'
                '(?<![\w.-])(?:PowerShell|pwsh|PS) (?<v>\d+(?:\.\d+)*)(?![\d\\])(?:\+| or later| or newer| or above)'
                'Requires:\s+PowerShell (?<v>\d+(?:\.\d+)*)(?![\d\\])'
            )
            $offenders = foreach ($file in $script:text) {
                $number = 0
                foreach ($line in ((Read-RepoFile $file) -split '\r?\n')) {
                    $number++
                    foreach ($pattern in $patterns) {
                        foreach ($match in [regex]::Matches($line, $pattern)) {
                            if ((ConvertTo-FloorVersion $match.Groups['v'].Value) -lt $script:floor) {
                                "${file}:$number '$($match.Value)'"
                            }
                        }
                    }
                }
            }
            @($offenders).Count | Should -Be 0 -Because (Get-Because $offenders)
        }
    }
}
