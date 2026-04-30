# Workbooks

Custom workbooks for security dashboards and visualisations. Each workbook is a subfolder under [`Workbooks/`](../../Workbooks/) containing the gallery template JSON exported from the Sentinel workbook editor, and an optional metadata file.

## Folder Structure

```
Workbooks/
  SOCOverview/
    workbook.json           # Gallery template JSON (source of truth)
    metadata.json           # Optional: display name, description, stable GUID
  IdentityInsights/
    workbook.json
    metadata.json
```

## Workbook Template (workbook.json)

The gallery template JSON exported from the Sentinel workbook editor. Two ways to get it into the repo.

### Option 1: bulk export via `Export-SentinelWorkbooks.ps1` (recommended)

For exporting many workbooks at once, or for a one-off bootstrap of a workspace into the repo:

```powershell
./Scripts/Export-SentinelWorkbooks.ps1 `
    -ResourceGroup 'rg-sentinel-prod' `
    -Workspace     'law-sentinel-prod' `
    -Region        'uksouth'
```

This:

- Lists every Sentinel workbook in the workspace via the `Microsoft.Insights/workbooks` API (`category=sentinel`, filtered by `sourceId == workspaceResourceId`).
- Skips Content Hub-managed workbooks by default (override with `-IncludeContentHub`).
- For each remaining (Custom) workbook, writes `Workbooks/<FolderName>/workbook.json` (the gallery template) and `Workbooks/<FolderName>/metadata.json` (display name, description, category, source ID, **and the workbook resource GUID**).
- **Folder name = PascalCase compaction of `displayName`** (with the workspace-name suffix stripped). Non-alphanumeric runs become word boundaries; all-upper acronyms TitleCase to match the repo convention (`GBP` → `Gbp`); user-curated camelCase (e.g. `pfSense`) is preserved.

Useful flags:

| Flag | Purpose |
| --- | --- |
| `-Filter '^Identity'` | Regex applied to `displayName`; only matching workbooks export |
| `-OnlyMissing` | Skip workbooks that already have a folder under `Workbooks/`. Useful for incremental import without overwriting in-repo customisations |
| `-WhatIf` | Read everything, write nothing |
| `-IsGov` | Target Azure Government cloud |

Symmetry contract — the output shape exactly matches what [`Deploy-CustomWorkbooks`](../../Scripts/Deploy-CustomContent.ps1) reads back, including the workbook resource GUID, so the next deploy run updates the same Azure resource rather than spawning a duplicate.

### Option 2: manual per-workbook export

For exporting a single workbook ad hoc:

1. Open the workbook in **Microsoft Sentinel > Workbooks**
2. Click **Edit**, then **Advanced Editor** (the `</>` icon)
3. Select the **Gallery Template** tab
4. Copy the full JSON content
5. Save as `workbook.json` in a new subfolder
6. Optionally hand-author the matching `metadata.json` (the deploy script can derive a deterministic GUID from the folder name if you skip the metadata file, but you'll lose the stable resource binding — prefer including it)

The JSON should look like:

```json
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "## SOC Overview Dashboard\nThis workbook provides..."
      }
    }
  ],
  "styleSettings": {},
  "$schema": "https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json"
}
```

## Metadata File (metadata.json) — Optional

Provides a stable GUID and display name. If omitted, the display name is derived from the folder name and a deterministic GUID is generated.

```json
{
  "workbookId": "b2c3d4e5-f6a7-8901-bcde-f23456789012",
  "displayName": "SOC Overview Dashboard",
  "description": "Security operations centre overview with key metrics and incident trends."
}
```

### Why use a stable GUID?

Without a stable `workbookId`, re-deployments may create duplicate workbooks instead of updating the existing one. Generate a GUID once with `New-Guid` and commit it in `metadata.json`.

## Authoring with GitHub Copilot

Workbooks don't have a dedicated path-scoped instruction file —
the gallery JSON is portal-exported and rarely hand-authored. The
repo-wide [`.github/copilot-instructions.md`](../../.github/copilot-instructions.md)
covers the metadata + GUID conventions.

Copilot tooling for workbooks:

- Agent `Sentinel-As-Code: Content Editor` — general edits with
  the right post-edit Pester suite (`Test-WorkbookJson.Tests.ps1`)

See [GitHub Copilot setup](../Development/GitHub-Copilot.md) for the full layout.

## Notes

- Workbooks deploy via the `Microsoft.Insights/workbooks` REST API with `category: sentinel`
- The `sourceId` (workspace resource ID) is set automatically by the deployment script
- Workbooks appear in the **My Workbooks** section of the Sentinel Workbooks blade
- Re-deploying with the same GUID updates the existing workbook in place
- Deployment is handled by [`Scripts/Deploy-CustomContent.ps1`](../../Scripts/Deploy-CustomContent.ps1) — see [Scripts.md](../Deployment/Scripts.md#deploy-customcontentps1)
