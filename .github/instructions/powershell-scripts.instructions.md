---
name: PowerShell scripts and modules
description: Conventions for Scripts/**/*.ps1 and Modules/**/*.psm1 files.
applyTo: "Scripts/**/*.ps1,Modules/**/*.psm1,Modules/**/*.psd1"
---

# PowerShell scripts and modules

Deploy, drift, dependency, and bootstrap PowerShell. Conventions match
the existing repo style. Reference doc:
[`Docs/Deployment/Scripts.md`](../../Docs/Deployment/Scripts.md).

## Style and structure

- **PowerShell 7.2+** is the minimum (declared in
  `Sentinel.Common.psd1`). Use `pwsh`-only features freely; don't
  worry about Windows PowerShell 5.1 compatibility.
- **`Set-StrictMode -Version Latest`** is set in shared modules.
  Watch for read-of-undefined-property (`$x.PSObject.Properties['Foo']`
  is the safe pattern when `$x` might not have `Foo`).
- **`$ErrorActionPreference = 'Stop'`** at the top of every script
  and module. Errors should fail loud, not be silently swallowed.

## File header (required for new files)

```powershell
#
# Sentinel-As-Code/Scripts/<Name>.ps1
#
# Created by <author> on DD/MM/YYYY.
#

<#
.SYNOPSIS
    One-line summary.

.DESCRIPTION
    Multi-paragraph description: what does this script do, when
    should I run it, what does it produce?

.PARAMETER ParamName
    Per-parameter description.

.EXAMPLE
    ./Scripts/Foo.ps1 -ParamName Value
    Brief description of what the example does.

.NOTES
    Author:       <author>
    Version:      <semver>
    Last Updated: YYYY-MM-DD
    Repository:   Sentinel-As-Code
    Requires:     PowerShell 7.2+, Az.Accounts (etc.)
#>
```

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
   or `Connect-AzureEnvironment`.** Wave 4 Item 1 extracted those out
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
   `Set-PlaybookPermissions.ps1` Wave 3 fix is the canonical example.
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
[`./pester-tests.instructions.md`](./pester-tests.instructions.md)
for the AST-extraction pattern used to test functions defined in
scripts (rather than modules).

## Cross-references

- Script reference: [`Docs/Deployment/Scripts.md`](../../Docs/Deployment/Scripts.md)
- Module manifest: [`Modules/Sentinel.Common/Sentinel.Common.psd1`](../../Modules/Sentinel.Common/Sentinel.Common.psd1)
- Module body: [`Modules/Sentinel.Common/Sentinel.Common.psm1`](../../Modules/Sentinel.Common/Sentinel.Common.psm1)
- Tests: [`Tests/Test-SentinelCommon.Tests.ps1`](../../Tests/Test-SentinelCommon.Tests.ps1)
