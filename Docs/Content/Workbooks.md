# Workbooks

Custom workbooks for security dashboards and visualisations. Each workbook is a subfolder under [`Content/Workbooks/`](../../Content/Workbooks) containing a `workbook.json` (the workbook content) and an optional metadata file.

> This page covers the **format and deploy mechanics** common to every workbook.
> Workbooks with their own reference page:
> [Detection Engineering Dashboard](Workbooks/Detection-Engineering-Dashboard.md).

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

`Deploy-iSOCContent` and the [`Test-WorkbookJson.Tests.ps1`](../../Tests/Test-WorkbookJson.Tests.ps1) Pester suite both accept two `workbook.json` shapes. The format is detected from the top-level keys: a top-level `resources` array selects the ARM branch; a top-level `items` array (with no `resources`) selects the gallery branch.

### Gallery notebook (top-level `version` + `items`)

The raw template JSON exported from the Sentinel workbook editor (**Advanced Editor > Gallery Template**). The whole file is the notebook payload. `Deploy-iSOCContent` sends it verbatim as the workbook's `serializedData`. Most in-repo workbooks (for example `MicrosoftSentinelCostGbp`, `Perimeter81`, `PfSense`, `Safeguard`, `SentinelDataLake`) use this shape. Minimal example:

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

An ARM template whose `$schema` matches `.../deploymentTemplate.json#` and whose `resources` array contains at least one `Microsoft.Insights/workbooks` resource of `kind: shared`. The workbook resource carries `properties.displayName`, `properties.serializedData` (the notebook, JSON-encoded as a string), and `properties.sourceId`. [`UnifiNetworkOverview`](../../Content/Workbooks/UnifiNetworkOverview/workbook.json) is stored in this shape. When it detects the ARM `$schema`, `Deploy-iSOCContent` extracts the inner workbook resource's `serializedData` before the PUT, so the notebook payload (not the ARM wrapper) is what lands in Azure. Abridged example:

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

### Option 1: bulk export with `Export-iSOCContent` (recommended)

`Export-iSOCContent -ContentType Workbook`, in the iSOCDeployments module,
replaces `Tools/Export-SentinelWorkbooks.ps1`, which was removed in release
26.11.0. [Export](../Modules/iSOCDeployments/Export.md) describes what a run
does and maps each old parameter to the command.

For exporting many workbooks at once, or for a one-off bootstrap of a workspace into the repo:

```powershell
Import-Module ./Modules/iSOCDeployments
Connect-AzAccount
Connect-iSOCWorkspace -ResourceGroup 'rg-sentinel-prod' -WorkspaceName 'law-sentinel-prod'

# What it would write, writing nothing.
Export-iSOCContent -ContentType Workbook -WhatIf

# The workbooks the repository does not have yet.
Export-iSOCContent -ContentType Workbook
```

This:

- Reads every workbook in the workspace through the `Microsoft.Insights/workbooks` API and classes each by its source, the same way `Compare-iSOCContent` does.
- Skips Content Hub-managed workbooks by default (add `-IncludeContentHub`). These workbooks belong to their solution, so bringing them under repo governance would conflict with Content Hub's own update flow.
- Skips workbooks the repository already has, found by `workbookId`, unless `-Force` is given. `-Force` writes over them in place.
- For each remaining workbook, writes `Content/Workbooks/<FolderName>/workbook.json` (the gallery notebook payload) and `Content/Workbooks/<FolderName>/metadata.json` (display name, description, category, source ID, **and the workbook resource GUID**).
- Replaces the live workspace ARM resource ID in the exported JSON with the `/subscriptions/00000000-.../resourcegroups/your-resource-group/.../workspaces/your-workspace` placeholder. This is what makes an exported `workbook.json` portable across environments.
- **Folder name = PascalCase compaction of `displayName`**, with the trailing ` - <workspace-name>` that Sentinel appends to instantiated template display names removed. Non-alphanumeric runs become word boundaries; all-upper acronyms TitleCase to match the repo convention (`GBP` becomes `Gbp`); user-curated camelCase (for example `pfSense`) is preserved.

Useful parameters:

| Parameter | Purpose |
| --- | --- |
| `-Name` | Wildcard applied to the display name; only matching workbooks export |
| `-Force` | Write over workbooks the repository already has (by default only missing ones are written) |
| `-IncludeContentHub` | Also export Content Hub-managed workbooks (advanced; off by default) |
| `-RepoPath` | Repo root that output is written under; defaults to the repository root |
| `-Path` | Write the files under another folder at their repository-relative paths |
| `-WhatIf` | Read everything, write nothing |

The subscription, resource group, workspace and cloud come from `Connect-iSOCWorkspace` and the Az sign-in, so there is nothing to pass for them.

Symmetry contract: the output shape exactly matches what `Deploy-iSOCContent` reads back, including the workbook resource GUID, so the next deploy run updates the same Azure resource rather than spawning a duplicate.

### Curation-preserving metadata merge

When a `metadata.json` already exists, the export does not blindly overwrite it. The REST API returns sparse metadata (most workbooks come back with `description = ''` and `category = 'sentinel'`), so curated repo values are protected:

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
6. Optionally hand-author the matching `metadata.json` (if you skip it, `Deploy-iSOCContent` derives a deterministic GUID by hashing `<WorkspaceResourceId>-<FolderName>` with SHA256, so the same folder deployed to two different workspaces gets two different stable GUIDs; hand-authoring a `workbookId` keeps the binding stable across workspaces, so prefer including it)

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

`Deploy-iSOCContent` reads `displayName`, `workbookId` and `category` from this file. `category` defaults to `sentinel` only when the file omits it; when present it is sent verbatim (existing repo metadata uses values like `Network` for `PfSense` and `Sentinel` for `MicrosoftSentinelCostGbp`).

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
- Deployment is handled by `Deploy-iSOCContent` in the iSOCDeployments module, see [Deploy](../Modules/iSOCDeployments/Deploy.md)
