---
name: PowerShell scripts and modules
description: Conventions for Deploy/**/*.ps1, Tools/**/*.ps1 and Modules/**/*.psm1 files.
applyTo: "Deploy/**/*.ps1,Tools/**/*.ps1,Modules/**/*.psm1,Modules/**/*.psd1"
---

# PowerShell scripts and modules

Deploy, drift, dependency, and bootstrap PowerShell. Conventions match
the existing repo style. Reference doc:
[`Docs/Deploy/Scripts.md`](../../Docs/Deploy/Scripts.md).

## Style and structure

- **PowerShell 7.2+** is the minimum (declared in
  `Sentinel.Common.psd1`). Use `pwsh`-only features freely; don't
  worry about Windows PowerShell 5.1 compatibility.
- **`Set-StrictMode -Version Latest`** is set in shared modules.
  Watch for read-of-undefined-property (`$x.PSObject.Properties['Foo']`
  is the safe pattern when `$x` might not have `Foo`).
- **`$ErrorActionPreference = 'Stop'`** at the top of every script
  and module. Errors should fail loud, not be silently swallowed.

## File header (required for every file)

Every `.ps1` and `.psm1` file starts with a comment-based help block
and **nothing above it** except `#Requires` statements. There is no
separate `#`-comment banner - the repo-relative path, author and dates
belong in `.NOTES`.

Keywords always appear in this order, one blank line between each:

```powershell
#Requires -Version 7.2

<#
.SYNOPSIS
    One sentence, no full stop needed. What the file does, not how.

.DESCRIPTION
    Multi-paragraph prose: what it does, when to run it, what it
    produces, and any behaviour a reader would otherwise have to
    infer from the code. Wrap at roughly 75 characters.

.PARAMETER ParamName
    One entry per parameter in the param block, in declaration order.
    Say what it controls and what happens when it is omitted.

.OUTPUTS
    Optional. The type emitted to the pipeline, and what it carries.

.EXAMPLE
    ./Deploy/Foo.ps1 -ParamName Value

    A blank line, then prose explaining what this invocation does and
    when you would reach for it.

.NOTES
    File:         Deploy/Foo.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      YYYY-MM-DD
    Version:      0.1.0
    Last Updated: YYYY-MM-DD
    Requires:     PowerShell 7.2+, Az.Accounts

    Any free-form notes go here, after a blank line, never welded
    onto the end of the metadata keys.

.LINK
    Optional. One URL per entry.
#>
```

Field rules for `.NOTES`:

- Every file carries the same eight keys, in the order shown, values
  aligned to a single column. Optional extras (`Component:`,
  `API Version:`, `Permissions:`) sit between `Last Updated:` and
  `Requires:`.
- **`File:`** - repo-relative path with no leading `./` and no
  `Sentinel-As-Code/` prefix. Keep it accurate when a file moves.
- **`Repository:`** - always `Sentinel-As-Code`.
- **`Author:`** - `noodlemctwoodle` unless the file was contributed
  by someone else, in which case credit them.
- **`Website:`** - always `https://sentinel.blog`.
- **`Created:`** / **`Last Updated:`** - ISO `YYYY-MM-DD`.
- **`Version:`** - semver. New files start at `0.1.0`. Bump on change.
- **`Requires:`** - mandatory, always the last key, always one line.
  Name the PowerShell floor first, then modules and external tooling.
  Where the file also carries `#Requires` statements, this line must
  name everything they enforce. `#Requires` is the functional gate;
  `Requires:` is the human-readable summary of it. Adding a
  `Requires:` line does not license adding a `#Requires` statement -
  those change whether the file will load at all.
- **Free-form prose** (provenance, RBAC needs, API versions, data
  sources) is allowed, but must be separated from the keys by a blank
  line so the metadata block stays scannable.

### Variants

**Files that define functions rather than run** (`Modules/**/*.psm1`,
`Tools/Documenter/Private/*.ps1`): the file-level block describes the
file and carries `.NOTES`. Per-parameter and per-example detail lives
on each function's own help block, not the file's.

**Pester test files** (`Tests/**/*.Tests.ps1`): no `.PARAMETER`, since
they take none. `.EXAMPLE` carries the `Invoke-Pester` invocations a
reader would actually run - the full file, a focused `-FullName`
subset, and detailed output where useful. Prerequisites go in
`.NOTES` prose.

**`.psd1` manifests** are data files (`@{ ... }`) and carry no
comment-based help. Their metadata lives in the manifest keys
(`Author`, `ModuleVersion`, `Description`) instead.

## Use the Sentinel.Common module

The repo's shared module exports the patterns every deployer uses:

| Function | Purpose |
| --- | --- |
| `Write-PipelineMessage -Level Section\|Info\|Success\|Warning\|Error -Message ...` | Single source of truth for ADO/GitHub/local logging output |
| `Invoke-SentinelApi -Uri ... -Method ... -Headers ...` | REST wrapper with retry-on-transient + StreamReader response-body recovery |
| `Connect-AzureEnvironment -ResourceGroup ... -Workspace ... -Region ... [-IsGov] [-PlaybookResourceGroup ...]` | Az context bootstrap; returns a state hashtable the caller assigns to its own scope |
| `Get-ContentDependencies -Path <yaml/json> -KnownFunctions <hashtable>` | Discover dependencies for a single content file |
| `Get-KqlBareIdentifiers -Query <kql>` | Extract bare table/function references from a KQL query |
| `Get-KqlWatchlistReferences` / `Get-KqlExternalDataReferences` / `Get-ContentKqlQuery` / `Remove-KqlComments` | Lower-level KQL discovery helpers |

Import the module at the top of any new deployer-style script:

```powershell
Import-Module "$PSScriptRoot/../Modules/Sentinel.Common/Sentinel.Common.psd1" -Force
```

## Hard rules

1. **Don't reimplement `Write-PipelineMessage`, `Invoke-SentinelApi`,
   or `Connect-AzureEnvironment`.** The Sentinel.Common module extracted those out
   of every script into the shared module specifically because
   inline duplication caused bug-fix-in-one-copy regressions. If a
   shared helper doesn't fit your need, add a new export to
   `Sentinel.Common.psm1` (with a Pester test) rather than inlining.
2. **PSGallery module pins.** Every workflow / pipeline pins
   `powershell-yaml` and `Pester` to specific versions (env vars
   `YAML_VERSION` / `PESTER_VERSION`). New scripts that need a
   PSGallery dep should pin too.
3. **`[void]` Boolean-leaking calls.** `Dictionary.Remove(key)`,
   `HashSet.Add(item)`, `List.Remove(item)` all return `Boolean`
   that PowerShell pipes to the function output stream. Prefix with
   `[void]` to suppress: `[void]$dict.Remove($key)`. The
   `Set-PlaybookPermissions.ps1` fix is the canonical example.
4. **Single-element array indexing.** `($func | ...)[0]` may index
   into a string when the pipeline returns one item. Use `@(...)[0]`
   to force array context first.
5. **Strict-mode-safe property access.** Don't use
   `$obj.MaybePresent` directly when strict mode is on; use
   `$obj.PSObject.Properties['MaybePresent']` and check for `$null`.
6. **Return values, not script-scope mutation.** `Connect-AzureEnvironment`
   used to mutate `$script:*` in the caller; that pattern doesn't
   survive module extraction (`$script:` in a module refers to the
   module's scope, not the caller's). Return a hashtable; let the
   caller assign.

## Adding a new function to Sentinel.Common

1. Add the function definition under the appropriate section in
   `Modules/Sentinel.Common/Sentinel.Common.psm1`.
2. Add it to `Export-ModuleMember -Function ...` at the bottom of
   the `.psm1`.
3. Add it to `FunctionsToExport` in
   `Modules/Sentinel.Common/Sentinel.Common.psd1`.
4. Bump `ModuleVersion` in the `.psd1` (semver: patch for bug fix,
   minor for new function, major for breaking change).
5. Update `ReleaseNotes` in `PrivateData.PSData`.
6. Add Pester tests to
   `Tests/Test-SentinelCommon.Tests.ps1`.

## Testing

Every public function gets a Pester unit test. See
[`./pester-tests.instructions.md`](pester-tests.instructions.md)
for the AST-extraction pattern used to test functions defined in
scripts (rather than modules).

## Cross-references

- Script reference: [`Docs/Deploy/Scripts.md`](../../Docs/Deploy/Scripts.md)
- Module manifest: [`Modules/Sentinel.Common/Sentinel.Common.psd1`](../../Modules/Sentinel.Common/Sentinel.Common.psd1)
- Module body: [`Modules/Sentinel.Common/Sentinel.Common.psm1`](../../Modules/Sentinel.Common/Sentinel.Common.psm1)
- Tests: [`Tests/Test-SentinelCommon.Tests.ps1`](../../Tests/Test-SentinelCommon.Tests.ps1)
