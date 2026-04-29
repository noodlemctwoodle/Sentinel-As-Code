---
name: Pester tests
description: Conventions and patterns for Pester 5 tests under Tests/.
applyTo: "Tests/**/*.ps1"
---

# Pester test authoring

Pester 5 tests live under `Tests/`. The full conventions, AST-extraction
pattern, and test inventory are in
[`Docs/Development/Pester-Tests.md`](../../Docs/Development/Pester-Tests.md).
Read that doc before adding tests to an existing area or creating a
new test file.

## File-naming convention

`Tests/Test-<TargetName>.Tests.ps1`.

- `Tests/Test-AnalyticalRuleYaml.Tests.ps1` — schema test for content
  under `AnalyticalRules/` and `HuntingQueries/`
- `Tests/Test-DeployCustomContent.Tests.ps1` — unit tests for
  functions inside `Scripts/Deploy-CustomContent.ps1`
- `Tests/Test-SentinelCommon.Tests.ps1` — unit tests for the
  `Modules/Sentinel.Common/` PowerShell module

## File header

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    One-line summary.
.DESCRIPTION
    What this suite covers and what it deliberately doesn't cover.
#>
```

## The two test patterns this repo uses

### 1. Schema validation (`-ForEach` per-file)

Used by every `Tests/Test-*Yaml.Tests.ps1` and `Tests/Test-*Json.Tests.ps1`.
Generates one `It` block per content file via `BeforeDiscovery` so
per-file failures surface in the PR check UI.

```powershell
BeforeDiscovery {
    $files = Get-ChildItem -Path "$PSScriptRoot/../AnalyticalRules" -Recurse -Filter '*.yaml'
}

Describe 'AnalyticalRule schema' -ForEach $files {
    BeforeAll {
        # $_ at the It level is the file object from -ForEach
        $yaml = ConvertFrom-Yaml (Get-Content $_.FullName -Raw)
    }

    It "has a unique id GUID — <_.Name>" {
        $yaml.id | Should -Match '^[0-9a-fA-F-]{36}$'
    }
}
```

### 2. AST extraction for script unit tests

Used by every `Tests/Test-Deploy*.Tests.ps1` and similar. The pattern
extracts function definitions from a script via PowerShell's AST,
dot-sources them into the test scope, and unit-tests them in
isolation — so the script's `Main` block (which would call Az
cmdlets and connect to Azure) never runs.

```powershell
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module "$repoRoot/Tests/_helpers/Import-ScriptFunctions.psm1" -Force

    # AST-extract functions from the script under test.
    $script:functions = Import-ScriptFunctions `
        -ScriptPath "$repoRoot/Scripts/Deploy-CustomContent.ps1"

    # Dot-source the function bodies into the current scope.
    . ([scriptblock]::Create($script:functions))

    # If the script imports Sentinel.Common at top level, the AST
    # extractor skips that statement — import the module here so
    # extracted functions can call its exports at runtime.
    Import-Module "$repoRoot/Modules/Sentinel.Common/Sentinel.Common.psd1" -Force
}

Describe 'Get-PrioritizedFiles' {
    It 'orders parsers before detections' {
        # ... arrange / act / assert
    }
}
```

The AST helper is at
[`Tests/_helpers/Import-ScriptFunctions.psm1`](../../Tests/_helpers/Import-ScriptFunctions.psm1).
Its self-test is [`Tests/Test-ImportScriptFunctions.Tests.ps1`](../../Tests/Test-ImportScriptFunctions.Tests.ps1).

## Mocking in module-scope

When the script under test calls a `Sentinel.Common` function (e.g.
`Invoke-SentinelApi`, `Connect-AzureEnvironment`), use Pester's
`Mock -ModuleName Sentinel.Common` so the mock binds in the right
scope:

```powershell
Mock -ModuleName Sentinel.Common Invoke-SentinelApi {
    [pscustomobject]@{ value = @() }
}
```

Without `-ModuleName`, Pester scopes the mock to the test scope and
the module's call to `Invoke-SentinelApi` doesn't see it.

## `$TestDrive` for file-touching tests

`$TestDrive` is a per-test-block scratch directory Pester cleans up
automatically. Use it for tests that need real files:

```powershell
It 'reads a YAML file' {
    $tmp = Join-Path $TestDrive 'rule.yaml'
    Set-Content -Path $tmp -Value @"
id: 12345...
name: Test
"@
    Get-ContentDependencies -Path $tmp -KnownFunctions @{}
}
```

## Hard rules

1. **No live Azure calls.** Every test must run offline. Use `Mock`
   for `Az.*` cmdlets and the `Sentinel.Common` REST wrappers.
2. **Single-element array indexing trap.** When a function returns
   one item, `$result[0]` indexes into the *string* (returns the
   first character). Use `@($result)[0]` to force array context first.
3. **Don't dot-source the script under test directly.** Use the
   AST-extraction helper. Direct dot-source runs the script's `Main`
   block.
4. **Each test file pins its own `BeforeAll` setup.** Don't rely on
   state from another test file — Pester runs files in unspecified
   order.

## Running locally

```powershell
# All tests
./Scripts/Invoke-PRValidation.ps1 -RepoPath .

# Specific file
Invoke-Pester -Path Tests/Test-DeployCustomContent.Tests.ps1

# Specific Describe block within a file
Invoke-Pester -Path Tests/Test-DeployCustomContent.Tests.ps1 -FullName 'Get-PrioritizedFiles*'
```

## Cross-references

- Full conventions: [`Docs/Development/Pester-Tests.md`](../../Docs/Development/Pester-Tests.md)
- AST helper: [`Tests/_helpers/Import-ScriptFunctions.psm1`](../../Tests/_helpers/Import-ScriptFunctions.psm1)
- PR-validation entrypoint: [`Scripts/Invoke-PRValidation.ps1`](../../Scripts/Invoke-PRValidation.ps1)
