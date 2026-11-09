---
name: Pester tests
description: Conventions and patterns for Pester 5 tests under Tests/.
applyTo: "Tests/**/*.ps1"
---

# Pester test authoring

Pester 5 tests live under `Tests/`. The full conventions, AST-extraction
pattern, and test inventory are in
[`Docs/Tests/Pester-Tests.md`](../../Docs/Tests/Pester-Tests.md).
Read that doc before adding tests to an existing area or creating a
new test file.

## File-naming convention

`Tests/Test-<TargetName>.Tests.ps1`.

- `Tests/Test-AnalyticalRuleYaml.Tests.ps1` — schema test for content
  under `Content/AnalyticalRules/` and `Content/HuntingQueries/`
- `Tests/Test-PullRequestTemplate.Tests.ps1` - unit tests for
  functions inside `Tools/Test-PullRequestTemplate.ps1`
- `Tests/iSOCDeployments/<Area>.Tests.ps1` - unit tests for the
  `Modules/iSOCDeployments/` PowerShell module, one suite per area

## File header

```powershell
#Requires -Version 7.6
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

Used by the suites for scripts outside the modules (for example
`Tests/Test-PullRequestTemplate.Tests.ps1`). The pattern
extracts function definitions from a script via PowerShell's AST,
dot-sources them into the test scope, and unit-tests them in
isolation — so the script's `Main` block (which would call Az
cmdlets and connect to Azure) never runs.

```powershell
BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Tools/Test-PullRequestTemplate.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop

    # The helper dot-sources the script's top-level functions directly
    # into the caller's session via InvokeWithContext — no need to
    # capture a string and re-execute it.
    Import-ScriptFunctions -Path $scriptPath
}

Describe 'Get-PullRequestSection' {
    It 'splits the description at each heading' {
        # ... arrange / act / assert
    }
}
```

The AST helper is at
[`Tests/_helpers/Import-ScriptFunctions.psm1`](../../Tests/_helpers/Import-ScriptFunctions.psm1).
Its self-test is [`Tests/Test-ImportScriptFunctions.Tests.ps1`](../../Tests/Test-ImportScriptFunctions.Tests.ps1).

## Module suites and mocking in module scope

The `iSOCDeployments` suites import the module and reach its private
functions with `InModuleScope`. When the code under test calls another
function of the module (for example the REST client
`Invoke-iSOCRestRequest`), mock it with `-ModuleName iSOCDeployments`
so the mock binds in the module's scope:

```powershell
BeforeAll {
    Import-Module (Join-Path $repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
}

It 'reads the rules' {
    Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { @() }
    InModuleScope iSOCDeployments { Read-iSOCAnalyticsRuleWorkspace -Context $ctx }
}
```

Without `-ModuleName`, Pester scopes the mock to the test scope and
the module's call doesn't see it.

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
    Get-iSOCContentDependency -Path $tmp -RepoPath $TestDrive
}
```

## Hard rules

1. **No live Azure calls.** Every test must run offline. Use `Mock`
   for `Az.*` cmdlets and the module's REST client.
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
./Tools/Invoke-PRValidation.ps1 -RepoPath .

# Specific file
Invoke-Pester -Path Tests/Test-DeployCustomContent.Tests.ps1

# Specific Describe block within a file
Invoke-Pester -Path Tests/Test-DeployCustomContent.Tests.ps1 -FullName 'Get-PrioritizedFiles*'
```

## Cross-references

- Full conventions: [`Docs/Tests/Pester-Tests.md`](../../Docs/Tests/Pester-Tests.md)
- AST helper: [`Tests/_helpers/Import-ScriptFunctions.psm1`](../../Tests/_helpers/Import-ScriptFunctions.psm1)
- PR-validation entrypoint: [`Tools/Invoke-PRValidation.ps1`](../../Tools/Invoke-PRValidation.ps1)
