# Documenter test fixtures

> **These are NOT a snapshot of any real Sentinel workspace.**
> They are hand-authored synthetic data used by the Pester suite under
> [`Tests/Documenter/`](..) to verify the renderer and the gap-analysis
> engine offline.

## Why fixtures exist

The PR-validation gate (`.github/workflows/pr-validation.yml`) runs Pester
with **no Azure auth**. That means every test must be deterministic and
self-contained. Without checked-in fixtures the only way to test the
renderer or the gap engine would be a live tenant — which would gate the
test suite on credentials and make every PR untestable in CI.

## Why this fixture is deliberately broken

`sample/_raw/` encodes a workspace that violates many best-practice rules
on purpose, so each `Test-*` function in
[`Tools/Documenter/Private/GapChecks.ps1`](../../../Tools/Documenter/Private/GapChecks.ps1)
has at least one positive case to prove against. Each rule's expected
firing condition is documented in the comment block at the top of
[`Get-SentinelGap.Tests.ps1`](../Get-SentinelGap.Tests.ps1).

Examples of the brokenness:

| File | Brokenness |
|---|---|
| `workspace.json` | `dailyQuotaGb = -1`, `retentionInDays = 30`, `replication.enabled = false`, `publicNetworkAccessForIngestion = Enabled`, `disableLocalAuth = false` |
| `workspace-tables.json` | `FirewallLogs_CL` on Analytics with 730d retention; `OrphanTable_CL` with no data |
| `tables-with-data.json` | `AuditLogs` has data 90d ago but none last 7d (silent table) |
| `alert-rules.json` | One NRT rule disabled |
| `rbac-workspace.json` | A legacy admin group holds `Owner` at workspace scope |
| `resource-providers.json` | `Microsoft.Insights` is `NotRegistered` |

## How real workspaces produce JSON

When you run `Tools/Documenter/Export-SentinelInventory.ps1` against your
live workspace the collector writes JSON to `SecurityDocs/<workspace>/_raw/`
at the **repo root**. That folder is `.gitignore`'d so the data stays local
and rides out via the workflow's private artefact — it never lands in this
fixture directory.

Workflow → JSON path:
```
.github/workflows/sentinel-document.yml
  → Tools/Documenter/Export-SentinelInventory.ps1
    → SecurityDocs/<workspace>/_raw/*.json    ← gitignored, real data
```

Test → JSON path:
```
.github/workflows/pr-validation.yml
  → Tests/Documenter/Convert-SentinelInventoryToMarkdown.Tests.ps1
    → Tests/Documenter/Fixtures/sample/_raw/*.json   ← tracked, synthetic data
```

## Updating the fixture

Update the fixture only when:

- A new gap rule lands that needs a positive case to fire against, OR
- A real Azure REST shape changes meaningfully (e.g. a new property on a
  workspace `tables` response that the renderer must surface).

When the API shape changes, refresh by running the collector against a real
workspace, **scrubbing identifiers and any tenant-specific values**, then
copying the relevant subset into `sample/_raw/`. Never copy a real
workspace's data verbatim.

After any update, run:

```powershell
Invoke-Pester -Path Tests/Documenter -Output Detailed
```
