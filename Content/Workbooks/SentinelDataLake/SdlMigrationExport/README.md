# SdlMigrationExport (deprecated)

> **Deprecated.** This module is frozen and will be replaced by the
> `iSOCDeployments` PowerShell module. Until then it receives correctness fixes
> only.

Exports every dataset behind the Sentinel Data Lake Migration workbook
(`../workbook.json`) to one multi-sheet Excel file. Full documentation:
[Docs/Tools/SDL-Migration-Workbook-Export.md](../../../../Docs/Tools/SDL-Migration-Workbook-Export.md).

## Usage

```powershell
Import-Module ./Content/Workbooks/SentinelDataLake/SdlMigrationExport
Export-SdlMigrationWorkbook -SubscriptionId '<sub>' -ResourceGroupName '<rg>' -WorkspaceName '<ws>'
```

The workbook is written to the current directory unless you pass
`-OutputPath`. `-WhatIf` runs every query but writes no file; `-Verbose` traces
each ARM call and KQL query.

## Requirements

- PowerShell 7.2 or later.
- `Az.Accounts`, `Az.OperationalInsights` and `ImportExcel`. They are checked
  when the command runs rather than in `RequiredModules`, so the module imports
  (and its tests run) where they are not installed.
- Read access to the workspace. The command signs you in when the current Az
  context has no working token.

## Layout

| Path | Contents |
| --- | --- |
| `SdlMigrationExport.psd1` | Manifest: version, one exported function, dependencies |
| `SdlMigrationExport.psm1` | Loads `Private/` and `Public/`, exports `Export-SdlMigrationWorkbook` by name |
| `Public/` | `Export-SdlMigrationWorkbook`, the only exported command |
| `Private/<Area>/` | One internal function per file: Azure, Console, Inventory, Kql, Report, Rule, Workbook |

## Tests and lint

```powershell
Invoke-Pester -Path Tests/Test-ExportSdlMigrationWorkbook.Tests.ps1, Tests/Test-PSScriptAnalyzer.Tests.ps1
```

`Tests/Test-PSScriptAnalyzer.Tests.ps1` lints every PowerShell file in the
repository, these included, with the profiles in `Tests/PSScriptAnalyzer/`;
this module has no baseline entries, so every file must stay clean.
`Tests/Test-ExportSdlMigrationWorkbook.Tests.ps1` checks the coding-standard
rules PSScriptAnalyzer has no built-in rule for, and the module's behaviour.
Both run in the PR `validate` job of both pipelines, which install
PSScriptAnalyzer 1.25.0; a failure fails the pipeline.
