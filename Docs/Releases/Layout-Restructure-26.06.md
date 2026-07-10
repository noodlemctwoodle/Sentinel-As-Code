# 26.06 Layout Restructure — Path Migration Guide

> **Status: complete, historical reference.** This restructure shipped in
> `26.06.1` and is already applied on `main`. If your fork was created after
> `26.06.1`, there is nothing left to migrate, this guide simply documents
> where each old path landed for anyone still reconciling an older fork or
> external links.

Release `26.06` reorganises the repository from a flat root into a by-concern
layout. This is a **structural change only** — no Sentinel content logic
changed. This guide maps every old path to its new home so forks and external
references can update.

## Why

The root previously mixed Sentinel content, infrastructure, deploy scripts, and
pipelines. They are now grouped into `Content/`, `Infra/`, `Deploy/`, and
`Tools/`. See [Issue #8](https://github.com/noodlemctwoodle/Sentinel-As-Code/issues/8).

## Old → new path map

### Content (all Sentinel content → `Content/`)

| Old | New |
|-----|-----|
| `AnalyticalRules/` | `Content/AnalyticalRules/` |
| `AutomationRules/` | `Content/AutomationRules/` |
| `DefenderCustomDetections/` | `Content/DefenderCustomDetections/` |
| `HuntingQueries/` | `Content/HuntingQueries/` |
| `Parsers/` | `Content/Parsers/` |
| `Playbooks/` | `Content/Playbooks/` |
| `SummaryRules/` | `Content/SummaryRules/` |
| `Watchlists/` | `Content/Watchlists/` |
| `Workbooks/` | `Content/Workbooks/` |

### Infrastructure (→ `Infra/`)

| Old | New |
|-----|-----|
| `Bicep/main.bicep` | `Infra/sentinel/main.bicep` |
| `Bicep/sentinel.bicep` | `Infra/sentinel/sentinel.bicep` |
| `Bicep/test/main.bicep` | `Infra/test-workspace/main.bicep` |
| `Automation/DCR-Watchlist/main.bicep` | `Infra/dcr-watchlist/main.bicep` |
| `Automation/DCR-Watchlist/modules/` | `Infra/dcr-watchlist/modules/` |
| `Automation/DCR-Watchlist/scripts/Invoke-DCRWatchlistSync.ps1` | `Tools/Invoke-DCRWatchlistSync.ps1` (runbook) |
| `Automation/DCR-Watchlist/scripts/Set-RunbookPermissions.ps1` | `Deploy/permissions/Set-RunbookPermissions.ps1` |

### Deployment scripts (→ `Deploy/`)

| Old | New |
|-----|-----|
| `Scripts/Deploy-CustomContent.ps1` | `Deploy/content/Deploy-CustomContent.ps1` |
| `Scripts/Deploy-DefenderDetections.ps1` | `Deploy/content/Deploy-DefenderDetections.ps1` |
| `Scripts/Deploy-SentinelContentHub.ps1` | `Deploy/content/Deploy-SentinelContentHub.ps1` |
| `Scripts/Set-PlaybookPermissions.ps1` | `Deploy/permissions/Set-PlaybookPermissions.ps1` |
| `Scripts/Setup-ServicePrincipal.ps1` | `Deploy/setup/Setup-ServicePrincipal.ps1` |
| `sentinel-deployment.config` | `Deploy/content/sentinel-deployment.config` |

### CI / maintenance / reporting tooling (→ `Tools/`)

| Old | New |
|-----|-----|
| `Scripts/Build-DependencyManifest.ps1` | `Tools/Build-DependencyManifest.ps1` |
| `Scripts/Test-SentinelRuleDrift.ps1` | `Tools/Test-SentinelRuleDrift.ps1` |
| `Scripts/Invoke-PRValidation.ps1` | `Tools/Invoke-PRValidation.ps1` |
| `Scripts/Export-SentinelWorkbooks.ps1` | `Tools/Export-SentinelWorkbooks.ps1` |
| `Scripts/Import-CommunityRules.ps1` | `Tools/Import-CommunityRules.ps1` |
| `Scripts/Documenter/` | `Tools/Documenter/` |

### Unchanged (stay at root)

`Docs/`, `Modules/`, `Tests/`, `Pipelines/`, `.github/`, `AGENTS.md`,
`README.md`, `LICENSE`, `dependencies.json`.

> `sentinel-deployment.config` now lives in `Deploy/`. The
> `Deploy-CustomContent.ps1` loader resolves it relative to its own folder
> (`$PSScriptRoot`), so no parameter change is needed.

## For fork maintainers

This section only applies if your fork still has content on the pre-`26.06.1`
flat layout. If you forked after `26.06.1`, skip it, your fork already has
the `Content/`, `Infra/`, `Deploy/`, and `Tools/` layout.

If you maintain a fork with custom content on the old layout:

1. **Merge or rebase the `26.06` restructure.** Tracked files move
   automatically via `git mv` (history preserved). Git rename detection
   reconciles your customised content with the relocated files.
2. **Relocate any stragglers** — untracked custom content or conflict
   leftovers still sitting at an old path — with the helper:
   ```powershell
   ./Tools/Migrate-ForkLayout.ps1 -WhatIf   # preview
   ./Tools/Migrate-ForkLayout.ps1           # apply
   ```
3. **Regenerate the dependency manifest** once your content is at its new path:
   ```powershell
   ./Tools/Build-DependencyManifest.ps1 -Mode Generate
   ```
4. **Update your own automation** (custom workflows/pipelines, scripts, raw
   URLs) that referenced the old paths, using the tables above.

## External references

Links to specific files (raw GitHub URLs, the community-rules importer, blog
posts) that point at old paths need updating to the `Content/…`, `Infra/…`,
`Deploy/…`, or `Tools/…` equivalents above. Versioning moved from "Wave N" to
CalVer at the same time — see [Versioning](Versioning.md).
