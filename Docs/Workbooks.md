# Workbooks

Custom workbooks for security dashboards and visualisations. Each workbook is a subfolder under [`Workbooks/`](../Workbooks/) containing the gallery template JSON exported from the Sentinel workbook editor, and an optional metadata file.

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

The gallery template JSON exported from the Sentinel workbook editor. To export:

1. Open the workbook in **Microsoft Sentinel > Workbooks**
2. Click **Edit**, then **Advanced Editor** (the `</>` icon)
3. Select the **Gallery Template** tab
4. Copy the full JSON content
5. Save as `workbook.json` in a new subfolder

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

## Notes

- Workbooks deploy via the `Microsoft.Insights/workbooks` REST API with `category: sentinel`
- The `sourceId` (workspace resource ID) is set automatically by the deployment script
- Workbooks appear in the **My Workbooks** section of the Sentinel Workbooks blade
- Re-deploying with the same GUID updates the existing workbook in place
- Deployment is handled by [`Scripts/Deploy-CustomContent.ps1`](../Scripts/Deploy-CustomContent.ps1) — see [Scripts.md](Scripts.md#deploy-customcontentps1)
