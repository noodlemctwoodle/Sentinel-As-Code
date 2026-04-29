---
description: Bootstraps a Pester 5 test file using the AST-extraction pattern this repo uses.
argument-hint: <script or module path you want to test>
agent: agent
tools: ['search/codebase', 'edit/applyPatch', 'terminal/run']
---

# New Pester test

Bootstrap a Pester 5 test file at
`Tests/Test-<TargetName>.Tests.ps1` using the AST-extraction pattern
the repo uses for script-level testing.

## When to use which pattern

| Target | Pattern | Existing example |
| --- | --- | --- |
| YAML / JSON content schema | `-ForEach` per-file generator | `Tests/Test-AnalyticalRuleYaml.Tests.ps1` |
| Functions inside a `*.ps1` script | AST extraction → dot-source | `Tests/Test-DeployCustomContent.Tests.ps1` |
| Functions exported from a `.psm1` | Direct `Import-Module` | `Tests/Test-SentinelCommon.Tests.ps1` |

## Steps

1. **Identify the target.** Ask the user for:
   - The target script or module path (e.g.
     `Scripts/Deploy-CustomContent.ps1`)
   - Which functions to cover (or "all of them")
   - What level of mocking is needed (Az cmdlets,
     `Sentinel.Common` REST wrappers, file system, etc.)

2. **Pick the pattern** based on the target:
   - Script with embedded functions → AST extraction
   - Module → direct `Import-Module`
   - Schema validation across many files → `-ForEach`

3. **Read an existing example** of the chosen pattern. Match its
   style — file header, `BeforeAll` block, `Describe` / `Context` /
   `It` structure.

4. **Set up mocks** for any Az cmdlet, `Sentinel.Common` function,
   or file-system call the target uses. For functions in
   `Sentinel.Common`, use `Mock -ModuleName Sentinel.Common` so the
   mock binds inside the module's session.

5. **Write the tests.** Cover:
   - Happy path (function returns expected output for valid input)
   - At least one failure case (rejects bad input with the
     documented exception)
   - Any edge case the function description specifically calls out

6. **Run locally** to confirm:
   ```powershell
   Invoke-Pester -Path Tests/Test-<TargetName>.Tests.ps1
   ```

7. **Add the file to the test inventory** in
   [`Docs/Development/Pester-Tests.md`](../../Docs/Development/Pester-Tests.md).

## Reference: AST-extraction pattern (script under test)

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 unit tests for functions in Scripts/<TargetName>.ps1.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module "$repoRoot/Tests/_helpers/Import-ScriptFunctions.psm1" -Force

    $script:functions = Import-ScriptFunctions `
        -ScriptPath "$repoRoot/Scripts/<TargetName>.ps1"
    . ([scriptblock]::Create($script:functions))

    Import-Module "$repoRoot/Modules/Sentinel.Common/Sentinel.Common.psd1" -Force
}

Describe '<FunctionUnderTest>' {
    Context 'happy path' {
        It 'returns the expected output for valid input' {
            <# arrange / act / assert #>
        }
    }

    Context 'failure handling' {
        It 'throws on invalid input' {
            { <FunctionUnderTest> -BadInput } | Should -Throw
        }
    }
}
```

## Reference: schema-validation pattern (-ForEach)

```powershell
BeforeDiscovery {
    $files = Get-ChildItem -Path "$PSScriptRoot/../<ContentDir>" -Recurse -Filter '*.yaml'
}

Describe '<ContentType> schema' -ForEach $files {
    BeforeAll {
        $yaml = ConvertFrom-Yaml (Get-Content $_.FullName -Raw)
        $relPath = $_.FullName.Substring(($PSScriptRoot + '/../').Length)
    }

    It "has a unique id GUID — $($_.Name)" {
        $yaml.id | Should -Match '^[0-9a-fA-F-]{36}$'
    }

    It "has the required field set — $($_.Name)" {
        foreach ($key in @('id', 'name', 'description', 'query')) {
            $yaml.ContainsKey($key) | Should -BeTrue -Because $key
        }
    }
}
```

## Hard rules

- **No live Azure calls.** Mock every Az cmdlet that the function
  under test calls.
- **Use `@($result)[0]` not `$result[0]`** — single-element
  PowerShell pipeline output is a string, and indexing a string
  returns characters.
- **Use `Mock -ModuleName Sentinel.Common`** for functions in
  the Sentinel.Common module so the mock takes effect.
- **Match repo style.** File header, `BeforeAll` setup,
  `Describe` / `Context` / `It` structure should mirror the
  reference example.

See the full conventions in
[`Docs/Development/Pester-Tests.md`](../../Docs/Development/Pester-Tests.md).
