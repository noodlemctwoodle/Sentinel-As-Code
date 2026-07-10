# Workbooks

Custom workbooks for security dashboards and visualisations. Each workbook is a subfolder under [`Content/Workbooks/`](../../Content/Workbooks) containing a `workbook.json` (the workbook content) and an optional metadata file.

The `workbook.json` may take either of two accepted shapes (both are valid and both deploy correctly, see [Accepted workbook.json formats](#accepted-workbookjson-formats)):

- a **gallery notebook** (the raw template JSON exported from the Sentinel workbook editor), or
- an **ARM deployment template** that wraps a `Microsoft.Insights/workbooks` resource (as used by [`UnifiNetworkOverview`](../../Content/Workbooks/UnifiNetworkOverview/workbook.json)).

## Folder Structure

```
Content/Workbooks/
  SOCOverview/
    workbook.json           # Workbook content (gallery notebook OR ARM template)
    metadata.json           # Optional: display name, description, category, stable GUID
  IdentityInsights/
    workbook.json
    metadata.json
```

## Accepted workbook.json formats

[`Deploy-CustomWorkbooks`](../../Deploy/content/Deploy-CustomContent.ps1) and the [`Test-WorkbookJson.Tests.ps1`](../../Tests/Test-WorkbookJson.Tests.ps1) Pester suite both accept two `workbook.json` shapes. The format is detected from the top-level keys: a top-level `resources` array selects the ARM branch; a top-level `items` array (with no `resources`) selects the gallery branch.

### Gallery notebook (top-level `version` + `items`)

The raw template JSON exported from the Sentinel workbook editor (**Advanced Editor > Gallery Template**). The whole file is the notebook payload. `Deploy-CustomWorkbooks` sends it verbatim as the workbook's `serializedData`. Most in-repo workbooks (for example `MicrosoftSentinelCostGbp`, `Perimeter81`, `PfSense`, `Safeguard`, `SentinelDataLake`) use this shape. Minimal example:

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

### ARM deployment template (top-level `resources`)

An ARM template whose `$schema` matches `.../deploymentTemplate.json#` and whose `resources` array contains at least one `Microsoft.Insights/workbooks` resource of `kind: shared`. The workbook resource carries `properties.displayName`, `properties.serializedData` (the notebook, JSON-encoded as a string), and `properties.sourceId`. [`UnifiNetworkOverview`](../../Content/Workbooks/UnifiNetworkOverview/workbook.json) is stored in this shape. When it detects the ARM `$schema`, `Deploy-CustomWorkbooks` extracts the inner workbook resource's `serializedData` before the PUT, so the notebook payload (not the ARM wrapper) is what lands in Azure. Abridged example:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "resources": [
    {
      "type": "Microsoft.Insights/workbooks",
      "apiVersion": "2022-04-01",
      "name": "0003f7e4-e283-4884-8000-000071e06f60",
      "kind": "shared",
      "properties": {
        "displayName": "UniFi Network Overview",
        "serializedData": "{\"version\":\"Notebook/1.0\",\"items\":[ ... ]}",
        "sourceId": "[concat(resourceGroup().id, '/providers/Microsoft.OperationalInsights/workspaces/', parameters('workspace'))]",
        "category": "Sentinel"
      }
    }
  ]
}
```

The ARM workbook resource `name` must be a GUID (Sentinel uses it as the workbook resource ID). `Test-WorkbookJson.Tests.ps1` enforces that every ARM workbook resource GUID is unique across `Content/Workbooks/` so two folders cannot silently overwrite the same Azure resource.

## Getting a workbook into the repo

Two ways to author a `workbook.json`.

### Option 1: bulk export via `Export-SentinelWorkbooks.ps1` (recommended)

For exporting many workbooks at once, or for a one-off bootstrap of a workspace into the repo:

```powershell
./Tools/Export-SentinelWorkbooks.ps1 `
    -ResourceGroup 'rg-sentinel-prod' `
    -Workspace     'law-sentinel-prod' `
    -Region        'uksouth'
```

This:

- Lists every workbook in the workspace via the `Microsoft.Insights/workbooks` API (with `canFetchContent=true` so the `serializedData` comes back), filtered to the target workspace.
- Skips Content Hub-managed workbooks by default (override with `-IncludeContentHub`). Content Hub workbooks are identified by cross-referencing `Microsoft.SecurityInsights/metadata` records where `source.kind == 'Solution'` and collecting their `parentId` (the owning workbook resource ID). Large metadata responses are paged via `nextLink`. These workbooks belong to their solution, so bringing them under repo governance would conflict with Content Hub's own update flow.
- For each remaining (Custom) workbook, writes `Content/Workbooks/<FolderName>/workbook.json` (the gallery notebook payload) and `Content/Workbooks/<FolderName>/metadata.json` (display name, description, category, source ID, **and the workbook resource GUID**).
- Rewrites the live workspace ARM resource ID out of the exported JSON, substituting the `/subscriptions/00000000-.../resourcegroups/your-resource-group/.../workspaces/your-workspace` placeholder (`Remove-WorkspaceArmId`, case-insensitive). This is what makes an exported `workbook.json` portable across environments.
- **Folder name = PascalCase compaction of `displayName`** (with the workspace-name suffix stripped by `Remove-WorkspaceSuffix`, which removes the trailing ` - <workspace-name>` that Sentinel appends to instantiated template display names). Non-alphanumeric runs become word boundaries; all-upper acronyms TitleCase to match the repo convention (`GBP` → `Gbp`); user-curated camelCase (e.g. `pfSense`) is preserved.

Useful flags and parameters:

| Flag / parameter | Purpose |
| --- | --- |
| `-SubscriptionId` | Optional. Target subscription; defaults to the current `Az` context's subscription when omitted |
| `-BasePath` | Optional. Repo root that output is written under (`<BasePath>/Content/Workbooks/`); defaults to the repository root (parent of `Tools/`) |
| `-Filter '^Identity'` | Regex applied to `displayName` (default `.`, i.e. everything); only matching workbooks export |
| `-OnlyMissing` | Skip workbooks that already have a folder under `Content/Workbooks/`. Useful for incremental import without overwriting in-repo customisations |
| `-IncludeContentHub` | Also export Content Hub-managed workbooks (advanced; off by default) |
| `-WhatIf` | Read everything, write nothing |
| `-IsGov` | Target Azure Government cloud |

`ResourceGroup`, `Workspace` and `Region` are mandatory.

Symmetry contract: the output shape exactly matches what [`Deploy-CustomWorkbooks`](../../Deploy/content/Deploy-CustomContent.ps1) reads back, including the workbook resource GUID, so the next deploy run updates the same Azure resource rather than spawning a duplicate.

### Curation-preserving metadata merge

When a `metadata.json` already exists, the export does not blindly overwrite it (`Merge-WorkbookMetadata`). The REST API returns sparse metadata (most workbooks come back with `description = ''` and `category = 'sentinel'`), so curated repo values are protected:

- `displayName`: the API value wins, but existing capitalisation is preserved when the two match case-insensitively (author-curated casing survives).
- `description`: an existing non-empty value wins over an empty API value.
- `category`: an existing non-empty value wins over the generic API default.
- `workbookId`: taken from the API's workbook resource GUID.
- Any extra keys the author added to `metadata.json` (tags, custom annotations) are carried through unchanged.

### Option 2: manual per-workbook export

For exporting a single workbook ad hoc:

1. Open the workbook in **Microsoft Sentinel > Workbooks**
2. Click **Edit**, then **Advanced Editor** (the `</>` icon)
3. Select the **Gallery Template** tab
4. Copy the full JSON content
5. Save as `workbook.json` in a new subfolder (see [Accepted workbook.json formats](#accepted-workbookjson-formats) for the gallery-notebook and ARM-template shapes)
6. Optionally hand-author the matching `metadata.json` (if you skip it, `Deploy-CustomWorkbooks` derives a deterministic GUID by hashing `<WorkspaceResourceId>-<FolderName>` with SHA256, so the same folder deployed to two different workspaces gets two different stable GUIDs; hand-authoring a `workbookId` keeps the binding stable across workspaces, so prefer including it)

## Metadata File (metadata.json, optional)

Provides a stable GUID, display name, and `category`. If omitted, the display name is derived from the folder name (`SOCOverview` -> `SOC Overview`) and a deterministic GUID is generated from the workspace resource ID plus the folder name.

```json
{
  "workbookId": "b2c3d4e5-f6a7-8901-bcde-f23456789012",
  "displayName": "SOC Overview Dashboard",
  "description": "Security operations centre overview with key metrics and incident trends.",
  "category": "Sentinel"
}
```

`Deploy-CustomWorkbooks` reads `displayName`, `workbookId` and `category` from this file. `category` defaults to `sentinel` only when the file omits it; when present it is sent verbatim (existing repo metadata uses values like `Network` for `PfSense` and `Sentinel` for `MicrosoftSentinelCostGbp`).

### Why use a stable GUID?

Without a stable `workbookId`, the fallback GUID is scoped to the target workspace (a SHA256 hash of `<WorkspaceResourceId>-<FolderName>`), so the same workbook resolves to different resources in different workspaces, and re-deployments may create duplicates instead of updating the existing one. Generate a GUID once with `New-Guid` and commit it in `metadata.json` for a workspace-independent binding.

## Authoring with GitHub Copilot

Workbooks don't have a dedicated path-scoped instruction file;
the workbook JSON is portal-exported and rarely hand-authored. The
repo-wide [`.github/copilot-instructions.md`](../../.github/copilot-instructions.md)
covers the metadata + GUID conventions.

Copilot tooling for workbooks:

- Agent `Sentinel-As-Code: Content Editor`, general edits with
  the right post-edit Pester suite ([`Test-WorkbookJson.Tests.ps1`](../../Tests/Test-WorkbookJson.Tests.ps1))

`Test-WorkbookJson.Tests.ps1` validates every `Content/Workbooks/<Name>/workbook.json`: it confirms each file parses to a JSON mapping, detects and validates whichever of the two accepted formats it uses (ARM template resources or gallery notebook `version`+`items`), checks that ARM `serializedData` itself decodes to a notebook with `version` and `items`, validates any sibling `metadata.json` for `displayName`+`sourceId`, and enforces that every ARM workbook resource GUID is unique across the tree.

See [GitHub Copilot setup](../GitHub/GitHub-Copilot.md) for the full layout.

## Notes

- Workbooks deploy via the `Microsoft.Insights/workbooks` REST API (api-version from `$script:WorkbookApiVersion`, currently `2022-04-01`), as `kind: shared`. The body `category` comes from `metadata.json` and only defaults to `sentinel` when unset
- The `sourceId` in the deploy body (workspace resource ID) is set automatically by the deployment script
- Workbooks appear in the **My Workbooks** section of the Sentinel Workbooks blade
- Re-deploying with the same GUID updates the existing workbook in place
- Deployment is handled by [`Deploy/content/Deploy-CustomContent.ps1`](../../Deploy/content/Deploy-CustomContent.ps1), see [Scripts.md](../Deploy/Scripts.md#deploy-customcontentps1)
