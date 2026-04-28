# Pester Tests

Unit tests for PowerShell scripts in this repo use [Pester 5](https://pester.dev),
the standard PowerShell testing framework. Tests live alongside the scripts
they cover under [`Tests/`](../Tests/) and exercise pure functions in
isolation — no Azure connectivity, no live workspaces, no side effects on
the repo working tree.

| What | Where |
| --- | --- |
| Test files | [`Tests/`](../Tests/) — one `<ScriptName>.Tests.ps1` per source script |
| Convention | Pester 5+ discovery model (`Describe` / `Context` / `It` / `BeforeAll`) |
| Isolation | `$TestDrive` for temp files; AST extraction so source scripts never run their `Main` |

## Prerequisites

| Component | Minimum | Install |
| --- | --- | --- |
| PowerShell | 7.2+ | [pwsh download](https://github.com/PowerShell/PowerShell/releases) |
| Pester | 5.0+ | `Install-Module -Name Pester -Force -SkipPublisherCheck` |
| `powershell-yaml` | any | Auto-installed by tests when needed |

Verify Pester is available:

```powershell
Get-Module -ListAvailable Pester | Select-Object Name, Version
```

## Running tests

### All tests

```powershell
Invoke-Pester -Path Tests -CI
```

`-CI` exits non-zero on any failure and is the right flag for pipelines and
local pre-commit hooks.

### A specific test file

```powershell
Invoke-Pester -Path Tests/Test-SentinelRuleDrift.Tests.ps1 -CI
```

### A specific Describe block

```powershell
Invoke-Pester -Path Tests/Test-SentinelRuleDrift.Tests.ps1 -FullName '*Update-RuleYamlFile*'
```

### Verbose / detailed output

```powershell
Invoke-Pester -Path Tests/Test-SentinelRuleDrift.Tests.ps1 -Output Detailed
```

`-Output Detailed` shows every individual `It` block as it runs. The default
(`-Output Normal`) shows just per-file pass/fail and any failure details.

### Code coverage

```powershell
Invoke-Pester -Path Tests/Test-SentinelRuleDrift.Tests.ps1 `
    -CodeCoverage Scripts/Test-SentinelRuleDrift.ps1 `
    -Output Detailed
```

Reports which lines of the source script each test exercised.

## Test file layout

Each test file follows this skeleton (see
[`Tests/Test-SentinelRuleDrift.Tests.ps1`](../Tests/Test-SentinelRuleDrift.Tests.ps1)
for the full real example):

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<# .SYNOPSIS / .DESCRIPTION / .NOTES #>

BeforeAll {
    # 1. Resolve the source script path
    $scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Scripts/<ScriptName>.ps1'

    # 2. AST-extract just the function definitions — see "AST extraction" below
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath, [ref]$tokens, [ref]$errors
    )
    $funcs = $ast.FindAll(
        { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] },
        $false
    )
    $src = ($funcs | ForEach-Object { $_.Extent.Text }) -join "`n`n"

    # 3. Stub any script-scoped constants the functions reference
    $script:Constant1 = 'value'

    # 4. Dot-source the function bodies into the test scope
    . ([ScriptBlock]::Create($src))
}

Describe 'FunctionName' {
    Context 'Some scenario' {
        It 'has the expected behaviour' {
            $result = FunctionName -Input 'x'
            $result | Should -Be 'expected'
        }
    }
}
```

## The AST-extraction pattern

Most production scripts in this repo end with a top-level call like
`Invoke-Main` or have a `param()` block at the top. Naively dot-sourcing
them in a test file would:

- Trigger `Invoke-Main`, which tries to authenticate to Azure
- Choke on mandatory `param(...)` values
- Pollute the test scope with side effects

The AST-extraction pattern walks the parsed script tree, collects only the
top-level `FunctionDefinitionAst` nodes, joins their text, and dot-sources
just that. The param block, the constants, and any final invocation are
left behind.

```powershell
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath, [ref]$tokens, [ref]$errors
)
$funcs = $ast.FindAll(
    { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] },
    $false   # IMPORTANT: $false = top-level only, not nested helpers
)
. ([ScriptBlock]::Create(($funcs.Extent.Text -join "`n`n")))
```

Critically the `$false` second argument to `FindAll` means "top-level
functions only, not nested ones". Without it you'd duplicate every nested
function definition.

If a function references script-scoped constants (`$script:Foo`), declare
them in `BeforeAll` after the dot-source so the functions can see them:

```powershell
$script:DiffSnippetLength  = 0
$script:SentinelApiVersion = '2025-09-01'
$script:ManagedRuleKinds   = @('Fusion', 'MicrosoftSecurityIncidentCreation')
```

## Mock builders

For functions that take complex parameter objects, define small builders in
`BeforeAll` that produce baseline values with optional overrides. This
keeps individual `It` blocks short — they only declare the fields the test
actually cares about.

```powershell
function New-DeployedScheduled {
    param([hashtable]$Override = @{})
    $base = @{
        kind             = 'Scheduled'
        displayName      = 'Mock rule'
        severity         = 'Medium'
        # ...full default shape...
    }
    foreach ($k in $Override.Keys) { $base[$k] = $Override[$k] }
    return $base
}
```

Use them like:

```powershell
It 'detects severity change' {
    $deployed = New-DeployedScheduled @{ severity = 'High' }
    $expected = New-DeployedScheduled
    $diff = Compare-SentinelRule -Deployed $deployed -Expected $expected
    $diff.HasDrift | Should -BeTrue
}
```

Each test stays focused on the field it's asserting against.

## `$TestDrive` for file-touching tests

When a function reads or writes files (e.g. `Update-RuleYamlFile`), use
Pester's built-in `$TestDrive` variable as the target directory. Pester
creates a fresh temp folder per test container and removes it automatically
when the run ends.

```powershell
It 'rewrites severity in place' {
    $tmp = Join-Path $TestDrive "rule-$([Guid]::NewGuid()).yaml"
    Copy-Item -Path $script:fixturePath -Destination $tmp

    $mods = @(@{ Field = 'severity'; Deployed = 'High'; Expected = 'Medium' })
    Update-RuleYamlFile -FilePath $tmp -Modifications $mods | Should -BeTrue
    Get-Content -Raw $tmp | Should -Match '(?m)^severity:\s+High\s*$'
}
```

Never write into `$repoRoot/AnalyticalRules/` from a test — that would
mutate real repo files. Always copy the fixture into `$TestDrive` first.

## Adding tests for a new script

1. **Create the test file**: `Tests/<SourceScriptName>.Tests.ps1`. Match
   the source filename so the relationship is unambiguous.

2. **Use the AST-extraction skeleton** above. Replace `<ScriptName>.ps1`
   with the actual source script name and stub any `$script:*` constants
   the functions reference.

3. **Group tests by function**, not by feature: one top-level `Describe`
   block per public function. Inside each, use `Context` blocks to group
   related scenarios (`Context 'Single-field drift'`,
   `Context 'NRT rules'`, `Context 'Empty inputs'`).

4. **Aim for one assertion per `It` block** where practical. Multi-assertion
   `It`s are fine when they're testing the same behaviour from different
   angles, but split them when they're testing distinct contracts.

5. **Run the suite locally** with `-CI` before committing:

   ```powershell
   Invoke-Pester -Path Tests -CI
   ```

## Pester 5 syntax cheat sheet

| Construct | Purpose |
| --- | --- |
| `Describe 'Name' { ... }` | Top-level group, typically per function |
| `Context 'Scenario' { ... }` | Sub-group for related cases within a function |
| `It 'does X' { ... }` | A single test case |
| `BeforeAll { ... }` | Runs once before any tests in the enclosing block |
| `BeforeEach { ... }` | Runs before every `It` in the enclosing block |
| `AfterAll` / `AfterEach` | Cleanup counterparts |
| `Should -Be 'x'` | Strict equality |
| `Should -BeTrue` / `-BeFalse` | Boolean assertions |
| `Should -Match 'regex'` | Regex match |
| `Should -Contain 'x'` | Collection containment |
| `Should -BeNullOrEmpty` | Null or empty string/collection |
| `Should -Throw` | Asserts the script-block throws |
| `$TestDrive` | Per-container temp folder, auto-cleaned |

Full reference: [pester.dev](https://pester.dev/docs/usage/should).

## CI integration (optional)

To gate PRs on the test suite, add a stage to your pipeline:

```yaml
- stage: RunTests
  jobs:
    - job: Pester
      pool:
        vmImage: 'ubuntu-latest'
      steps:
        - checkout: self
        - task: PowerShell@2
          displayName: 'Install Pester'
          inputs:
            targetType: inline
            pwsh: true
            script: Install-Module -Name Pester -Force -SkipPublisherCheck
        - task: PowerShell@2
          displayName: 'Run Pester suite'
          inputs:
            targetType: inline
            pwsh: true
            script: |
              $result = Invoke-Pester -Path Tests -CI -PassThru
              if ($result.FailedCount -gt 0) {
                  Write-Host "##[error]$($result.FailedCount) Pester test(s) failed."
                  exit 1
              }
```

This is a separate concern from the deploy pipeline and the drift pipeline,
so a dedicated `Pipelines/Run-Tests.yml` is the cleanest home for it. Trigger
it on every PR via `pr: { branches: { include: [ main ] } }`.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `The term 'FunctionName' is not recognized` | AST extraction didn't include the function (e.g. nested in another function, or you passed `$true` to `FindAll` and got duplicates that misbehaved) | Verify with `$ast.FindAll(...).Name -join ','` that the expected function is in the list; ensure the `FindAll` second arg is `$false` |
| `Cannot find path '<TestDrive>'` outside an `It` block | `$TestDrive` is only valid inside test blocks | Move the file write into `It` or `BeforeEach`, not `BeforeAll` at the file scope |
| Tests pass locally but fail in CI | Pester version mismatch — CI on Pester 3.x, local on 5.x (or vice versa) | Pin Pester version in CI: `Install-Module Pester -RequiredVersion 5.7.1 -Force` |
| `Method invocation failed because [Object[]] does not contain a method named 'op_Subtraction'` | PowerShell `$arr[i, j]` indexing is array slicing, not 2-D access | Use jagged arrays (`int[][]`) or `.GetValue(i, j)` instead |
| AST extraction succeeds but functions reference undefined `$script:*` variables | Constants from the source script's prelude weren't stubbed in `BeforeAll` | Declare every `$script:*` the functions need before the dot-source |

## Test inventory

| File | Coverage | Tests |
| --- | --- | --- |
| [`Tests/Test-SentinelRuleDrift.Tests.ps1`](../Tests/Test-SentinelRuleDrift.Tests.ps1) | `Compare-SentinelRule`, `Update-RuleYamlFile`, `Get-LineDiff`, `Resolve-RuleSource` | 41 |

Add new entries to this table as you cover more scripts.
