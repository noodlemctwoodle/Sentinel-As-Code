#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 schema validation for every YAML in Parsers/.

.DESCRIPTION
    Parsers ship as YAML files describing a workspace saved-search KQL
    function. Each parser is later referenced by analytical rules and
    hunting queries via its `functionAlias`. A typo in the alias breaks
    every rule that depends on it.

    Schema:
    - Required: id, name, description, category, functionAlias, query
    - functionAlias: must be a valid KQL function-name identifier
      (^[A-Za-z_][A-Za-z0-9_]*$)
    - functionAlias uniqueness: globally unique across the parser tree
      (Sentinel rejects duplicates)

.NOTES
    Run all tests:
        Invoke-Pester -Path Tests/Test-ParserYaml.Tests.ps1
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module -Name powershell-yaml -Force -Scope CurrentUser -AllowClobber | Out-Null
    }
    Import-Module powershell-yaml -ErrorAction Stop

    $script:parserCases = @()
    $parsersRoot = Join-Path $repoRoot 'Parsers'
    if (Test-Path $parsersRoot) {
        $script:parserCases = @(Get-ChildItem -Path $parsersRoot -Recurse -Filter '*.yaml' -File | ForEach-Object {
            $rel = ($_.FullName.Substring($repoRoot.Length + 1)) -replace '\\', '/'
            $yaml = $null
            $parseError = $null
            try {
                $raw = Get-Content -Path $_.FullName -Raw -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace($raw)) { throw 'File is empty' }
                $yaml = ConvertFrom-Yaml $raw
            }
            catch {
                $parseError = $_.Exception.Message
            }

            @{
                Path         = $_.FullName
                RelativePath = $rel
                Yaml         = $yaml
                ParseError   = $parseError
                ParseFailed  = ($null -ne $parseError) -or ($null -eq $yaml)
            }
        })
    }
}

BeforeAll {
    $script:RequiredParserFields = @('id', 'name', 'description', 'category', 'functionAlias', 'query')
    # KQL function names: letter or underscore start, then letters/digits/underscores
    $script:KqlIdentifierPattern = '^[A-Za-z_][A-Za-z0-9_]*$'
}

Describe 'Parser schema: <RelativePath>' -ForEach $script:parserCases {

    It 'parses as valid YAML with a mapping at the root' {
        $ParseError | Should -BeNullOrEmpty
        $Yaml       | Should -Not -BeNullOrEmpty
        ($Yaml -is [System.Collections.IDictionary]) | Should -BeTrue
    }

    Context 'Required fields' -Skip:$ParseFailed {
        It 'has every required field non-empty' {
            foreach ($field in $script:RequiredParserFields) {
                $Yaml.ContainsKey($field) | Should -BeTrue -Because "parser YAML must declare '$field'"
                ([string]$Yaml[$field]).Trim() | Should -Not -BeNullOrEmpty -Because "parser YAML '$field' must be non-empty"
            }
        }

        It 'functionAlias is a valid KQL identifier' {
            [string]$Yaml.functionAlias | Should -Match $script:KqlIdentifierPattern -Because 'functionAlias becomes a callable KQL function name; must start with a letter or underscore and contain only word characters'
        }
    }
}

Describe 'Parsers: cross-file invariants' {
    BeforeAll {
        if (-not (Get-Module -Name powershell-yaml)) {
            Import-Module powershell-yaml -ErrorAction Stop
        }
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $parsersRoot = Join-Path $repoRoot 'Parsers'

        $script:functionAliasMap = @{}
        if (Test-Path $parsersRoot) {
            Get-ChildItem -Path $parsersRoot -Recurse -Filter '*.yaml' -File | ForEach-Object {
                try {
                    $y = ConvertFrom-Yaml (Get-Content $_.FullName -Raw)
                    if (-not $y -or -not $y.ContainsKey('functionAlias')) { return }
                    $alias = [string]$y.functionAlias
                    if (-not $script:functionAliasMap.ContainsKey($alias)) { $script:functionAliasMap[$alias] = @() }
                    $rel = ($_.FullName.Substring($repoRoot.Length + 1)) -replace '\\', '/'
                    $script:functionAliasMap[$alias] += $rel
                }
                catch {
                    # Per-file test owns parse errors.
                }
            }
        }
    }

    It 'every functionAlias is unique across Parsers/' {
        $duplicates = $script:functionAliasMap.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
        if ($duplicates) {
            $report = ($duplicates | ForEach-Object {
                "  alias '$($_.Key)' used by:`n    - $($_.Value -join "`n    - ")"
            }) -join "`n"
            throw "Duplicate functionAlias values found (Sentinel rejects duplicate workspace function names):`n$report"
        }
    }
}
