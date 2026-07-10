# Graph API Migrations

Upcoming Microsoft Graph `security` API changes that affect how the
[Sentinel as Code Toolkit](README.md) models Microsoft Defender XDR custom
detections. Tracked here so the Toolkit's schema, templates, and converters can
be migrated ahead of the removal dates, and so authors know which fields are on
a deprecation path.

This page was migrated from the Toolkit repository's `docs/` folder. The file
paths below (`schemas/`, `templates/`, `src/`) refer to the Toolkit repository,
not this one. See also [Defender Workflows](Defender-Workflows.md) and the
repository [Defender Custom Detections](../Content/Defender-Custom-Detections.md)
schema.

> Source: Microsoft Graph beta reference (`microsoft.graph.security`), verified 2026-07-09.

## Deprecations (all scheduled for removal on 2026-10-01)

| Current shape (used by the Toolkit) | Replacement | Notes |
|---|---|---|
| `detectionAction.responseActions` and all 17 `responseAction` derived types | `detectionAction.automatedActions` (grouped via `automatedActionSet`) | The custom-detection template catalogues every current `responseAction`. Migration means re-mapping each to an `automatedAction`. |
| `detectionRule.isEnabled` (boolean) | `detectionRule.status` (`detectionRuleStatus` enum) | Boolean flag becomes an enum. |
| `alertTemplate.impactedAssets` and the `impacted*Asset` derived types | `alertTemplate.entityMappings` and the `entityMapping` derived types | Entity-mapping shape changes. |

## Where the Toolkit depends on the current shape

- `schemas/defender-custom-detection-schema.json` - models `isEnabled`, `queryCondition`, `schedule`, `detectionAction.alertTemplate` (with `impactedAssets`) and `detectionAction.responseActions`.
- `templates/custom-detection.template.yaml` - uses `isEnabled`, `impactedAssets`, and the full `responseActions` catalogue.
- `src/defender/services/defenderXdrService.ts` - `formatRuleForRepo` and the convert methods pass `responseActions` and `impactedAssets` through unchanged.
- `src/validation/defenderDetectionValidator.ts` - requires `isEnabled`; treats `responseActions` / `impactedAssets` as arrays.

## Migration plan (before 2026-10-01)

1. Extend the schema and validator to accept `automatedActions`, `status`, and `entityMappings` alongside the current fields (dual-read during the transition).
2. Update `defenderXdrService` conversion to emit the new shape.
3. Switch `templates/custom-detection.template.yaml` to `automatedActions` / `status` / `entityMappings`.
4. Remove the deprecated fields once tenants no longer accept the old shape.
